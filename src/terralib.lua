-- See Copyright Notice in ../LICENSE.txt


--io.write("loading terra lib...")


-- LINE COVERAGE INFORMATION, CLEANUP OR REMOVE
--[[
local converageloader = loadfile("coverageinfo.lua")
local linetable = converageloader and converageloader() or {}
function terra.dumplineinfo()
    local F = io.open("coverageinfo.lua","w")
    F:write("return {\n")
    for k,v in pairs(linetable) do
        F:write("["..k.."] = "..v..";\n")
    end
    F:write("}\n")
    F:close()
end

local function debughook(event)
    local info = debug.getinfo(2,"Sl")
    if info.short_src == "src/terralib.lua" then
        linetable[info.currentline] = linetable[info.currentline] or 0
        linetable[info.currentline] = linetable[info.currentline] + 1
    end
end
debug.sethook(debughook,"l")
]]

local ffi = require("ffi")

terra.isverbose = 0 --set by C api

local function dbprint(level,...) 
    if terra.isverbose >= level then
        print(...)
    end
end
local function dbprintraw(level,obj)
    if terra.isverbose >= level then
        obj:printraw()
    end
end

--debug wrapper around cdef function to print out all the things being defined
local oldcdef = ffi.cdef
ffi.cdef = function(...)
    dbprint(2,...)
    return oldcdef(...)
end

-- TREE
terra.tree = {} --metatype for trees
terra.tree.__index = terra.tree
function terra.tree:is(value)
    return self.kind == terra.kinds[value]
end
 
function terra.tree:printraw()
    local function header(key,t)
        if type(t) == "table" and (getmetatable(t) == nil or type(getmetatable(t).__index) ~= "function") then
            local kt = t["kind"]
            return (type(kt) == "number" and terra.kinds[kt]) or (type(kt) == "string" and kt) or ""
        elseif (key == "type" or key == "operator") and type(t) == "number" then
            return terra.kinds[t] .. " (enum " .. tostring(t) .. ")"
        else
            return tostring(t)
        end
    end
    local function isList(t)
        return type(t) == "table" and #t ~= 0
    end
    local parents = {}
    local depth = 0
    local function printElem(t,spacing)
        if(type(t) == "table") then
            if parents[t] then
                print(string.rep(" ",#spacing).."<cyclic reference>")
                return
            elseif depth > 0 and (terra.isfunction(t) or terra.isfunctiondefinition(t)) then
                return --don't print the entire nested function...
            end
            parents[t] = true
            depth = depth + 1
            for k,v in pairs(t) do
                if type(k) == "table" and not terra.issymbol(k) then
                    print("this table:")
                    terra.tree.printraw(k)
                    error("table is key?")
                end
                if k ~= "kind" and k ~= "offset" --[[and k ~= "linenumber"]] then
                    local prefix = spacing..tostring(k)..": "
                    if terra.types.istype(v) then --dont print the raw form of types unless printraw was called directly on the type
                        print(prefix..tostring(v))
                    else
                        print(prefix..header(k,v))
                        if isList(v) then
                            printElem(v,string.rep(" ",2+#spacing))
                        else
                            printElem(v,string.rep(" ",2+#prefix))
                        end
                    end
                end
            end
            depth = depth - 1
            parents[t] = nil
        end
    end
    print(header(nil,self))
    if type(self) == "table" then
        printElem(self,"  ")
    end
end

function terra.tree:copy(new_tree)
    if not new_tree then
        print(debug.traceback())
        error("empty tree?")
    end
    for k,v in pairs(self) do
        if not new_tree[k] then
            new_tree[k] = v
        end
    end
    return setmetatable(new_tree,getmetatable(self))
end

function terra.newtree(ref,body)
    if not ref or not terra.istree(ref) then
        terra.tree.printraw(ref)
        print(debug.traceback())
        error("not a tree?",2)
    end
    body.offset = ref.offset
    body.linenumber = ref.linenumber
    body.filename = ref.filename
    return setmetatable(body,terra.tree)
end

function terra.newanchor(depth)
    local info = debug.getinfo(1 + depth,"Sl")
    local body = { linenumber = info.currentline, filename = info.short_src }
    return setmetatable(body,terra.tree)
end

function terra.istree(v) 
    return terra.tree == getmetatable(v)
end

-- END TREE


-- LIST
terra.list = {} --used for all ast lists
setmetatable(terra.list,{ __index = table })
terra.list.__index = terra.list
function terra.newlist(lst)
    if lst == nil then
        lst = {}
    end
    return setmetatable(lst,terra.list)
end

function terra.list:map(fn)
    local l = terra.newlist()
    for i,v in ipairs(self) do
        l[i] = fn(v)
    end 
    return l
end
function terra.list:flatmap(fn)
    local l = terra.newlist()
    for i,v in ipairs(self) do
        local tmp = fn(v)
        if terra.islist(tmp) then
            for _,v2 in ipairs(tmp) do
                l:insert(v2)
            end
        else
            l:insert(tmp)
        end
    end 
    return l
end


function terra.list:printraw()
    for i,v in ipairs(self) do
        if v.printraw then
            print(i,v:printraw())
        else
            print(i,v)
        end
    end
end
function terra.list:mkstring(begin,sep,finish)
    if sep == nil then
        begin,sep,finish = "",begin,""
    end
    local len = #self
    if len == 0 then return begin..finish end
    local str = begin .. tostring(self[1])
    for i = 2,len do
        str = str .. sep .. tostring(self[i])
    end
    return str..finish
end

function terra.islist(exp)
    return getmetatable(exp) == terra.list
end

-- END LIST

-- CONTEXT
terra.context = {}
terra.context.__index = terra.context

function terra.context:isempty()
    return #self.stack == 0
end

function terra.context:begin(obj) --obj is currently only a funcdefinition
    obj.compileindex = self.nextindex
    obj.lowlink = obj.compileindex
    self.nextindex = self.nextindex + 1
    
    self.diagnostics:begin()
    
    table.insert(self.stack,obj)
    table.insert(self.tobecompiled,obj)
end

function terra.context:finish(anchor)
    local obj = table.remove(self.stack)
    if obj.lowlink == obj.compileindex then
        local scc = terra.newlist()
        local functions = terra.newlist()
        repeat
            local tocompile = table.remove(self.tobecompiled)
            scc:insert(tocompile)
            assert(tocompile.state == "typechecking")
            functions:insert(tocompile)
        until tocompile == obj
        
        if self.diagnostics:haserrors() then
            for i,o in ipairs(scc) do
                o.state = "error"
            end
        else
            for i,o in ipairs(scc) do
                terra.codegen(o)
                o.state = "emittedllvm"
            end
            terra.optimize({ functions = functions, flags = self.compileflags })
            --dispatch callbacks that should occur once the llvm is emitted
            for i,o in ipairs(scc) do
                if o.oncompletion then
                    for i,fn in ipairs(o.oncompletion) do
                        terra.invokeuserfunction(anchor,false,fn,o)
                    end    
                    o.oncompletion = nil
                end
            end
        end
    end
    self.diagnostics:finish()
end

function terra.context:oncompletion(obj,callback)
    obj.oncompletion = obj.oncompletion or terra.newlist()
    obj.oncompletion:insert(callback)
end

function terra.context:referencefunction(anchor, func)
    local curobj = self.stack[#self.stack]
    if func.state == "untyped" then
        func:typecheck()
        assert(terra.types.istype(func.type))
        curobj.lowlink = math.min(curobj.lowlink,func.lowlink)
        return func.type
    elseif func.state == "typechecking" then
        curobj.lowlink = math.min(curobj.lowlink,func.compileindex)
        local success, typ = func:peektype()
        if not success then
            self.diagnostics:reporterror(anchor,"recursively called function needs an explicit return type.")
            if func.untypedtree then
                self.diagnostics:reporterror(anchor,"definition of recursively called function is here.")
            end
        end
        return typ
    elseif func.state == "compiled" or func.state == "emittedllvm" then
        assert(terra.types.istype(func.type))
        return func.type
    elseif func.state == "uninitializedc" then
        func:initializecfunction(anchor)
        assert(terra.types.istype(func.type))
        return func.type
    elseif func.state == "error" then
        assert(terra.types.istype(func.type))
        if not self.diagnostics:haserrors() then --the error that caused this function to not compile may have been reported in a previous compile
                                                 --if we don't have any errors preventing the current compile from succeeding, then
                                                 --we need to emit one here
            self.diagnostics:reporterror(anchor,"expression references a function which failed to compile.")
            if func.untypedtree then
                self.diagnostics:reporterror(func.untypedtree,"definition of function which failed to compile.")
            end
        end
        return terra.types.error
    end
end

function terra.getcompilecontext()
    if not terra.globalcompilecontext then
        terra.globalcompilecontext = setmetatable({definitions = {}, diagnostics = terra.newdiagnostics() , stack = {}, tobecompiled = {}, nextindex = 0, compileflags = {}},terra.context)
    end
    return terra.globalcompilecontext
end

-- END CONTEXT

-- ENVIRONMENT

terra.environment = {}
terra.environment.__index = terra.environment

function terra.environment:enterblock()
    local e = {}
    self._containedenvs[e] = true
    self._localenv = setmetatable(e,{ __index = self._localenv })
end
function terra.environment:leaveblock()
    self._containedenvs[self._localenv] = nil
    self._localenv = getmetatable(self._localenv).__index
end
function terra.environment:localenv()
    return self._localenv
end
function terra.environment:luaenv()
    return self._luaenv
end
function terra.environment:combinedenv()
    return self._combinedenv
end
function terra.environment:insideenv(env)
    return self._containedenvs[env]
end

function terra.newenvironment(_luaenv)
    local self = setmetatable({},terra.environment)
    self._luaenv = _luaenv
    self._containedenvs = {} --map from env -> true for environments we are inside
    self._combinedenv = setmetatable({}, {
        __index = function(_,idx)
            return self._localenv[idx] or self._luaenv[idx]
        end;
        __newindex = function() 
            error("cannot define global variables or assign to upvalues in an escape")
        end;
    })
    self:enterblock()
    return self
end



-- END ENVIRONMENT


-- DIAGNOSTICS

terra.diagnostics = {}
terra.diagnostics.__index = terra.diagnostics

--terra.printlocation
--and terra.opensourcefile are inserted by C wrapper
function terra.diagnostics:printsource(anchor)
    if not anchor.offset then 
        return
    end
    local filename = anchor.filename
    local handle = self.filecache[filename] or terra.opensourcefile(filename)
    self.filecache[filename] = handle
    
    if handle then --if the code did not come from a file then we don't print the carrot, since we cannot (easily) find the text
        terra.printlocation(handle,anchor.offset)
    end
end

function terra.diagnostics:clearfilecache()
    for k,v in pairs(self.filecache) do
        terra.closesourcefile(v)
    end
    self.filecache = {}
end

function terra.diagnostics:reporterror(anchor,...)
    self._haserrors[#self._haserrors] = true
    if not anchor then
        print(debug.traceback())
        error("nil anchor")
    end
    io.write(anchor.filename..":"..anchor.linenumber..": ")
    for _,v in ipairs({...}) do
        io.write(tostring(v))
    end
    io.write("\n")
    self:printsource(anchor)
end

function terra.diagnostics:haserrors()
    return self._haserrors[#self._haserrors]
end

function terra.diagnostics:begin()
    table.insert(self._haserrors,false)
end

function terra.diagnostics:finish()
    local haderrors = table.remove(self._haserrors)
    local top = #self._haserrors
    assert(top > 0)
    self._haserrors[top] = self._haserrors[top] or haderrors
    return haderrors
end

function terra.diagnostics:finishandabortiferrors(msg,depth)
    local haderrors = table.remove(self._haserrors)
    if haderrors then
        self:clearfilecache()
        error(msg,depth+1)
    else
        assert(#self.filecache == 0)
    end
end

function terra.newdiagnostics()
    return setmetatable({ filecache = {}, _haserrors = { true } },terra.diagnostics)
end

-- END DIAGNOSTICS

-- FUNCVARIANT

-- a function definition is an implementation of a function for a particular set of arguments
-- functions themselves are overloadable. Each potential implementation is its own function definition
-- with its own compile state, type, AST, etc.
 
terra.funcdefinition = {} --metatable for all function types
terra.funcdefinition.__index = terra.funcdefinition

function terra.funcdefinition:peektype() --look at the type but don't compile the function (if possible)
                                      --this will return success, <type if success == true>
    if self.type then
        return true,self.type
    end
    if not self.untypedtree.return_types then
        return false, terra.types.error
    end

    local params = self.untypedtree.parameters:map(function(entry) return entry.type end)
    local rets   = self.untypedtree.return_types
    self.type = terra.types.functype(params,rets) --for future calls
    
    return true, self.type
end

function terra.funcdefinition:gettype(cont)
    self:emitllvm(cont)
    assert(cont or self.type ~= nil) --either this was asynchronous and type can be nil, or it wasn't so type needs to be set
    return self.type
end

function terra.funcdefinition:jit()
    if self.state == "emittedllvm" then
        terra.jit({ func = self, flags = {} })
        self.state = "compiled"
    end
end

function terra.funcdefinition:compile(cont)
    if self.state == "compiled" then
        if cont and type(cont) == "function" then
            cont(self)
        end
        return
    end
    
    if cont then 
        self:emitllvm(function()
            self:jit()
            if type(cont) == "function" then
                cont(self)
            end
        end)
    else
        self:emitllvm()
        self:jit()
    end
end

function terra.funcdefinition:initializecfunction(anchor)
    assert(self.state == "uninitializedc")
    terra.registercfunction(self)
    --make sure all types for function are registered
    self.type:complete(anchor)
    self.state = "compiled"
end

function terra.funcdefinition:emitllvm(cont)
    if self.state == "untyped" then
        local ctx = terra.getcompilecontext()
        ctx.diagnostics:begin()
        self:typecheck()
        ctx.diagnostics:finishandabortiferrors("Errors reported during compilation.",2)
    end

    if self.state == "compiled" or self.state == "emittedllvm" then
        --pass
    elseif self.state == "uninitializedc" then --this is a stub generated by the c wrapper, connect it with the right llvm_function object and set fptr
        self:initializecfunction(nil)
    elseif self.state == "typechecking" then
        if cont then
            if type(cont) == "function" then
                terra.getcompilecontext():oncompletion(self,cont)
            end
            return
        else
            error("attempting to compile a function that is already being compiled",2)
        end
    elseif self.state == "error" then
        error("attempting to compile a function which already has an error",2)
    end

    if cont and type(cont) == "function" then
        cont(self)
    end
end

function terra.funcdefinition:__call(...)
    local ffiwrapper = self:getpointer()
    local NR = #self.type.returns
    if NR <= 1 then --fast path
        return ffiwrapper(...)
    else
        --multireturn
        local rs = ffiwrapper(...)
        local rl = {}
        for i = 0,NR-1 do
            table.insert(rl,rs["_"..i])
        end
        return unpack(rl)
    end
end
function terra.funcdefinition:getpointer()
    self:compile()
    if not self.ffiwrapper then
        self.ffiwrapper = ffi.cast(self.type:cstring(),self.fptr)
    end
    return self.ffiwrapper
end

terra.llvm_gcdebugmetatable = { __gc = function(obj)
    print("GC IS CALLED")
end }

function terra.isfunctiondefinition(obj)
    return getmetatable(obj) == terra.funcdefinition
end

--END FUNCDEFINITION

-- FUNCTION
-- a function is a list of possible function definitions that can be invoked
-- it is implemented this way to support function overloading, where the same symbol
-- may have different definitions

terra.func = {} --metatable for all function types
terra.func.__index = terra.func

function terra.func:compile(cont)
    for i,v in ipairs(self.definitions) do
        v:compile(cont)
    end
end
function terra.func:emitllvm(cont)
    for i,v in ipairs(self.definitions) do
        v:emitllvm(cont)
    end
end

function terra.func:__call(...)
    if self.fastcall then
        return self.fastcall(...)
    end
    if #self.definitions == 1 then --generate fast path for the non-overloaded case
        local defn = self.definitions[1]
        local ptr = defn:getpointer() --forces compilation
        local NR = #defn.type.returns
        if NR <= 1 then
            self.fastcall = ptr
        else
            self.fastcall = defn
        end
        return self.fastcall(...)
    end
    
    local results
    for i,v in ipairs(self.definitions) do
        --TODO: this is very inefficient, we should have a routine which
        --figures out which function to call based on argument types
        results = {pcall(v.__call,v,...)}
        if results[1] == true then
            table.remove(results,1)
            return unpack(results)
        end
    end
    --none of the definitions worked, remove the final error
    error(results[2])
end

function terra.func:adddefinition(v)
    self.fastcall = nil
    self.definitions:insert(v)
end

function terra.func:getdefinitions()
    return self.definitions
end

function terra.func:printstats()
    self:compile()
    for i,v in ipairs(self.definitions) do
        print("definition ", v.type)
        for k,v in pairs(v.stats) do
            print("",k,v)
        end
    end
end

function terra.func:disas()
    self:compile()
    for i,v in ipairs(self.definitions) do
        print("definition ", v.type)
        terra.disassemble(v)
    end
end

function terra.isfunction(obj)
    return getmetatable(obj) == terra.func
end

-- END FUNCTION

-- GLOBALVAR

terra.globalvar = {} --metatable for all global variables
terra.globalvar.__index = terra.globalvar

function terra.isglobalvar(obj)
    return getmetatable(obj) == terra.globalvar
end

function terra.globalvar:gettype()
    return self.type
end

--terra.createglobal provided by tcompiler.cpp
function terra.global(a0, a1)
    local typ,c
    if terra.types.istype(a0) then
        typ = a0
        if a1 then
            c = terra.constant(typ,a1)
        end
    else
        c = terra.constant(a0)
        typ = c.type
    end
    
    local gbl =  setmetatable({type = typ, isglobal = true, initializer = c},terra.globalvar)
    
    if c then --if we have an initializer we know that the type is not opaque and we can create the variable
              --we need to call this now because it is possible for the initializer's underlying cdata object to change value
              --in later code
        gbl:getpointer()
    end

    return gbl
end

function terra.globalvar:getpointer()
    if not self.llvm_ptr then
        self.type:complete()
        terra.createglobal(self)
    end
    if not self.cdata_ptr then
        self.cdata_ptr = terra.cast(terra.types.pointer(self.type),self.llvm_ptr)
    end
    return self.cdata_ptr
end
function terra.globalvar:get()
    local ptr = self:getpointer()
    return ptr[0]
end
function terra.globalvar:set(v)
    local ptr = self:getpointer()
    ptr[0] = v
end
    

-- END GLOBALVAR

-- MACRO

terra.macro = {}
terra.macro.__index = terra.macro
terra.macro.__call = function(self,ctx,tree,...)
    if self._internal then
        return self.fn(ctx,tree,...)
    else
        return self.fn(...)
    end
end

function terra.ismacro(t)
    return getmetatable(t) == terra.macro
end

function terra.createmacro(fn)
    return setmetatable({fn = fn}, terra.macro)
end
function terra.internalmacro(fn) 
    local m = terra.createmacro(fn)
    m._internal = true
    return m
end

_G["macro"] = terra.createmacro --introduce macro intrinsic into global namespace

-- END MACRO


function terra.israwlist(l)
    if terralib.islist(l) then
        return true
    elseif type(l) == "table" and not getmetatable(l) then
        local sz = #l
        local i = 0
        for k,v in pairs(l) do
            i = i + 1
        end
        return i == sz --table only has integer keys and no other keys, we treat it as a list
    end
    return false
end

-- QUOTE
terra.quote = {}
terra.quote.__index = terra.quote
function terra.isquote(t)
    return getmetatable(t) == terra.quote
end

function terra.quote:astype()
    local obj = (self.tree:is "typedexpressionlist" and self.tree.expressions[1]) or self.tree
    if not obj:is "luaobject" or not terra.types.istype(obj.value) then
        error("quoted value is not a type")
    end
    return obj.value
end

function terra.quote:gettype()
    if not self.tree:is "typedexpressionlist" then
        error("not a typed quote")
    end
    local exps = self.tree.expressions 
    if #exps == 0 then
        error("expected at least one expression in quote")
    end
    local exp = exps[1]
    if not terra.types.istype(exp.type) then
        error("not a typed quote")
    end
    return exp.type
end

function terra.quote:asvalue()
    
    local function getvalue(e)
        if e:is "literal" then
            if type(e.value) == "userdata" then
                return tonumber(ffi.cast("uint64_t *",e.value)[0])
            else
                return e.value
            end
        elseif e:is "constant" then
            return tonumber(e.value.object) or e.value.object
        elseif e:is "constructor" then
            local t = {}
            for i,r in ipairs(e.records) do
                t[r.key] = getvalue(e.expressions.expressions[i])
            end
            return t
        elseif e:is "typedexpressionlist" then
            local e1 = e.expressions[1]
            return (e1 and getvalue(e1)) or {} 
        else
             error("the rest of :asvalue() needs to be implemented...")
        end
    end
    
    local v = getvalue(self.tree)
    
    return v
end
function terra.newquote(tree)
    return setmetatable({ tree = tree }, terra.quote)
end

-- END QUOTE

-- SYMBOL
terra.symbol = {}
terra.symbol.__index = terra.symbol
function terra.issymbol(s)
    return getmetatable(s) == terra.symbol
end
terra.symbol.count = 0

function terra.newsymbol(typ,displayname)
    if typ and not terra.types.istype(typ) then
        if type(typ) == "string" and displayname == nil then
            displayname = typ
            typ = nil
        else
            error("argument is not a type",2)
        end
    end
    local self = setmetatable({
        id = terra.symbol.count,
        type = typ,
        displayname = displayname
    },terra.symbol)
    terra.symbol.count = terra.symbol.count + 1
    return self
end

function terra.symbol:__tostring()
    return "$"..(self.displayname or tostring(self.id))
end

_G["symbol"] = terra.newsymbol 

-- INTRINSIC

function terra.intrinsic(str, typ)
    local typefn
    if typ == nil and type(str) == "function" then
        typefn = str
    elseif type(str) == "string" and terra.types.istype(typ) then
        typefn = function() return str,typ end
    else
        error("expected a name and type or a function providing a name and type but found "..tostring(str) .. ", " .. tostring(typ))
    end
    local function intrinsiccall(diag,tree,...)
        local args = terra.newlist({...}):map(function(e) return e.tree end)
        return terra.newtree(tree, { kind = terra.kinds.intrinsic, typefn = typefn, arguments = args } )
    end
    return terra.internalmacro(intrinsiccall)
end
    

-- CONSTRUCTORS
do  --constructor functions for terra functions and variables
    local name_count = 0
    local function manglename(nm)
        local fixed = nm:gsub("[^A-Za-z0-9]","_") .. name_count --todo if a user writes terra foo, pass in the string "foo"
        name_count = name_count + 1
        return fixed
    end
    local function newfunctiondefinition(newtree,name,env,reciever)
        local rawname = (name or newtree.filename.."_"..newtree.linenumber.."_")
        local fname = manglename(rawname)
        local obj = { untypedtree = newtree, filename = newtree.filename, name = fname, state = "untyped", stats = {} }
        local fn = setmetatable(obj,terra.funcdefinition)
        
        --handle desugaring of methods defintions by adding an implicit self argument
        if reciever ~= nil then
            local pointerto = terra.types.pointer
            local addressof = terra.newtree(newtree, { kind = terra.kinds.luaexpression, expression = function() return pointerto(reciever) end })
            local sym = terra.newtree(newtree, { kind = terra.kinds.symbol, name = "self"})
            local implicitparam = terra.newtree(newtree, { kind = terra.kinds.entry, name = sym, type = addressof })
            
            --add the implicit parameter to the parameter list
            local newparameters = terra.newlist{implicitparam}
            for _,p in ipairs(newtree.parameters) do
                newparameters:insert(p)
            end
            fn.untypedtree = newtree:copy { parameters = newparameters} 
        end
        local starttime = terra.currenttimeinseconds() 
        fn.untypedtree = terra.specialize(fn.untypedtree,env,3)
        fn.stats.specialize = terra.currenttimeinseconds() - starttime
        return fn
    end
    
    local function mkfunction(name)
        return setmetatable({definitions = terra.newlist(), name = name},terra.func)
    end
    
    local function layoutstruct(st,tree,env)
        local diag = terra.newdiagnostics()
        diag:begin()
        if st.tree then
            diag:reporterror(tree,"attempting to redefine struct")
            diag:reporterror(st.tree,"previous definition was here")
        end
        st.undefined = nil

        local function getstructentry(v)
            local success,resolvedtype = terra.evalluaexpression(diag,env,v.type)
            if not success then return end
            if not terra.types.istype(resolvedtype) then
                diag:reporterror(v,"lua expression is not a terra type but ", type(resolvedtype))
                return terra.types.error
            end
            return { field = v.key, type = resolvedtype }
        end
        
        local function getrecords(records)
            return records:map(function(v)
                if v.kind == terra.kinds["union"] then
                    return getrecords(v.records)
                else
                    return getstructentry(v)
                end
            end)
        end
        st.entries = getrecords(tree.records)
        st.tree = tree --to track whether the struct has already beend defined
                       --we keep the tree to improve error reporting
        st.anchor = tree --replace the anchor generated by newstruct with this struct definition
                         --this will cause errors on the type to be reported at the definition
        diag:finishandabortiferrors("Errors reported during struct definition.",3)

    end

    local function declareobjects(N,declfn,...)
        local idx,args,results = 1,{...},{}
        for i = 1,N do
            local origv,name = args[idx], args[idx+1]
            results[i] = declfn(origv,name)
            idx = idx + 2
        end
        return unpack(results)
    end
    function terra.declarestructs(N,...)
        return declareobjects(N,function(origv,name)
            if terra.types.istype(origv) and origv:isstruct() then
                return origv
            else
                local st = terra.types.newstruct(name,3)
                st.undefined = true
                return st
            end 
        end,...)
    end
    function terra.declarefunctions(N,...)
        return declareobjects(N,function(origv,name)
            return (terra.isfunction(origv) and origv) or mkfunction(name)
        end,...)
    end

    function terra.defineobjects(fmt,envfn,...)
        local args = {...}
        local idx = 1
        local results = {}
        for i = 1, #fmt do
            local c = fmt:sub(i,i)
            local obj, name, tree = args[idx], args[idx+1], args[idx+2]
            idx = idx + 3
            if "s" == c then
                layoutstruct(obj,tree,envfn())
            elseif "f" == c or "m" == c then
                local reciever = nil
                if "m" == c then
                    reciever = args[idx]
                    idx = idx + 1
                end
                obj:adddefinition(newfunctiondefinition(tree,name,envfn(),reciever))
            else
                error("unknown object format: "..c)
            end
        end
    end

    function terra.anonstruct(tree,envfn)
        local st = terra.types.newstruct("anon",2)
        layoutstruct(st,tree,envfn())
        st:setconvertible(true)
        return st
    end

    function terra.anonfunction(tree,envfn)
        local fn = mkfunction(nil)
        fn:adddefinition(newfunctiondefinition(tree,nil,envfn(),nil))
        return fn
    end

    function terra.newcfunction(name,typ)
        local obj = { name = name, type = typ, state = "uninitializedc" }
        setmetatable(obj,terra.funcdefinition)
        
        local fn = mkfunction(name)
        fn:adddefinition(obj)
        
        return fn
    end

    function terra.definequote(tree,envfn)
        return terra.newquote(terra.specialize(tree,envfn(),2))
    end
end

-- END CONSTRUCTORS

-- TYPE

do --construct type table that holds the singleton value representing each unique type
   --eventually this will be linked to the LLVM object representing the type
   --and any information about the operators defined on the type
    local types = {}
    
    
    types.type = {} --all types have this as their metatable
    types.type.__index = function(self,key)
        local N = tonumber(key)
        if N then
            return types.array(self,N) -- int[3] should create an array
        else
            return types.type[key]  -- int:ispointer() (which translates to int["ispointer"](self)) should look up ispointer in types.type
        end
    end
    
    
    function types.type:__tostring()
        return self.displayname or self.name
    end
    types.type.printraw = terra.tree.printraw
    function types.type:isprimitive()
        return self.kind == terra.kinds.primitive
    end
    function types.type:isintegral()
        return self.kind == terra.kinds.primitive and self.type == terra.kinds.integer
    end
    function types.type:isfloat()
        return self.kind == terra.kinds.primitive and self.type == terra.kinds.float
    end
    function types.type:isarithmetic()
        return self.kind == terra.kinds.primitive and (self.type == terra.kinds.integer or self.type == terra.kinds.float)
    end
    function types.type:islogical()
        return self.kind == terra.kinds.primitive and self.type == terra.kinds.logical
    end
    function types.type:canbeord()
        return self:isintegral() or self:islogical()
    end
    function types.type:ispointer()
        return self.kind == terra.kinds.pointer
    end
    function types.type:isarray()
        return self.kind == terra.kinds.array
    end
    function types.type:isfunction()
        return self.kind == terra.kinds.functype
    end
    function types.type:isstruct()
        return self.kind == terra.kinds["struct"]
    end
    function types.type:ispointertostruct()
        return self:ispointer() and self.type:isstruct()
    end
    function types.type:ispointertofunction()
        return self:ispointer() and self.type:isfunction()
    end
    function types.type:isaggregate() 
        return self:isstruct() or self:isarray()
    end
    
    function types.type:iscomplete()
        return not self.incomplete
    end
    
    function types.type:isvector()
        return self.kind == terra.kinds.vector
    end
    
    local applies_to_vectors = {"isprimitive","isintegral","isarithmetic","islogical", "canbeord"}
    for i,n in ipairs(applies_to_vectors) do
        types.type[n.."orvector"] = function(self)
            return self[n](self) or (self:isvector() and self.type[n](self.type))  
        end
    end
    
    local next_type_id = 0 --used to generate uniq type names
    local function uniquetypename(base,name) --used to generate unique typedefs for C
        base = base:gsub("%.","_")
        local r = base.."_"
        if name then
            r = r..name.."_"
        end
        r = r..next_type_id
        next_type_id = next_type_id + 1
        return r
    end
    

    local function memoize(data)
        local name = data.name
        local defaultvalue = data.defaultvalue
        local erroronrecursion = data.erroronrecursion
        local getvalue = data.getvalue

        local errorresult = { "<errorresult>" }
        local key = "cached"..name
        local inside = "inget"..name
        return function(self,anchor)
            if not self[key] then
                local diag = terra.getcompilecontext().diagnostics
                local haderrors = diag:haserrors()
                diag:begin()
                if self[inside] then
                    diag:reporterror(self.anchor,erroronrecursion)
                else 
                    self[inside] = true
                    self[key] = getvalue(self,diag,anchor or terra.newanchor(1))
                    self[inside] = nil
                end
                if diag:haserrors() then
                    self[key] = errorresult
                end
                if anchor then
                    diag:finish() 
                else
                    diag:finishandabortiferrors("Errors reported during struct property lookup.",2)
                end

            end
            if self[key] == errorresult then
                local msg = "Attempting to get a property of a type that previously resulted in an error."
                if anchor then
                    local diag = terra.getcompilecontext().diagnostics
                    if not diag:haserrors() then
                        diag:reporterror(self.anchor,msg)
                    end
                    return defaultvalue
                else
                    error(msg,2)
                end
            end
            return self[key]
        end
    end

    types.type.cstring = memoize { 
        name  = "cstring";
        defaultvalue = "int";
        erroronrecursion = "cstring called itself?";
        getvalue = function(self,diag)
            local function definetype(base,name,value)
                local nm = uniquetypename(base,name)
                ffi.cdef("typedef "..value.." "..nm..";")
                return nm
            end
            local cstring
            --assumption: cstring needs to be an identifier, it cannot be a derived type (e.g. int*)
            --this makes it possible to predict the syntax of subsequent typedef operations
            if self:isintegral() then
                cstring = tostring(self).."_t"
            elseif self:isfloat() then
                cstring = tostring(self)
            elseif self:ispointer() and self.type:isfunction() then --function pointers and functions have the same typedef
                cstring = self.type:cstring()
            elseif self:ispointer() then
                local value = self.type:cstring()
                cstring = definetype(value,"ptr",value .. "*")
            elseif self:islogical() then
                cstring = "bool"
            elseif self:isstruct() then
                local nm = uniquetypename(self.name)
                ffi.cdef("typedef struct "..nm.." "..nm..";") --just make a typedef to the opaque type
                                                              --when the struct is 
                cstring = nm 
            elseif self:isarray() then
                local value = self.type:cstring()
                local nm = uniquetypename(value,"arr")
                ffi.cdef("typedef "..value.." "..nm.."["..tostring(self.N).."];")
                cstring = nm
            elseif self:isvector() then
                local value = self.type:cstring()
                local nm = uniquetypename(value,"vec")
                ffi.cdef("typedef "..value.." "..nm.." __attribute__ ((vector_size("..tostring(self.N)..")));")
                cstring = nm 
            elseif self:isfunction() then
                local rt = (#self.returns == 0 and "void") or self.returnobj:cstring()
                local function getcstring(t)
                    if t == rawstring then
                        --hack to make it possible to pass strings to terra functions
                        --this breaks some lesser used functionality (e.g. passing and mutating &int8 pointers)
                        --so it should be removed when we have a better solution
                        return "const char *"
                    else
                        return t:cstring()
                    end
                end
                local pa = self.parameters:map(getcstring)
                pa = pa:mkstring("(",",","")
                if self.isvararg then
                    pa = pa .. ",...)"
                else
                    pa = pa .. ")"
                end
                local ntyp = uniquetypename("function")
                local cdef = "typedef "..rt.." (*"..ntyp..")"..pa..";"
                ffi.cdef(cdef)
                cstring = ntyp
            elseif self == types.niltype then
                local nilname = uniquetypename("niltype")
                ffi.cdef("typedef void * "..nilname..";")
                cstring = nilname
            elseif self == types.error then
                cstring = "int"
            else
                error("NYI - cstring")
            end
            if not cstring then error("cstring not set? "..tostring(self)) end
            
            --create a map from this ctype to the terra type to that we can implement terra.typeof(cdata)
            local ctype = ffi.typeof(cstring)
            types.ctypetoterra[tonumber(ctype)] = self
            local rctype = ffi.typeof(cstring.."&")
            types.ctypetoterra[tonumber(rctype)] = self
            return cstring
        end
    }

    local function definecstruct(nm,layout)
        local str = "struct "..nm.." { "
        local entries = layout.entries
        for i,v in ipairs(entries) do
        
            local prevalloc = entries[i-1] and entries[i-1].allocation
            local nextalloc = entries[i+1] and entries[i+1].allocation
    
            if v.inunion and prevalloc ~= v.allocation then
                str = str .. " union { "
            end
            
            local keystr = v.key
            if terra.issymbol(keystr) then
                keystr = "__symbol"..tostring(keystr.id)
            end
            str = str..v.type:cstring().." "..keystr.."; "
            
            if v.inunion and nextalloc ~= v.allocation then
                str = str .. " }; "
            end
            
        end
        str = str .. "};"
        ffi.cdef(str)
    end

    types.type.getentries = memoize{
        name = "entries";
        defaultvalue = terra.newlist();
        erroronrecursion = "recursively calling getentries on type";
        getvalue = function(self,diag,anchor)
            if not self:isstruct() then
                error("attempting to get entries of non-struct type: ", tostring(self))
            end
            local entries = self.entries
            if type(self.metamethods.__getentries) == "function" then
                local success,result = terra.invokeuserfunction(self.anchor,false,self.metamethods.__getentries,self)
                entries = (success and result) or {}
            elseif self.undefined then
                diag:reporterror(anchor,"attempting to use a type before it is defined")
                diag:reporterror(self.anchor,"type was declared here.")
            end
            if not type(entries) == "table" then
                diag:reporterror(self.anchor,"computed entries are not a table")
                return
            end
            local function checkentries(entries)
                for i,e in ipairs(entries) do
                    if type(e) == "table" and terra.types.istype(e.type) then
                        local f = e.field
                        if f and not (type(f) == "string" or terra.issymbol(f)) then
                            diag:reporterror(self.anchor,"entry field must be a string or symbol")
                        end
                    elseif terra.israwlist(e) then
                        checkentries(e)
                    elseif not terra.types.istype(e) then
                        diag:reporterror(self.anchor,"expected a valid entry (either a type, a field-type pair (e.g. { field = <key>, type = <type> }), or a list of valid entries representing a union")
                    end
                end
            end
            checkentries(entries)
            return entries
        end
    }
    types.type.getlayout = memoize {
        name = "layout"; 
        defaultvalue = { entries = terra.newlist(), keytoindex = {}, invalid = true };
        erroronrecursion = "type recursively contains itself";
        getvalue = function(self,diag,anchor)
            local tree = self.anchor
            local entries = self:getentries(anchor)
            local nextallocation = 0
            local nextunnamed = 0
            local uniondepth = 0
            local unionsize = 0
            
            local layout = {
                entries = terra.newlist(),
                keytoindex = {}
            }

            local function addentry(k,t)
                local function ensurelayout(t)
                    if t:isstruct() then
                        t:getlayout(anchor)
                    elseif t:isarray() then
                        ensurelayout(t.type)
                    end
                end
                ensurelayout(t)
                local entry = { type = t, key = k, hasname = true, allocation = nextallocation, inunion = uniondepth > 0 }
                if not k then
                    entry.hasname = false
                    entry.key = "_"..tostring(nextunnamed)
                    nextunnamed = nextunnamed + 1
                end
                
                if layout.keytoindex[entry.key] ~= nil then
                    diag:reporterror(tree,"duplicate field ",tostring(entry.key))
                end

                layout.keytoindex[entry.key] = #layout.entries
                layout.entries:insert(entry)
                
                if uniondepth > 0 then
                    unionsize = unionsize + 1
                else
                    nextallocation = nextallocation + 1
                end
            end
            local function beginunion()
                uniondepth = uniondepth + 1
            end
            local function endunion()
                uniondepth = uniondepth - 1
                if uniondepth == 0 and unionsize > 0 then
                    nextallocation = nextallocation + 1
                    unionsize = 0
                end
            end
            local function addentrylist(entries)
                for i,e in ipairs(entries) do
                    if terra.types.istype(e) then
                        addentry(nil,e)
                    elseif type(e) == "table" and terra.types.istype(e.type) then
                        addentry(e.field,e.type)
                    elseif terra.israwlist(e) then
                        beginunion()
                        addentrylist(e)
                        endunion()
                    else
                        error("internal - invalid entries list?")
                    end
                end
            end
            addentrylist(entries)
            
            dbprint(2,"Resolved Named Struct To:")
            dbprintraw(2,self)
            if not diag:haserrors() then
                definecstruct(self:cstring(),layout)
            end
            return layout
        end;
    }
    function types.type:complete(anchor) 
        if self.incomplete then
            if self:isarray() then
                self.type:complete(anchor)
                self.incomplete = self.type.incomplete
            elseif self:isfunction() then
                local incomplete = nil
                for i,p in ipairs(self.parameters) do
                    incomplete = incomplete or p:complete(anchor).incomplete
                end
                for i,r in ipairs(self.returns) do
                    incomplete = incomplete or r:complete(anchor).incomplete
                end
                if self.returnobj then
                    incomplete = incomplete or self.returnobj:complete(anchor).incomplete
                end
                self.incomplete = incomplete
            else
                assert(self:isstruct())
                local layout = self:getlayout(anchor)
                if not layout.invalid then
                    self.incomplete = nil --static initializers run only once
                                          --if one of the members of this struct recursively
                                          --calls complete on this type, then it will return before the static initializer has run
                    for i,e in ipairs(layout.entries) do
                        e.type:complete(anchor)
                    end
                    if type(self.metamethods.__staticinitialize) == "function" then
                        terra.invokeuserfunction(self.anchor,false,self.metamethods.__staticinitialize,self)
                    end
                end
            end
        end
        return self
    end
        
    function types.istype(t)
        return getmetatable(t) == types.type
    end
    
    --map from unique type identifier string to the metadata for the type
    types.table = {}
    
    --map from luajit ffi ctype objects to corresponding terra type
    types.ctypetoterra = {}
    
    local function mktyp(v)
        return setmetatable(v,types.type)
    end
    local function mkincomplete(v)
        v.incomplete = true
        return setmetatable(v,types.type)
    end
    
    local function registertype(name, constructor)
        local typ = types.table[name]
        if typ == nil then
            if types.istype(constructor) then
                typ = constructor
            elseif type(constructor) == "function" then
                typ = constructor()
            else
                error("expected function or type")
            end
            typ.name = name
            types.table[name] = typ
        end
        return typ
    end
    
    --initialize integral types
    local integer_sizes = {1,2,4,8}
    for _,size in ipairs(integer_sizes) do
        for _,s in ipairs{true,false} do
            local name = "int"..tostring(size * 8)
            if not s then
                name = "u"..name
            end
            local typ = mktyp { kind = terra.kinds.primitive, bytes = size, type = terra.kinds.integer, signed = s}
            registertype(name,typ)
            typ:cstring() -- force registration of integral types so calls like terralib.typeof(1LL) work
        end
    end  
    
    registertype("float", mktyp { kind = terra.kinds.primitive, bytes = 4, type = terra.kinds.float })
    registertype("double",mktyp { kind = terra.kinds.primitive, bytes = 8, type = terra.kinds.float })
    registertype("bool",  mktyp { kind = terra.kinds.primitive, bytes = 1, type = terra.kinds.logical})
    
    types.error   = registertype("error",  mktyp { kind = terra.kinds.error })
    types.niltype = registertype("niltype",mktyp { kind = terra.kinds.niltype}) -- the type of the singleton nil (implicitly convertable to any pointer type)
    
    local function checkistype(typ)
        if not types.istype(typ) then 
            error("expected a type but found "..type(typ))
        end
    end
    
    function types.pointer(typ)
        checkistype(typ)
        if typ == types.error then return types.error end
        
        return registertype("&"..typ.name, function()
            return mktyp { kind = terra.kinds.pointer, type = typ }
        end)
    end
    
    local function checkarraylike(typ, N_)
        local N = tonumber(N_)
        checkistype(typ)
        if not N then
            error("expected a number but found "..type(N_))
        end
        return N
    end
    
    function types.array(typ, N_)
        local N = checkarraylike(typ,N_)
        if typ == types.error then return types.error end
        
        local tname = (typ:ispointer() and "("..typ.name..")") or typ.name
        local name = tname .. "[" .. N .. "]"
        return registertype(name,function()
            return mkincomplete { kind = terra.kinds.array, type = typ, N = N }
        end)
    end
    
    function types.vector(typ,N_)
        local N = checkarraylike(typ,N_)
        if typ == types.error then return types.error end
        
        
        if not typ:isprimitive() then
            error("vectors must be composed of primitive types (for now...) but found type "..tostring(typ))
        end
        local name = "vector("..typ.name..","..N..")"
        return registertype(name,function()
            return mktyp { kind = terra.kinds.vector, type = typ, N = N }
        end)
    end
    
    function types.primitive(name)
        return types.table[name] or types.error
    end
    
    
    local definedstructs = {}
    local function getuniquestructname(displayname)
        local name = displayname
        if definedstructs[displayname] then 
            name = name .. tostring(definedstructs[displayname])
        else
            definedstructs[displayname] = 0
        end
        definedstructs[displayname] = definedstructs[displayname] + 1
        return name
    end
    function types.newstruct(displayname,depth)
        if not displayname then
            displayname = "anon"
        end
        if not depth then
            depth = 1
        end
        return types.newstructwithanchor(displayname,terra.newanchor(1 + depth))
    end
    function types.newstructwithanchor(displayname,anchor)
        
        assert(displayname ~= "")
        local name = getuniquestructname(displayname)
                
        local tbl = mkincomplete { kind = terra.kinds["struct"],
                            name = name, 
                            displayname = displayname, 
                            entries = terra.newlist(),
                            methods = {},
                            metamethods = {},
                            anchor = anchor                  
                          }
        function tbl:setconvertible(b)
            assert(self.incomplete)
            self.isconvertible = b
        end
        
        return tbl
    end
    
    function types.funcpointer(parameters,returns,isvararg)
        if types.istype(parameters) then
            parameters = {parameters}
        end
        if types.istype(returns) then
            returns = {returns}
        end
        return types.pointer(types.functype(parameters,returns,isvararg))
    end
    
    function types.functype(parameters,returns,isvararg)
        
        if not terra.islist(parameters) then
            parameters = terra.newlist(parameters)
        end
        if not terra.islist(returns) then
            returns = terra.newlist(returns)
        end
        
        local function checkalltypes(l)
            for i,v in ipairs(l) do
                checkistype(v)
            end
        end
        checkalltypes(parameters)
        checkalltypes(returns)
        
        local function getname(t) return t.name end
        local a = terra.list.map(parameters,getname):mkstring("{",",","")
        if isvararg then
            a = a .. ",...}"
        else
            a = a .. "}"
        end
        local r = terra.list.map(returns,getname):mkstring("{",",","}")
        local name = a.."->"..r
        return registertype(name,function()
            local returnobj = nil
            if #returns == 1 then
                returnobj = returns[1]
            elseif #returns > 1 then
                returnobj = types.newstruct()
                returnobj.entries = returns
            end
            return mkincomplete { kind = terra.kinds.functype, parameters = parameters, returns = returns, isvararg = isvararg, returnobj = returnobj }
        end)
    end
    
    for name,typ in pairs(types.table) do
        --introduce primitive types into global namespace
        -- outside of the typechecker and internal terra modules
        if typ:isprimitive() then
            _G[name] = typ
        end 
    end
    _G["int"] = int32
    _G["uint"] = uint32
    _G["long"] = int64
    _G["intptr"] = uint64
    _G["ptrdiff"] = int64
    _G["niltype"] = types.niltype
    _G["rawstring"] = types.pointer(int8)
    terra.types = types
end

-- END TYPE

-- SPECIALIZATION (removal of escape expressions, escape sugar, evaluation of type expressoins)

--convert a lua value 'v' into the terra tree representing that value
function terra.createterraexpression(diag,anchor,v)
    local function createsingle(v)
        if terra.isglobalvar(v) or terra.issymbol(v) then
            local name = anchor:is "var" and anchor.name and tostring(anchor.name) --propage original variable name for debugging purposes
            return terra.newtree(anchor, { kind = terra.kinds["var"], value = v, name = name or tostring(v), lvalue = true }) 
        elseif terra.isquote(v) then
            assert(terra.istree(v.tree))
            if v.tree:is "block" then
                return terra.newtree(anchor, { kind = terra.kinds.treelist, values = v.tree.statements })
            else
                return v.tree
            end
        elseif terra.istree(v) then
            --if this is a raw tree, we just drop it in place and hope the user knew what they were doing
            return v
        elseif type(v) == "cdata" or type(v) == "number" or type(v) == "boolean" or type(v) == "string" then
            return createsingle(terra.constant(v))
        elseif terra.isconstant(v) then
            if type(v.object) == "string" then --strings are handled specially since they are a pointer type (rawstring) but the constant is actually string data, not just the pointer
                return terra.newtree(anchor, { kind = terra.kinds.literal, value = v.object, type = rawstring })
            else 
                return terra.newtree(anchor, { kind = terra.kinds.constant, value = v, type = v.type, lvalue = v.type:isaggregate()})
            end
        else
            if not (terra.isfunction(v) or terra.ismacro(v) or terra.types.istype(v) or type(v) == "function" or type(v) == "table") then
                diag:reporterror(anchor,"lua object of type ", type(v), " not understood by terra code.")
            end
            return terra.newtree(anchor, { kind = terra.kinds.luaobject, value = v })
        end
    end
    if terra.israwlist(v) then
        local values = terra.newlist()
        for _,i in ipairs(v) do
            values:insert(createsingle(i))
        end
        return terra.newtree(anchor, { kind = terra.kinds.treelist, values = values})
    else
        return createsingle(v)
    end
end

function terra.specialize(origtree, luaenv, depth)
    local env = terra.newenvironment(luaenv)
    local diag = terra.newdiagnostics()
    diag:begin()
    local translatetree, translategenerictree, translatelist, resolvetype, createformalparameterlist, desugarfornum
    function translatetree(e)
        if e:is "var" then
            local v = env:combinedenv()[e.name]
            if v == nil then
                diag:reporterror(e,"variable '"..e.name.."' not found")
                return e
            end
            return terra.createterraexpression(diag,e,v)
        elseif e:is "select" then
            local ee = translategenerictree(e)
            if not ee.value:is "luaobject" then
                return ee
            end
            --note: luaobject only appear due to tree translation, so we can safely mutate ee
            local value,field = ee.value.value, ee.field
            if type(value) ~= "table" then
                diag:reporterror(e,"expected a table but found ", type(value))
                return ee
            end
            

            if terra.types.istype(value) and value:isstruct() then --class method resolve to method table
                value = value.methods
            end

            local selected = value[field]
            if selected == nil then
                diag:reporterror(e,"no field ", field," in lua object")
                return ee
            end
            return terra.createterraexpression(diag,e,selected)
        elseif e:is "luaexpression" then     
            local success, value = terra.evalluaexpression(diag,env:combinedenv(),e)
            return terra.createterraexpression(diag, e, (success and value) or {})
        elseif e:is "symbol" then
            local v
            if e.name then
                v = e.name
            else
                local success, r = terra.evalluaexpression(diag,env:combinedenv(),e.expression)
                if not success then 
                    v = terra.newsymbol(nil,"error")
                elseif type(r) ~= "string" and not terra.issymbol(r) then
                    diag:reporterror(e,"expected a string or symbol but found ",type(r))
                    v = terra.newsymbol(nil,"error")
                else
                    v = r
                end
            end
            return v
        elseif e:is "defvar" then
            local initializers = e.initializers and translatelist(e.initializers)
            local variables = createformalparameterlist(e.variables, initializers == nil)     
            return e:copy { variables = variables, initializers = initializers }
        elseif e:is "function" then
            local parameters = createformalparameterlist(e.parameters,true)
            local return_types
            if e.return_types then
                local success, value = terra.evalluaexpression(diag,env:combinedenv(),e.return_types)
                if not value then
                    diag:reporterror(e.return_types,"expected a type but found nil")
                elseif success then
                    return_types = (terra.israwlist(value) and terra.newlist(value)) or terra.newlist { value }
                    for i,t in ipairs(return_types) do
                        if not terra.types.istype(t) then
                            diag:reporterror(e.return_types,"expected a type but found ",type(t))
                        end
                    end
                end
            end
            local body = translatetree(e.body)
            return e:copy { parameters = parameters, return_types = return_types, body = body }
        elseif e:is "fornum" then
            --we desugar this early on so that we don't have to have special handling for the definitions/scoping
            return translatetree(desugarfornum(e))
        elseif e:is "repeat" then
            --special handling of scope for
            env:enterblock()
            local b = translategenerictree(e.body)
            local c = translatetree(e.condition)
            env:leaveblock()
            if b ~= e.body or c ~= e.condition then
                return e:copy { body = b, condition = c }
            else
                return e
            end
        elseif e:is "block" then
            env:enterblock()
            local r = translategenerictree(e)
            env:leaveblock()
            return r
        else
            return translategenerictree(e)
        end
    end
    function createformalparameterlist(paramlist, requiretypes)
        local result = terra.newlist()
        for i,p in ipairs(paramlist) do
            if i ~= #paramlist or p.type or p.name.name then
                --treat the entry as a _single_ parameter if any are true:
                --if it is not the last entry in the list
                --it has an explicit type
                --it is a string (and hence cannot be multiple items) then
            
                local typ
                if p.type then
                    local success, v = terra.evalluaexpression(diag,env:combinedenv(),p.type)
                    typ = (success and v) or nil
                    if not terra.types.istype(typ) then
                        diag:reporterror(p,"expected a type but found ",type(typ))
                        typ = terra.types.error
                    end
                end
                local function registername(name,sym)
                    local lenv = env:localenv()
                    if rawget(lenv,name) then
                        diag:reporterror(p,"duplicate definition of variable ",name)
                    end
                    lenv[name] = sym
                end
                local symorstring = translatetree(p.name)
                local sym,name
                if type(symorstring) == "string" then
                    name = symorstring
                    if p.name.expression then
                        --in statement: "var [a] : int = ..." don't let 'a' resolve to a string 
                        diag:reporterror(p,"expected a symbol but found string")
                    else
                        --generate a new unique symbol for this variable and add it to the environment
                        --this will allow quotes to see it hygientically and references to it to be resolved to the symbol
                        local name = symorstring
                        local lenv = env:localenv()
                        sym = terra.newsymbol(nil,name)
                        registername(name,sym)
                    end
                else
                    sym = symorstring
                    name = tostring(sym)
                    registername(sym,sym)
                end
                result:insert(p:copy { type = typ, name = name, symbol = sym })
            else
                local sym = p.name
                assert(sym.expression)
                local success, value = terra.evalluaexpression(diag,env:combinedenv(),sym.expression)
                if success then
                    if not value then
                        diag:reporterror(p,"expected a symbol or string but found nil")
                    end
                    local symlist = (terra.israwlist(value) and value) or terra.newlist{ value }
                    for i,entry in ipairs(symlist) do
                        if terra.issymbol(entry) then
                            result:insert(p:copy { symbol = entry, name = tostring(entry) })
                        else
                            diag:reporterror(p,"expected a symbol but found ",type(entry))
                        end
                    end
                end
            end
        end
        for i,entry in ipairs(result) do
            local sym = entry.symbol
            entry.type = entry.type or sym.type --if the symbol was given a type but the parameter didn't have one
                                                --it takes the type of the symbol
            assert(entry.type == nil or terra.types.istype(entry.type))
            if requiretypes and not entry.type then
                diag:reporterror(entry,"type must be specified for parameters and uninitialized variables")
            end
        end
        return result
    end
    function desugarfornum(s)
        local function mkdefs(...)
            local lst = terra.newlist()
            for i,v in pairs({...}) do
                local sym = terra.newtree(s,{ kind = terra.kinds.symbol, name = v})
                lst:insert( terra.newtree(s,{ kind = terra.kinds.entry, name = sym }) )
            end
            return lst
        end
        
        local function mkvar(a)
            assert(type(a) == "string")
            return terra.newtree(s,{ kind = terra.kinds["var"], name = a })
        end
        
        local function mkop(op,a,b)
           a = (type(a) == "string" and mkvar(a)) or a
           b = (type(b) == "string" and mkvar(b)) or b
           return terra.newtree(s, {
            kind = terra.kinds.operator;
            operator = terra.kinds[op];
            operands = terra.newlist { a, b };
            })
        end

        local dv = terra.newtree(s, { 
            kind = terra.kinds.defvar;
            variables = mkdefs("<i>","<limit>","<step>");
            initializers = terra.newlist({s.initial,s.limit,s.step})
        })
        local zero = terra.createterraexpression(diag,s,0LL)
        local lt = mkop("<","<i>","<limit>")
        local gt = mkop(">","<i>","<limit>")
        local slt = mkop("<","<step>",zero)
        local sgt = mkop(">","<step>",zero)
        local cond = mkop("or",mkop("and",sgt,lt),
                               mkop("and",slt,gt))
        
        local newstmts = terra.newlist()

        local newvaras = terra.newtree(s, { 
            kind = terra.kinds.defvar;
            variables = terra.newlist{ terra.newtree(s, { kind = terra.kinds.entry, name = s.varname }) };
            initializers = terra.newlist{mkvar("<i>")}
        })
        newstmts:insert(newvaras)
        for _,v in pairs(s.body.statements) do
            newstmts:insert(v)
        end
        
        local p1 = mkop("+","<i>","<step>")
        local as = terra.newtree(s, {
            kind = terra.kinds.assignment;
            lhs = terra.newlist({mkvar("<i>")});
            rhs = terra.newlist({p1});
        })
        
        newstmts:insert(as)
        
        local nbody = terra.newtree(s, {
            kind = terra.kinds.block;
            statements = newstmts;
        })
        
        local wh = terra.newtree(s, {
            kind = terra.kinds["while"];
            condition = cond;
            body = nbody;
        })
    
        return terra.newtree(s, { kind = terra.kinds.block, statements = terra.newlist {dv,wh} } )
    end
    --recursively translate any tree or list of trees.
    --new objects are only created when we find a new value
    function translategenerictree(tree)
        assert(terra.istree(tree))
        local nt = nil
        local function addentry(k,origv,newv)
            if origv ~= newv then
                if not nt then
                    nt = tree:copy {}
                end
                nt[k] = newv
            end
        end
        for k,v in pairs(tree) do
            if terra.istree(v) then
                addentry(k,v,translatetree(v))
            elseif terra.islist(v) and #v > 0 and terra.istree(v[1]) then
                addentry(k,v,translatelist(v))
            end 
        end
        return nt or tree
    end
    function translatelist(lst)
        local changed = false
        local nl = lst:map(function(e)
            assert(terra.istree(e)) 
            local ee = translatetree(e)
            changed = changed or ee ~= e
            return ee
        end)
        return (changed and nl) or lst
    end
    
    dbprint(2,"specializing tree")
    dbprintraw(2,origtree)

    local newtree = translatetree(origtree)
    
    diag:finishandabortiferrors("Errors reported during specialization.",depth+1)
    return newtree
end

-- TYPECHECKER

function terra.evalluaexpression(diag, env, e)
    local function parseerrormessage(startline, errmsg)
        local line,err = errmsg:match [["$terra$"]:([0-9]+):(.*)]]
        if line and err then
            return startline + tonumber(line) - 1, "error evaluating lua code: " .. err
        else
            return startline, "error evaluating lua code: " .. errmsg
        end
    end
    if not terra.istree(e) or not e:is "luaexpression" then
       print(debug.traceback())
       terra.tree.printraw(e)
       error("not a lua expression?") 
    end
    assert(type(e.expression) == "function")
    local fn = e.expression
    setfenv(fn,env)
    local success,v = pcall(fn)
    if not success then --v contains the error message
        local ln,err = parseerrormessage(e.linenumber,v)
        diag:reporterror(e:copy( { linenumber = ln }),err)
        return false
    end
    return true,v
end

--all calls to user-defined functions from the compiler go through this wrapper
function terra.invokeuserfunction(anchor, speculate, userfn,  ...)
    local results = { pcall(userfn, ...) }
    if not speculate and not results[1] then
        local diag = terra.getcompilecontext().diagnostics
        diag:reporterror(anchor,"error while invoking macro or metamethod: ",results[2])
    end
    return unpack(results)
end

function terra.funcdefinition:typecheck()
    
    assert(self.state == "untyped")
    local ctx = terra.getcompilecontext()
    ctx:begin(self)
    self.state = "typechecking"
    local starttime = terra.currenttimeinseconds()
    
    --initialization

    dbprint(2,"compiling function:")
    dbprintraw(2,self.untypedtree)

    local ftree = self.untypedtree
    
    local symbolenv = terra.newenvironment()
    local diag = terra.getcompilecontext().diagnostics

    -- TYPECHECKING FUNCTION DECLARATIONS
    --declarations major driver functions for typechecker
    local checkexp -- (e.g. 3 + 4)
    local checkstmt -- (e.g. var a = 3)
    local checkcall -- any invocation (method, function call, macro, overloaded operator) gets translated into a call to checkcall (e.g. sizeof(int), foobar(3), obj:method(arg))
    local checkparameterlist -- (e.g. 3,4 of foo(3,4))

    --tree constructors for trees created in the typechecking process
    local function createcast(exp,typ)
        return terra.newtree(exp, { kind = terra.kinds.cast, from = exp.type, to = typ, type = typ:complete(exp), expression = exp })
    end
    
    local function createtypedexpressionlist(anchor, explist, fncall, minsize)
        assert(terra.islist(explist))
        return terra.newtree(anchor, { kind = terra.kinds.typedexpressionlist, expressions = explist, fncall = fncall, key = symbolenv:localenv(), minsize = minsize or 0})
    end
    local function createextractreturn(fncall, index, t)
        return terra.newtree(fncall,{ kind = terra.kinds.extractreturn, index = index, type = t:complete(fncall), fncall = fncall})
    end
    local function createfunctionliteral(anchor,e)
        local fntyp = ctx:referencefunction(anchor,e)
        local typ = terra.types.pointer(fntyp)
        return terra.newtree(anchor, { kind = terra.kinds.literal, value = e, type = typ })
    end
    

    local function asrvalue(ee)
        if ee.lvalue then
            return terra.newtree(ee,{ kind = terra.kinds.ltor, type = ee.type, expression = ee })
        else
            return ee
        end
    end
    local function aslvalue(ee) --this is used in a few cases where we allow rvalues to become lvalues
                          -- int[4] -> int * conversion, and invoking a method that requires a pointer on an rvalue
        if not ee.lvalue then
            if ee.kind == terra.kinds.ltor then --sometimes we might as for an rvalue and then convert to an lvalue (e.g. on casts), we just undo that here
                return ee.expression
            else
                return terra.newtree(ee,{ kind = terra.kinds.rtol, type = ee.type, expression = ee })
            end
        else
            return ee
        end
    end
    
    local function insertaddressof(ee)
        local e = aslvalue(ee)
        local ret = terra.newtree(e,{ kind = terra.kinds.operator, type = terra.types.pointer(ee.type), operator = terra.kinds["&"], operands = terra.newlist{e} })
        return ret
    end
    local function insertdereference(ee)
        local e = asrvalue(ee)
        local ret = terra.newtree(e,{ kind = terra.kinds.operator, operator = terra.kinds["@"], operands = terra.newlist{e}, lvalue = true })
        if not e.type:ispointer() then
            diag:reporterror(e,"argument of dereference is not a pointer type but ",e.type)
            ret.type = terra.types.error 
        elseif e.type.type:isfunction() then
            --function pointer dereference does nothing, return the input
            return e
        else
            ret.type = e.type.type:complete(e)
        end
        return ret
    end
    
    local function insertvar(anchor, typ, name, definition)
        return terra.newtree(anchor, { kind = terra.kinds["var"], type = typ:complete(anchor), name = name, definition = definition, lvalue = true }) 
    end

    local function insertselect(v, field)
        local tree = terra.newtree(v, { type = terra.types.error, kind = terra.kinds.select, field = field, value = v, lvalue = v.lvalue })
        assert(v.type:isstruct())
        local layout = v.type:getlayout(v)
        local index = layout.keytoindex[field]
        
        if index == nil then
            return nil,false
        end
        tree.index = index
        tree.type = layout.entries[index+1].type:complete(v)
        return tree,true
    end

    --wrappers for l/rvalue version of checking functions
    local function checkrvalue(e)
        local ee = checkexp(e)
        return asrvalue(ee)
    end

    local function checklvalue(ee)
        local e = checkexp(ee)
        if not e.lvalue then
            diag:reporterror(e,"argument to operator must be an lvalue")
            e.type = terra.types.error
        end
        return e
    end

    --functions handling casting between types
    
    local insertcast --handles implicitly allowed casts (e.g. var a : int = 3.5)
    local insertexplicitcast --handles casts performed explicitly (e.g. var a = int(3.5))
    local structcast -- handles casting from an anonymous structure type to another struct type (e.g. StructFoo { 3, 5 })
    local insertrecievercast -- handles casting for method recievers, which allows for an implicit addressof operator to be inserted

    -- all implicit casts (struct,reciever,generic) take a speculative argument
    --if speculative is true, then errors will not be reported (caller must check)
    --this is used to see if an overloaded function can apply to the argument list

    function structcast(cast,exp,typ, speculative) 
        local from = exp.type:getlayout(exp)
        local to = typ:getlayout(exp)

        local valid = true
        local function err(...)
            valid = false
            if not speculative then
                diag:reporterror(exp,...)
            end
        end
        
        cast.structvariable = terra.newtree(exp, { kind = terra.kinds.entry, name = "<structcast>", type = exp.type:complete(exp) })
        local var_ref = insertvar(exp,exp.type,cast.structvariable.name,cast.structvariable)
        
        local indextoinit = {}
        for i,entry in ipairs(from.entries) do
            local selected = asrvalue(insertselect(var_ref,entry.key))
            if entry.hasname then
                local offset = to.keytoindex[entry.key]
                if not offset then
                    err("structural cast invalid, result structure has no key ", entry.key)
                else
                    if indextoinit[offset] then
                        err("structural cast invalid, ",entry.key," initialized more than once")
                    end
                    indextoinit[offset] = insertcast(selected,to.entries[offset+1].type)
                end
            else
                local offset = 0
                
                --find the first non initialized entry
                while offset < #to.entries and indextoinit[offset] do
                    offset = offset + 1
                end
                local totyp = to.entries[offset+1] and to.entries[offset+1].type
                local maxsz = #to.entries
                
                if offset == maxsz then
                    err("structural cast invalid, too many unnamed fields")
                else
                    indextoinit[offset] = insertcast(selected,totyp)
                end
            end
        end
        
        cast.entries = terra.newlist()
        for i,v in pairs(indextoinit) do
            cast.entries:insert( { index = i, value = v } )
        end
        
        return cast, valid
    end

    function insertcast(exp,typ,speculative) --if speculative is true, then an error will not be reported and the caller should check the second return value to see if the cast was valid
        if typ == nil then
            print(debug.traceback())
        end
        if typ == exp.type or typ == terra.types.error or exp.type == terra.types.error then
            return exp, true
        else
            local cast_exp = createcast(exp,typ)
            if ((typ:isprimitive() and exp.type:isprimitive()) or
                (typ:isvector() and exp.type:isvector() and typ.N == exp.type.N)) and
               not typ:islogicalorvector() and not exp.type:islogicalorvector() then
                return cast_exp, true
            elseif typ:ispointer() and exp.type:ispointer() and typ.type == uint8 then --implicit cast from any pointer to &uint8
                return cast_exp, true
            elseif typ:ispointer() and exp.type == terra.types.niltype then --niltype can be any pointer
                return cast_exp, true
            elseif typ:isstruct() and exp.type:isstruct() and exp.type.isconvertible then 
                return structcast(cast_exp,exp,typ,speculative)
            elseif typ:ispointer() and exp.type:isarray() and typ.type == exp.type.type then
                --if we have an rvalue array, it must be converted to lvalue (i.e. placed on the stack) before the cast is valid
                cast_exp.expression = aslvalue(cast_exp.expression)
                return cast_exp, true
            elseif typ:isvector() and exp.type:isprimitive() then
                local primitivecast, valid = insertcast(exp,typ.type,speculative)
                local broadcast = createcast(primitivecast,typ)
                return broadcast, valid
            end

            --no builtin casts worked... now try user-defined casts
            local cast_fns = terra.newlist()
            local function addcasts(typ)
                if typ:isstruct() and typ.metamethods.__cast then
                    cast_fns:insert(typ.metamethods.__cast)
                elseif typ:ispointertostruct() then
                    addcasts(typ.type)
                end
            end
            addcasts(exp.type)
            addcasts(typ)

            local errormsgs = terra.newlist()
            for i,__cast in ipairs(cast_fns) do
                local tel = createtypedexpressionlist(exp,terra.newlist{exp},nil)
                local quotedexp = terra.newquote(tel)
                local success,result = terra.invokeuserfunction(exp, true,__cast,exp.type,typ,quotedexp)
                if success then
                    local result = checkrvalue(terra.createterraexpression(diag,exp,result))
                    if result.type ~= typ then 
                        diag:reporterror(exp,"user-defined cast returned expression with the wrong type.")
                    end
                    return result
                else
                    errormsgs:insert(result)
                end
            end

            if not speculative then
                diag:reporterror(exp,"invalid conversion from ",exp.type," to ",typ)
                for i,e in ipairs(errormsgs) do
                    diag:reporterror(exp,"user-defined cast failed: ",e)
                end
            end
            return cast_exp, false
        end
    end
    function insertexplicitcast(exp,typ) --all implicit casts are allowed plus some additional casts like from int to pointer, pointer to int, and int to int
        if typ == exp.type then
            return exp
        elseif typ:ispointer() and exp.type:ispointer() then
            return createcast(exp,typ)
        elseif typ:ispointer() and exp.type:isintegral() then --int to pointer
            return createcast(exp,typ)
        elseif typ:isintegral() and exp.type:ispointer() then
            if typ.bytes < intptr.bytes then
                diag:reporterror(exp,"pointer to ",typ," conversion loses precision")
            end
            return createcast(exp,typ)
        elseif (typ:isprimitive() and exp.type:isprimitive())
            or (typ:isvector() and exp.type:isvector() and typ.N == exp.type.N) then --explicit conversions from logicals to other primitives are allowed
            return createcast(exp,typ)
        else
            return insertcast(exp,typ) --otherwise, allow any implicit casts
        end
    end
    function insertrecievercast(exp,typ,speculative) --casts allow for method recievers a:b(c,d) ==> b(a,c,d), but 'a' has additional allowed implicit casting rules
                                                      --type can also be == "vararg" if the expected type of the reciever was an argument to the varargs of a function (this often happens when it is a lua function)
         if typ == "vararg" then
             return insertaddressof(exp), true
         elseif typ:ispointer() and not exp.type:ispointer() then
             --implicit address of allowed for recievers
             return insertcast(insertaddressof(exp),typ,speculative)
         else
            return insertcast(exp,typ,speculative)
        end
        --notes:
        --we force vararg recievers to be a pointer
        --an alternative would be to return reciever.type in this case, but when invoking a lua function as a method
        --this would case the lua function to get a pointer if called on a pointer, and a value otherwise
        --in other cases, you would consistently get a value or a pointer regardless of receiver type
        --for consistency, we all lua methods take pointers
        --TODO: should we also consider implicit conversions after the implicit address/dereference? or does it have to match exactly to work?
    end


    --functions to typecheck operator expressions
    
    local function typemeet(op,a,b)
        local function err()
            diag:reporterror(op,"incompatible types: ",a," and ",b)
        end
        if a == terra.types.error or b == terra.types.error then
            return terra.types.error
        elseif a == b then
            return a
        elseif a.kind == terra.kinds.primitive and b.kind == terra.kinds.primitive then
            if a:isintegral() and b:isintegral() then
                if a.bytes < b.bytes then
                    return b
                elseif a.bytes > b.bytes then
                    return a
                elseif a.signed then
                    return b
                else --a is unsigned but b is signed
                    return a
                end
            elseif a:isintegral() and b:isfloat() then
                return b
            elseif a:isfloat() and b:isintegral() then
                return a
            elseif a:isfloat() and b:isfloat() then
                return double
            else
                err()
                return terra.types.error
            end
        elseif a:ispointer() and b == terra.types.niltype then
            return a
        elseif a == terra.types.niltype and b:ispointer() then
            return b
        elseif a:isvector() and b:isvector() and a.N == b.N then
            local rt, valid = typemeet(op,a.type,b.type)
            return (rt == terra.types.error and rt) or terra.types.vector(rt,a.N)
        elseif (a:isvector() and b:isprimitive()) or (b:isvector() and a:isprimitive()) then
            if a:isprimitive() then
                a,b = b,a --ensure a is vector and b is primitive
            end
            local rt = typemeet(op,a.type,b)
            return (rt == terra.types.error and rt) or terra.types.vector(rt,a.N)
        else    
            err()
            return terra.types.error
        end
    end

    local function typematch(op,lstmt,rstmt)
        local inputtype = typemeet(op,lstmt.type,rstmt.type)
        return inputtype, insertcast(lstmt,inputtype), insertcast(rstmt,inputtype)
    end

    local function checkunary(ee,operands,property)
        local e = operands[1]
        if e.type ~= terra.types.error and not e.type[property](e.type) then
            diag:reporterror(e,"argument of unary operator is not valid type but ",e.type)
            return e:copy { type = terra.types.error }
        end
        return ee:copy { type = e.type, operands = terra.newlist{e} }
    end 
    
    
    local function meetbinary(e,property,lhs,rhs)
        local t,l,r = typematch(e,lhs,rhs)
        if t ~= terra.types.error and not t[property](t) then
            diag:reporterror(e,"arguments of binary operator are not valid type but ",t)
            return e:copy { type = terra.types.error }
        end
        return e:copy { type = t, operands = terra.newlist {l,r} }
    end
    
    local function checkbinaryorunary(e,operands,property)
        if #operands == 1 then
            return checkunary(e,operands,property)
        end
        return meetbinary(e,property,operands[1],operands[2])
    end
    
    local function checkarith(e,operands)
        return checkbinaryorunary(e,operands,"isarithmeticorvector")
    end

    local function checkarithpointer(e,operands)
        if #operands == 1 then
            return checkunary(e,operands,"isarithmeticorvector")
        end
        
        local l,r = unpack(operands)
        
        local function pointerlike(t)
            return t:ispointer() or t:isarray()
        end
        local function ascompletepointer(exp) --convert pointer like things into pointers to _complete_ types
            exp.type.type:complete(exp)
            return (insertcast(exp,terra.types.pointer(exp.type.type))) --parens are to truncate to 1 argument
        end
        -- subtracting 2 pointers
        if  pointerlike(l.type) and pointerlike(r.type) and l.type.type == r.type.type and e.operator == terra.kinds["-"] then
            return e:copy { type = ptrdiff, operands = terra.newlist {ascompletepointer(l),ascompletepointer(r)} }
        elseif pointerlike(l.type) and r.type:isintegral() then -- adding or subtracting a int to a pointer
            return e:copy { type = terra.types.pointer(l.type.type), operands = terra.newlist {ascompletepointer(l),r} }
        elseif l.type:isintegral() and pointerlike(r.type) then
            return e:copy { type = terra.types.pointer(r.type.type), operands = terra.newlist {ascompletepointer(r),l} }
        else
            return meetbinary(e,"isarithmeticorvector",l,r)
        end
    end

    local function checkintegralarith(e,operands)
        return checkbinaryorunary(e,operands,"isintegralorvector")
    end
    
    local function checkcomparision(e,operands)
        local t,l,r = typematch(e,operands[1],operands[2])
        local rt = bool
        if t:isvector() then
            rt = terra.types.vector(bool,t.N)
        end
        return e:copy { type = rt, operands = terra.newlist {l,r} }
    end
    
    local function checklogicalorintegral(e,operands)
        return checkbinaryorunary(e,operands,"canbeordorvector")
    end
    
    local function checkshift(ee,operands)
        local a,b = unpack(operands)
        local typ = terra.types.error
        if a.type ~= terra.types.error and b.type ~= terra.types.error then
            if a.type:isintegralorvector() and b.type:isintegralorvector() then
                if a.type:isvector() then
                    typ = a.type
                elseif b.type:isvector() then
                    typ = terra.types.vector(a.type,b.type.N)
                else
                    typ = a.type
                end
                
                a = insertcast(a,typ)
                b = insertcast(b,typ)
            
            else
                diag:reporterror(ee,"arguments to shift must be integers but found ",a.type," and ", b.type)
            end
        end
        
        return ee:copy { type = typ, operands = terra.newlist{a,b} }
    end
    
    
    local function checkifelse(ee,operands)
        local cond = operands[1]
        local t,l,r = typematch(ee,operands[2],operands[3])
        if cond.type ~= terra.types.error and t ~= terra.types.error then
            if cond.type:isvector() and cond.type.type == bool then
                if not t:isvector() or t.N ~= cond.type.N then
                    diag:reporterror(ee,"conditional in select is not the same shape as ",cond.type)
                end
            elseif cond.type ~= bool then
                print(ee)
                diag:reporterror(ee,"expected a boolean or vector of booleans but found ",cond.type)   
            end
        end
        return ee:copy { type = t, operands = terra.newlist{cond,l,r}}
    end

    local operator_table = {
        ["-"] = { checkarithpointer, "__sub", "__unm" };
        ["+"] = { checkarithpointer, "__add" };
        ["*"] = { checkarith, "__mul" };
        ["/"] = { checkarith, "__div" };
        ["%"] = { checkarith, "__mod" };
        ["<"] = { checkcomparision, "__lt" };
        ["<="] = { checkcomparision, "__le" };
        [">"] = { checkcomparision, "__gt" };
        [">="] =  { checkcomparision, "__ge" };
        ["=="] = { checkcomparision, "__eq" };
        ["~="] = { checkcomparision, "__ne" };
        ["and"] = { checklogicalorintegral, "__and" };
        ["or"] = { checklogicalorintegral, "__or" };
        ["not"] = { checklogicalorintegral, "__not" };
        ["^"] =  { checkintegralarith, "__xor" };
        ["<<"] = { checkshift, "__lshift" };
        [">>"] = { checkshift, "__rshift" };
        ["select"] = { checkifelse, "__select"}
    }
    
    local function checkoperator(ee)
        local op_string = terra.kinds[ee.operator]
        
        --check non-overloadable operators first
        if op_string == "@" then
            local e = checkrvalue(ee.operands[1])
            return insertdereference(e)
        elseif op_string == "&" then
            local e = checklvalue(ee.operands[1])
            local ty = terra.types.pointer(e.type)
            return ee:copy { type = ty, operands = terra.newlist{e} }
        end
        
        local op, genericoverloadmethod, unaryoverloadmethod = unpack(operator_table[op_string] or {})
        
        if op == nil then
            diag:reporterror(ee,"operator ",op_string," not defined in terra code.")
            return ee:copy { type = terra.types.error }
        end
        local operands = ee.operands:map(checkexp)
        
        local overloads = terra.newlist()
        for i,e in ipairs(operands) do
            if e.type:isstruct() then
                local overloadmethod = (#operands == 1 and unaryoverloadmethod) or genericoverloadmethod
                local overload = e.type.metamethods[overloadmethod] --TODO: be more intelligent here about merging overloaded functions so that all possibilities are considered
                if overload then
                    overloads:insert(terra.createterraexpression(diag, ee, overload))
                end
            end
        end
        
        if #overloads > 0 then
            local function wrapexp(exp)
                return createtypedexpressionlist(exp,terra.newlist{exp},nil)
            end
            return checkcall(ee, overloads, operands:map(wrapexp), "all", true, false)
        else
            return op(ee,operands:map(asrvalue))
        end

    end

    --functions to handle typecheck invocations (functions,methods,macros,operator overloads)

    function checkparameterlist(anchor,params) --individual params may be already typechecked (e.g. if they were a method call receiver) 
                                                                --in this case they are treated as single expressions
        local exps = terra.newlist()
        local fncall = nil
        
        local minsize = #params --minsize is either the number of explicitly listed parameters (a,b,c) minsize == 3
                                --or 1 less than this number if 'c' is a macro/quotelist that has 0 elements
        for i,p in ipairs(params) do
            if i ~= #params then
                exps:insert(checkrvalue(p))
            else
                local explist = checkexp(p,true,false)
                fncall = explist.fncall
                if #explist.expressions == 0 then
                    minsize = minsize - 1
                end
                for i,a in ipairs(explist.expressions) do
                    exps:insert(asrvalue(a))
                end
            end
        end
        return createtypedexpressionlist(anchor, exps, fncall, minsize)
    end

    local function insertvarargpromotions(param)
        if param.type == float then
            return insertcast(param,double)
        end
        --TODO: do we need promotions for integral data types or does llvm already do that?
        return param
    end

    local function tryinsertcasts(typelists,castbehavior, speculate, allowambiguous, paramlist)
        local minsize, maxsize = paramlist.minsize, #paramlist.expressions
        local function trylist(typelist, speculate)
            local allvalid = true
            if #typelist > maxsize then
                allvalid = false
                if not speculate then
                    diag:reporterror(paramlist,"expected at least "..#typelist.." parameters, but found "..maxsize)
                end
            elseif #typelist < minsize then
                allvalid = false
                if not speculate then
                    diag:reporterror(paramlist,"expected no more than "..#typelist.." parameters, but found at least "..minsize)
                end
            end
            
            local results = terra.newlist{}
            
            for i,param in ipairs(paramlist.expressions) do
                local typ = typelist[i]
                
                local result,valid
                if typ == nil or typ == "passthrough" then
                    result,valid = param,true 
                elseif castbehavior == "all" or (i == 1 and castbehavior == "first") then
                    result,valid = insertrecievercast(param,typ,speculate)
                elseif typ == "vararg" then
                    result,valid = insertvarargpromotions(param),true
                else
                    result,valid = insertcast(param,typ,speculate)
                end
                results[i] = result
                allvalid = allvalid and valid
            end
            
            return results,allvalid
        end
        
        local function shortenparamlist(size)
            if #paramlist.expressions > size then --could already be shorter on error
                for i = size+1,maxsize do
                    paramlist.expressions[i] = nil
                end
                assert(#paramlist.expressions == size) 
            end
        end

        if #typelists == 1 then
            local typelist = typelists[1]    
            local results,allvalid = trylist(typelist,false)
            assert(#results == maxsize)
            paramlist.expressions = results
            shortenparamlist(#typelist)
            return 1
        else
            --evaluate each potential list
            local valididx,validcasts
            for i,typelist in ipairs(typelists) do
                local results,allvalid = trylist(typelist,true)
                if allvalid then
                    if valididx == nil then
                        valididx = i
                        validcasts = results
                        if allowambiguous then
                            break
                        end
                    else
                        local optiona = typelists[valididx]:mkstring("(",",",")")
                        local optionb = typelist:mkstring("(",",",")")
                        diag:reporterror(paramlist,"call to overloaded function is ambiguous. can apply to both ", optiona, " and ", optionb)
                        break
                    end
                end
            end
            
            if valididx then
               paramlist.expressions = validcasts
               shortenparamlist(#typelists[valididx])
            else
                --no options were valid and our caller wants us to, lets emit some errors
                if not speculate then
                    diag:reporterror(paramlist,"call to overloaded function does not apply to any arguments")
                    for i,typelist in ipairs(typelists) do
                        diag:reporterror(paramlist,"option ",i," with type ",typelist:mkstring("(",",",")"))
                        trylist(typelist,false)
                    end
                end
            end
            return valididx
        end
    end
    
    local function insertcasts(typelist,paramlist) --typelist is a list of target types (or the value "passthrough"), paramlist is a parameter list that might have a multiple return value at the end
        return tryinsertcasts(terra.newlist { typelist }, "none", false, false, paramlist)
    end

    local function checkmethodwithreciever(anchor, ismeta, methodname, reciever, arguments, isstatement)
        local objtyp
        reciever.type:complete(anchor)
        if reciever.type:isstruct() then
            objtyp = reciever.type
        elseif reciever.type:ispointertostruct() then
            objtyp = reciever.type.type
            reciever = insertdereference(reciever)
        else
            diag:reporterror(anchor,"attempting to call a method on a non-structural type ",reciever.type)
            return anchor:copy { type = terra.types.error }
        end

        local fnlike
        if ismeta then
            fnlike = objtyp.metamethods[methodname]
        else
            fnlike = objtyp.methods[methodname]
            if not fnlike and terra.ismacro(objtyp.metamethods.__methodmissing) then
                fnlike = terra.internalmacro(function(ctx,tree,...)
                    return objtyp.metamethods.__methodmissing(ctx,tree,methodname,...)
                end)
            end
        end

        if not fnlike then
            diag:reporterror(anchor,"no such method ",methodname," defined for type ",reciever.type)
            return anchor:copy { type = terra.types.error }
        end

        fnlike = terra.createterraexpression(diag, anchor, fnlike) 
        local wrappedrecv = createtypedexpressionlist(anchor,terra.newlist {reciever},nil)
        local fnargs = terra.newlist { wrappedrecv }
        for i,a in ipairs(arguments) do
            fnargs:insert(a)
        end
        
        return checkcall(anchor, terra.newlist { fnlike }, fnargs, "first", false, isstatement)
    end

    local function checkmethod(exp, isstatement)
        local methodname = exp.name
        assert(type(methodname) == "string" or terra.issymbol(methodname))
        local reciever = checkexp(exp.value)
        local arguments = exp.arguments:map( function(a) return checkexp(a,true,true) end )
        return checkmethodwithreciever(exp, false, methodname, reciever, arguments, isstatement)
    end

    local function checkapply(exp, isstatement)
        local fnlike = checkexp(exp.value,false,true)
        local arguments = exp.arguments:map( function(a) return checkexp(a,true,true) end )
    
        if not fnlike:is "luaobject" then
            if fnlike.type:isstruct() or fnlike.type:ispointertostruct() then
                return checkmethodwithreciever(exp, true, "__apply", fnlike, arguments, isstatement) 
            end
            fnlike = asrvalue(fnlike)
        end
        return checkcall(exp, terra.newlist { fnlike } , arguments, "none", false, isstatement)
    end
    
    function checkcall(anchor, fnlikelist, arguments, castbehavior, allowambiguous, isstatement)
        --arguments are always typedexpressions or luaobjects
        for i,a in ipairs(arguments) do
            assert(a:is "typedexpressionlist")
        end
        assert(#fnlikelist > 0)
        
        --collect all the terra functions, stop collecting when we reach the first 
        --alternative that is not a terra function and record it as fnlike
        --we will first attempt to typecheck the terra functions, and if they fail,
        --we will call the macro/luafunction (these can take any argument types so they will always work)
        local terrafunctions = terra.newlist()
        local fnlike = nil
        for i,fn in ipairs(fnlikelist) do
            if fn:is "luaobject" then
                if terra.ismacro(fn.value) or type(fn.value) == "function" then
                    fnlike = fn.value
                    break
                elseif terra.types.istype(fn.value) then
                    local castmacro = terra.internalmacro(function(diag,tree,arg)
                        return terra.newtree(tree, { kind = terra.kinds.explicitcast, value = arg.tree, totype = fn.value })
                    end)
                    fnlike = castmacro
                    break
                elseif terra.isfunction(fn.value) then
                    if #fn.value:getdefinitions() == 0 then
                        diag:reporterror(anchor,"attempting to call undefined function")
                    end
                    for i,v in ipairs(fn.value:getdefinitions()) do
                        local fnlit = createfunctionliteral(anchor,v)
                        if fnlit.type ~= terra.types.error then
                            terrafunctions:insert( fnlit )
                        end
                    end
                else
                    diag:reporterror(anchor,"expected a function or macro but found lua value of type ",type(fn.value))
                end
            elseif fn.type:ispointer() and fn.type.type:isfunction() then
                terrafunctions:insert(fn)
            else
                if fn.type ~= terra.types.error then
                    diag:reporterror(anchor,"expected a function but found ",fn.type)
                end
            end 
        end

        local function createcall(callee, paramlist)
            callee.type.type:complete(anchor)
            local returntypes = callee.type.type.returns
            local paramtypes = paramlist.expressions:map(function(x) return x.type end)
            local fncall = terra.newtree(anchor, { kind = terra.kinds.apply, arguments = paramlist, value = callee, returntypes = returntypes, paramtypes = paramtypes })
            local expressions = terra.newlist()
            for i,rt in ipairs(returntypes) do
                expressions[i] = createextractreturn(fncall,i-1, rt)
            end 
            return createtypedexpressionlist(anchor,expressions,fncall)
        end
        local function generatenativewrapper(fn,paramlist)
            local varargslist = paramlist.expressions:map(function(p) return "vararg" end)
            tryinsertcasts(terra.newlist{varargslist},castbehavior, false, false, paramlist)
            local paramtypes = paramlist.expressions:map(function(p) return p.type end)
            local castedtype = terra.types.funcpointer(paramtypes,{})
            local cb = terra.cast(castedtype,fn)
            local fptr = terra.pointertolightuserdata(cb)
            return terra.newtree(anchor, { kind = terra.kinds.luafunction, callback = cb, fptr = fptr, type = castedtype })
        end

        local paramlist
        if #terrafunctions > 0 then
            paramlist = checkparameterlist(anchor,arguments)
            local function getparametertypes(fn) --get the expected types for parameters to the call (this extends the function type to the length of the parameters if the function is vararg)
                local fntyp = fn.type.type
                if not fntyp.isvararg then
                    return fntyp.parameters
                end
                
                local vatypes = terra.newlist()
                for i,v in ipairs(paramlist.expressions) do
                    if i <= #fntyp.parameters then
                        vatypes[i] = fntyp.parameters[i]
                    else
                        vatypes[i] = "vararg"
                    end
                end
                return vatypes
            end
            local typelists = terrafunctions:map(getparametertypes)
            local valididx = tryinsertcasts(typelists,castbehavior, fnlike ~= nil, allowambiguous, paramlist)
            if valididx then
                return createcall(terrafunctions[valididx],paramlist)
            end
        end

        if fnlike then
            if terra.ismacro(fnlike) then
                local quotes = arguments:map(terra.newquote)
                local success, result = terra.invokeuserfunction(anchor, false, fnlike, diag, anchor, unpack(quotes))
                
                if success then
                    local newexp = terra.createterraexpression(diag,anchor,result)
                    if isstatement then
                        return checkstmt(newexp)
                    else
                        return checkexp(newexp,true,true) --TODO: is true,true right? we will need tests
                    end
                else
                    return anchor:copy { type = terra.types.error }
                end
            elseif type(fnlike) == "function" then
                paramlist = paramlist or checkparameterlist(anchor,arguments)
                local callee = generatenativewrapper(fnlike,paramlist)
                return createcall(callee,paramlist)
            else 
                error("fnlike is not a function/macro?")
            end
        end
        assert(diag:haserrors())
        return anchor:copy { type = terra.types.error }
    end

    --functions that handle the checking of expressions
    
    local function checkintrinsic(e,mustreturnatleast1)
        local params = checkparameterlist(e,e.arguments)
        local paramtypes = terra.newlist()
        for i,p in ipairs(params.expressions) do
            paramtypes:insert(p.type)
        end
        local name,intrinsictype = e.typefn(paramtypes,params.minsize)
        if type(name) ~= "string" then
            diag:reporterror(e,"expected an intrinsic name but found ",tostring(name))
            return e:copy { type = terra.types.error }
        elseif intrinsictype == terra.types.error then
            diag:reporterror(e,"intrinsic ",name," does not support arguments: ",unpack(paramtypes))
            return e:copy { type = terra.types.error }
        elseif not terra.types.istype(intrinsictype) or not intrinsictype:ispointertofunction() then
            diag:reporterror(e,"expected intrinsic to resolve to a function type but found ",tostring(intrinsictype))
            return e:copy { type = terra.types.error }
        elseif (#intrinsictype.type.returns == 0 and mustreturnatleast1) or (#intrinsictype.type.returns > 1) then
            diag:reporterror(e,"intrinsic used in an expression must return 1 argument")
            return e:copy { type = terra.types.error }
        end
        
        insertcasts(intrinsictype.type.parameters,params)
        local rt = intrinsictype.type.returns[1]
        return e:copy { type = rt and rt:complete(e), name = name, arguments = params, intrinsictype = intrinsictype }
    end

    local function truncateexpressionlist(tel)
        assert(tel:is "typedexpressionlist")
        if #tel.expressions == 0 then
            diag:reporterror(tel, "expression resulting in no values used where at least one value is required")
            return tel:copy { type = terra.types.error }
        else
            local r = tel.expressions[1]
            if r:is "extractreturn" then --this is a function call so we need to return a typedexpression list to retain the function call  
                assert(tel.fncall ~= nil)
                assert(terra.types.istype(r.type))
                local result = createtypedexpressionlist(tel,terra.newlist { r }, tel.fncall)
                result.type = r.type
                return result
            else -- it is not a function call node, so we can truncate by just returnting the first element
                return r
            end
        end
    end

    local function checksymbol(sym)
        assert(terra.issymbol(sym) or type(sym) == "string")
        return sym
    end

    function checkexp(e_,notruncate, allowluaobjects) -- if notruncate == true, then checkexp will _always_ return a typedexpressionlist tree node, these nodes may contain "luaobject" values
                
        --this function will return either 1 tree, or a list of trees and a function call
        --checkexp then makes the return value consistent with the notruncate argument
        local function docheck(e)
            if not terra.istree(e) then
                print("NOT A TREE: ",terra.isquote(e))
                terra.tree.printraw(e)
            end
            if e:is "luaobject" then
                return e
            elseif e:is "literal" then
                return e
            elseif e:is "constant"  then
                return e
            elseif e:is "var" then
                assert(e.value) --value should be added during specialization. it is a symbol in the currently symbol environment if this is a local variable
                                --otherwise it a reference to the global variable object to which it refers
                local definition = (terra.isglobalvar(e.value) and e.value) or symbolenv:localenv()[e.value]

                if not definition then
                    diag:reporterror(e, "definition of this variable is not in scope")
                    return e:copy { type = terra.types.error }
                end

                assert(terra.istree(definition) or terra.isglobalvar(definition))
                assert(terra.types.istype(definition.type))

                return e:copy { type = definition.type, definition = definition }
            elseif e:is "select" then
                local v = checkexp(e.value)
                local field = checksymbol(e.field)
                if v.type:ispointertostruct() then --allow 1 implicit dereference
                    v = insertdereference(v)
                end

                if v.type:isstruct() then
                    local ret, success = insertselect(v,field)
                    if not success then
                        --struct has no member field, look for a getter __get<field>
                        local getter = type(v.type.metamethods.__get) == "table" and v.type.metamethods.__get[field]
                        if getter then
                            getter = terra.createterraexpression(diag, e, getter) 
                            local til = createtypedexpressionlist(v, terra.newlist { v } ) 
                            return checkcall(v, terra.newlist{ getter }, terra.newlist { til }, "first", false, false)
                        else
                            diag:reporterror(v,"no field ",field," in terra object of type ",v.type)
                            return e:copy { type = terra.types.error }
                        end
                    else
                        return ret
                    end
                else
                    diag:reporterror(v,"expected a structural type")
                    return e:copy { type = terra.types.error }
                end
            elseif e:is "typedexpressionlist" then --expressionlist that has been previously typechecked and re-injected into the compiler
                if not symbolenv:insideenv(e.key) then --if it went through a macro, it could have been retained by lua code and returned to a different scope or even a different function
                                                       --we check that this didn't happen by checking that we are still inside the same scope where the expression was created
                    diag:reporterror(e,"cannot use a typed expression from one scope/function in another")
                    diag:reporterror(ftree,"typed expression used in this function.")
                end
                return e
            elseif e:is "operator" then
                return checkoperator(e)
            elseif e:is "index" then
                local v = checkexp(e.value)
                local idx = checkrvalue(e.index)
                local typ,lvalue
                if v.type:ispointer() or v.type:isarray() or v.type:isvector() then
                    typ = v.type.type
                    if not idx.type:isintegral() and idx.type ~= terra.types.error then
                        diag:reporterror(e,"expected integral index but found ",idx.type)
                    end
                    if v.type:ispointer() then
                        v = asrvalue(v)
                        lvalue = true
                    elseif v.type:isarray() then
                        lvalue = v.lvalue
                    elseif v.type:isvector() then
                        v = asrvalue(v)
                        lvalue = nil
                    end
                else
                    typ = terra.types.error
                    if v.type ~= terra.types.error then
                        diag:reporterror(e,"expected an array or pointer but found ",v.type)
                    end
                end
                return e:copy { type = typ, lvalue = lvalue, value = v, index = idx }
            elseif e:is "explicitcast" then
                return insertexplicitcast(checkrvalue(e.value),e.totype)
            elseif e:is "sizeof" then
                e.oftype:complete(e)
                return e:copy { type = uint64 }
            elseif e:is "vectorconstructor" or e:is "arrayconstructor" then
                local entries = checkparameterlist(e,e.expressions)
                local N = #entries.expressions
                         
                local typ
                if e.oftype ~= nil then
                    typ = e.oftype:complete(e)
                else
                    if N == 0 then
                        diag:reporterror(e,"cannot determine type of empty aggregate")
                        return e:copy { type = terra.types.error }
                    end
                    
                    --figure out what type this vector has
                    typ = entries.expressions[1].type
                    for i,p in ipairs(entries.expressions) do
                        typ = typemeet(e,typ,p.type)
                    end
                end
                
                local aggtype
                if e:is "vectorconstructor" then
                    if not typ:isprimitive() and typ ~= terra.types.error then
                        diag:reporterror(e,"vectors must be composed of primitive types (for now...) but found type ",type(typ))
                        return e:copy { type = terra.types.error }
                    end
                    aggtype = terra.types.vector(typ,N)
                else
                    aggtype = terra.types.array(typ,N)
                end
                
                --insert the casts to the right type in the parameter list
                local typs = entries.expressions:map(function(x) return typ end)
                
                insertcasts(typs,entries)
                
                return e:copy { type = aggtype, expressions = entries }
                
            elseif e:is "apply" then
                return checkapply(e,false)
            elseif e:is "method" then
                return checkmethod(e,false)
            elseif e:is "truncate" then
                return checkexp(e.value, false, allowluaobjects)
            elseif e:is "treelist" then
                local results = terra.newlist()
                local fncall = nil
                for i,v in ipairs(e.values) do
                    if v:is "luaobject" then
                        results:insert(v)
                    elseif i == #e.values then
                        local tel = checkexp(v,true)
                        for i,e in ipairs(tel.expressions) do
                            results:insert(e)
                        end
                        fncall = tel.fncall
                    else
                        results:insert(checkexp(v))
                    end
                end
                return createtypedexpressionlist(e,results,fncall)
           elseif e:is "constructor" then
                local typ = terra.types.newstructwithanchor("anon",e)
                typ:setconvertible(true)
                
                local paramlist = terra.newlist{}
                
                for i,f in ipairs(e.records) do
                    local value = f.value
                    if i == #e.records and f.key then
                        value = terra.newtree(value, { kind = terra.kinds.truncate, value = value })
                    end
                    paramlist:insert(value)
                end

                local entries = checkparameterlist(e,paramlist)
                
                for i,v in ipairs(entries.expressions) do
                    local k = e.records[i] and e.records[i].key
                    k = k and checksymbol(k)
                    typ.entries:insert({field = k, type = v.type})
                end

                return e:copy { expressions = entries, type = typ:complete(e) }
            elseif e:is "intrinsic" then
                return checkintrinsic(e,true)
            else
                diag:reporterror(e,"statement found where an expression is expected ", terra.kinds[e.kind])
                return e:copy { type = terra.types.error }
            end
        end
        
        --check the expression, may return 1 value or multiple
        local result = docheck(e_)
        --freeze all types returned by the expression (or list of expressions)
        local isexpressionlist = result:is "typedexpressionlist"
        if isexpressionlist then
            for i,e in ipairs(result.expressions) do
                if not e:is "luaobject" then
                    assert(terra.types.istype(e.type))
                    e.type:complete(e)
                end
            end
        elseif not result:is "luaobject" then
            assert(terra.types.istype(result.type))
            result.type:complete(result)
        end

        --remove any lua objects if they are not allowed in this context
        
        if not allowluaobjects then
            local function removeluaobject(e)
                if e.type == terra.types.error then return e end --don't repeat error messages
                if terra.isfunction(e.value) then
                    local definitions = e.value:getdefinitions()
                    if #definitions ~= 1 then
                        diag:reporterror(e,(#definitions == 0 and "undefined") or "overloaded", " functions cannot be used as values")
                        return e:copy { type = terra.types.error }
                    end
                    return createfunctionliteral(e,definitions[1])
                else
                    diag:reporterror(e, "expected a terra expression but found ",type(result.value))
                    return e:copy { type = terra.types.error }
                end
            end
            if isexpressionlist then
                local exps = result.expressions:map( function(e) 
                    return (e:is "luaobject" and removeluaobject(e)) or e
                end)
                result = result:copy { expressions = exps }
            elseif result:is "luaobject" then
                result = removeluaobject(result)
            end
        end

        --normalize the return type to the requested type
        if isexpressionlist then
            return (notruncate and result) or truncateexpressionlist(result)
        else
            return (notruncate and createtypedexpressionlist(e_,terra.newlist {result},nil)) or result
        end
    end

    --helper functions used in checking statements:
    
    local function checkexptyp(re,target)
        local e = checkrvalue(re)
        if e.type ~= target then
            diag:reporterror(e,"expected a ",target," expression but found ",e.type)
            e.type = terra.types.error
        end
        return e
    end
    local function checkcondbranch(s)
        local e = checkexptyp(s.condition,bool)
        local b = checkstmt(s.body)
        return s:copy {condition = e, body = b}
    end

    local function checkformalparameterlist(params)
        for i, p in ipairs(params) do
            assert(type(p.name) == "string")
            assert(terra.issymbol(p.symbol))
            if p.type then
                assert(terra.types.istype(p.type))
                p.type:complete(p)
            end
        end
        --copy the entries since we mutate them and this list could appear multiple times in the tree
        return params:map(function(x) return x:copy{}  end) 
    end


    --state that is modified by checkstmt:
    
    local return_stmts = terra.newlist() --keep track of return stms, these will be merged at the end, possibly inserting casts
    
    local labels = {} --map from label name to definition (or, if undefined to the list of already seen gotos that target that label)
    local loopstmts = terra.newlist() -- stack of loopstatements (for resolving where a break goes)
    
    local function enterloop()
        local bt = {}
        loopstmts:insert(bt)
        return bt
    end
    local function leaveloop()
        loopstmts:remove()
    end
    
    -- checking of statements

    function checkstmt(s)
        if s:is "block" then
            symbolenv:enterblock()
            local r = s.statements:flatmap(checkstmt)
            symbolenv:leaveblock()
            return s:copy {statements = r}
        elseif s:is "return" then
            local rstmt = s:copy { expressions = checkparameterlist(s,s.expressions) }
            return_stmts:insert( rstmt )
            return rstmt
        elseif s:is "label" then
            local ss = s:copy {}
            local label = checksymbol(ss.value)
            ss.labelname = tostring(label)
            local lbls = labels[label] or terra.newlist()
            if terra.istree(lbls) then
                diag:reporterror(s,"label defined twice")
                diag:reporterror(lbls,"previous definition here")
            else
                for _,v in ipairs(lbls) do
                    v.definition = ss
                end
            end
            labels[label] = ss
            return ss
        elseif s:is "goto" then
            local ss = s:copy{}
            local label = checksymbol(ss.label)
            local lbls = labels[label] or terra.newlist()
            if terra.istree(lbls) then
                ss.definition = lbls
            else
                lbls:insert(ss)
            end
            labels[label] = lbls
            return ss
        elseif s:is "break" then
            local ss = s:copy({})
            if #loopstmts == 0 then
                diag:reporterror(s,"break found outside a loop")
            else
                ss.breaktable = loopstmts[#loopstmts]
            end
            return ss
        elseif s:is "while" then
            local breaktable = enterloop()
            local r = checkcondbranch(s)
            r.breaktable = breaktable
            leaveloop()
            return r
        elseif s:is "if" then
            local br = s.branches:map(checkcondbranch)
            local els = (s.orelse and checkstmt(s.orelse)) or terra.newtree(s, { kind = terra.kinds.block, statements = terra.newlist() })
            return s:copy{ branches = br, orelse = els }
        elseif s:is "repeat" then
            local breaktable = enterloop()
            symbolenv:enterblock() --we don't use block here because, unlike while loops, the condition needs to be checked in the scope of the loop
            local new_blk = s.body:copy { statements = s.body.statements:map(checkstmt) }
            local e = checkexptyp(s.condition,bool)
            symbolenv:leaveblock()
            leaveloop()
            return s:copy { body = new_blk, condition = e, breaktable = breaktable }
        elseif s:is "defvar" then
            local res
            
            local lhs = checkformalparameterlist(s.variables)

            if s.initializers then
                local params = checkparameterlist(s,s.initializers)
                
                local vtypes = terra.newlist()
                for i,v in ipairs(lhs) do
                    vtypes:insert(v.type or "passthrough")
                end
                


                insertcasts(vtypes,params)
                
                for i,v in ipairs(lhs) do
                    v.type = (params.expressions[i] and params.expressions[i].type) or terra.types.error
                end
                
                res = s:copy { variables = lhs, initializers = params }
            else
                res = s:copy { variables = lhs }
            end     
            --add the variables to current environment
            for i,v in ipairs(lhs) do
                assert(terra.issymbol(v.symbol))
                symbolenv:localenv()[v.symbol] = v
            end
            return res
        elseif s:is "assignment" then
            
            local params = checkparameterlist(s,s.rhs)
            
            local lhs = terra.newlist()
            local vtypes = terra.newlist()
            for i,l in ipairs(s.lhs) do
                local ll = checklvalue(l)
                vtypes:insert(ll.type)
                lhs:insert(ll)
            end
            
            insertcasts(vtypes,params)
            
            return s:copy { lhs = lhs, rhs = params }
        elseif s:is "apply" then
            return checkapply(s,true)
        elseif s:is "method" then
            return checkmethod(s,true)
        elseif s:is "treelist" then
            return s.values:flatmap(checkstmt)
        elseif s:is "intrinsic" then
            return checkintrinsic(s,false)
        else
            return checkexp(s,true)
        end
        error("NYI - "..terra.kinds[s.kind],2)
    end
    


    -- actual implementation of typechecking the function begins here

    --  generate types for parameters, if return types exists generate a types for them as well
    local typed_parameters = checkformalparameterlist(ftree.parameters)
    local parameter_types = terra.newlist() --just the types, used to create the function type
    for _,v in ipairs(typed_parameters) do
        assert(terra.types.istype(v.type))
        assert(terra.issymbol(v.symbol))
        parameter_types:insert( v.type )
        symbolenv:localenv()[v.symbol] = v
    end


    local result = checkstmt(ftree.body)

    --check the label table for any labels that have been referenced but not defined
    for _,v in pairs(labels) do
        if not terra.istree(v) then
            diag:reporterror(v[1],"goto to undefined label")
        end
    end
    
    
    dbprint(2,"Return Stmts:")
    
    --calculate the return type based on either the declared return type, or the return statements

    local return_types
    if ftree.return_types then --take the return types to be as specified
        return_types = ftree.return_types
    else --calculate the meet of all return type to calculate the actual return type
        if #return_stmts == 0 then
            return_types = terra.newlist()
        else
            local minsize,maxsize
            for _,stmt in ipairs(return_stmts) do
                if return_types == nil then
                    return_types = terra.newlist()
                    for i,exp in ipairs(stmt.expressions.expressions) do
                        return_types[i] = exp.type
                    end
                    minsize = stmt.expressions.minsize
                    maxsize = #stmt.expressions.expressions
                else
                    minsize = math.max(minsize,stmt.expressions.minsize)
                    maxsize = math.min(maxsize,#stmt.expressions.expressions)
                    if minsize > maxsize then
                        diag:reporterror(stmt,"returning a different length from previous return")
                    else
                        for i,exp in ipairs(stmt.expressions.expressions) do
                            if i <= maxsize then
                                return_types[i] = typemeet(exp,return_types[i],exp.type)
                            end
                        end
                    end
                end
            end
            while #return_types > maxsize do
                table.remove(return_types)
            end
            
        end
    end
    local fntype = terra.types.functype(parameter_types,return_types):complete(ftree)

    --now cast each return expression to the expected return type
    for _,stmt in ipairs(return_stmts) do
        insertcasts(return_types,stmt.expressions)
    end
    
    --we're done. build the typed tree for this function
    self.typedtree = ftree:copy { body = result, parameters = typed_parameters, labels = labels, type = fntype}
    self.type = fntype

    self.stats.typec = terra.currenttimeinseconds() - starttime
    
    dbprint(2,"TypedTree")
    dbprintraw(2,self.typedtree)

    ctx:finish(ftree)

end
--cache for lua functions called by terra, to prevent making multiple callback functions
terra.__wrappedluafunctions = {}

-- END TYPECHECKER

-- INCLUDEC
local function includetableindex(tbl,name)    --this is called when a table returned from terra.includec doesn't contain an entry
    local v = getmetatable(tbl).errors[name]  --it is used to report why a function or type couldn't be included
    if v then
        error("includec: error importing symbol '"..name.."': "..v, 2)
    else
        error("includec: imported symbol '"..name.."' not found.",2)
    end
    return nil
end

terra.includepath = os.getenv("INCLUDE_PATH") or "."
function terra.includecstring(code,...)
    local args = terralib.newlist {"-O3","-Wno-deprecated",...}
    for p in terra.includepath:gmatch("([^;]+);?") do
        args:insert("-I")
        args:insert(p)
    end
    local result = terra.registercfile(code,args)
    local general,tagged,errors = result.general,result.tagged,result.errors
    local mt = { __index = includetableindex, errors = result.errors }
    for k,v in pairs(tagged) do
        if not general[k] then
            general[k] = v
        end
    end
    setmetatable(general,mt)
    setmetatable(tagged,mt)
    return general,tagged
end
function terra.includec(fname,...)
    return terra.includecstring("#include \""..fname.."\"\n",...)
end


-- GLOBAL MACROS
_G["sizeof"] = terra.internalmacro(function(diag,tree,typ)
    return terra.newtree(tree,{ kind = terra.kinds.sizeof, oftype = typ:astype()})
end)
_G["vector"] = terra.internalmacro(function(diag,tree,...)
    if not diag then
        error("nil first argument in vector constructor")
    end
    if not tree then
        error("nil second argument in vector constructor")
    end
    if terra.types.istype(diag) then --vector used as a type constructor vector(int,3)
        return terra.types.vector(diag,tree)
    end
    --otherwise this is a macro that constructs a vector literal
    local exps = terra.newlist({...}):map(function(x) return x.tree end)
    return terra.newtree(tree,{ kind = terra.kinds.vectorconstructor, expressions = exps })
    
end)
_G["vectorof"] = terra.internalmacro(function(diag,tree,typ,...)
    local exps = terra.newlist({...}):map(function(x) return x.tree end)
    return terra.newtree(tree,{ kind = terra.kinds.vectorconstructor, oftype = typ:astype(), expressions = exps })
end)
_G["array"] = terra.internalmacro(function(diag,tree,...)
    local exps = terra.newlist({...}):map(function(x) return x.tree end)
    return terra.newtree(tree, { kind = terra.kinds.arrayconstructor, expressions = exps })
end)
_G["arrayof"] = terra.internalmacro(function(diag,tree,typ,...)
    local exps = terra.newlist({...}):map(function(x) return x.tree end)
    return terra.newtree(tree, { kind = terra.kinds.arrayconstructor, oftype = typ:astype(), expressions = exps })
end)

_G["global"] = terra.global
_G["constant"] = terra.constant

terra.select = terra.internalmacro(function(diag,tree,guard,a,b)
    return terra.newtree(tree, { kind = terra.kinds.operator, operator = terra.kinds.select, operands = terra.newlist{guard.tree,a.tree,b.tree}})
end)

local function annotatememory(arg,tbl)
    if arg.tree:is "typedexpressionlist" and #arg.tree.expressions > 0 then
        local e = arg.tree.expressions[1]
        if (e:is "operator" and e.operator == terra.kinds["@"]) or e:is "index" then
            return arg.tree:copy { expressions = terra.newlist { e:copy(tbl) } }
        end
    end
    error("expected a dereference operator")
end

terra.nontemporal = terra.internalmacro( function(diag,tree,arg)
    return annotatememory(arg,{nontemporal = true})
end)

terra.aligned = terra.internalmacro( function(diag,tree,arg,num)
    local n = num:asvalue()
    if type(n) ~= "number" then
        error("expected a number for alignment")
    end
    return annotatememory(arg,{alignment = n})
end)


-- END GLOBAL MACROS

-- DEBUG

function terra.printf(s,...)
    local function toformat(x)
        if type(x) ~= "number" and type(x) ~= "string" then
            return tostring(x) 
        else
            return x
        end
    end
    local strs = terra.newlist({...}):map(toformat)
    --print(debug.traceback())
    return io.write(tostring(s):format(unpack(strs)))
end

function terra.func:printpretty()
    for i,v in ipairs(self.definitions) do
        v:compile()
        terra.printf("%s = ",v.name,v.type)
        v:printpretty()
    end
end

function terra.func:__tostring()
    return "<terra function>"
end

function terra.funcdefinition:printpretty()
    self:compile()
    if not self.typedtree then
        terra.printf("<extern : %s>\n",self.type)
        return
    end
    local indent = 0
    local function enterblock()
        indent = indent + 1
    end
    local function leaveblock()
        indent = indent - 1
    end
    local function emit(...) terra.printf(...) end
    local function begin(...)
        for i = 1,indent do
            io.write("    ")
        end
        emit(...)
    end

    local function emitList(lst,begin,sep,finish,fn)
        emit(begin)
        for i,k in ipairs(lst) do
            fn(k,i)
            if i ~= #lst then
                emit(sep)
            end
        end
        emit(finish)
    end

    local function emitType(t)
        emit(t)
    end

    local function emitParam(p)
        emit("%s : %s",p.name,p.type)
    end
    local emitStmt, emitExp,emitParamList

    function emitStmt(s)
        if s:is "block" then
            enterblock()
            local function emitStatList(lst) --nested statements (e.g. from quotes need "do" appended)
                for i,ss in ipairs(lst) do
                    if ss:is "block" then
                        begin("do\n")
                        enterblock()
                        emitStatList(ss.statements)
                        leaveblock()
                        begin("end\n")
                    else
                        emitStmt(ss)
                    end
                end
            end
            emitStatList(s.statements)
            leaveblock()
        elseif s:is "return" then
            begin("return ")
            emitParamList(s.expressions)
            emit("\n")
        elseif s:is "label" then
            begin("::%s::\n",s.labelname)
        elseif s:is "goto" then
            begin("goto %s\n",s.definition.labelname)
        elseif s:is "break" then
            begin("break\n")
        elseif s:is "while" then
            begin("while ")
            emitExp(s.condition)
            emit(" do\n")
            emitStmt(s.body)
            begin("end\n")
        elseif s:is "if" then
            for i,b in ipairs(s.branches) do
                if i == 1 then
                    begin("if ")
                else
                    begin("elseif ")
                end
                emitExp(b.condition)
                emit(" then\n")
                emitStmt(b.body)
            end
            begin("else\n")
            emitStmt(s.orelse)
            begin("end\n")
        elseif s:is "repeat" then
            begin("repeat\n")
            emitStmt(s.body)
            begin("until ")
            emitExp(s.condition)
            emit("\n")
        elseif s:is "defvar" then
            begin("var ")
            emitList(s.variables,"",", ","",emitParam)
            if s.initializers then
                emit(" = ")
                emitParamList(s.initializers)
            end
            emit("\n")
        elseif s:is "assignment" then
            begin("")
            emitList(s.lhs,"",", ","",emitExp)
            emit(" = ")
            emitParamList(s.rhs)
            emit("\n")
        else
            begin("")
            emitExp(s)
            emit("\n")
        end
    end
    
    local function makeprectable(...)
        local lst = {...}
        local sz = #lst
        local tbl = {}
        for i = 1,#lst,2 do
            tbl[lst[i]] = lst[i+1]
        end
        return tbl
    end

    local prectable = makeprectable(
     "+",7,"-",7,"*",8,"/",8,"%",8,
     "^",11,"..",6,"<<",4,">>",4,
     "==",3,"<",3,"<=",3,
     "~=",3,">",3,">=",3,
     "and",2,"or",1,
     "@",9,"-",9,"&",9,"not",9,"select",12)
    
    local function getprec(e)
        if e:is "operator" then
            return prectable[terra.kinds[e.operator]]
        else
            return 12
        end
    end
    local function doparens(ref,e)
        if getprec(ref) > getprec(e) then
            emit("(")
            emitExp(e)
            emit(")")
        else
            emitExp(e)
        end
    end

    function emitExp(e)
        if e:is "var" then
            emit(e.name)
        elseif e:is "ltor" or e:is "rtol" then
            emitExp(e.expression)
        elseif e:is "operator" then
            local op = terra.kinds[e.operator]
            local function emitOperand(o)
                doparens(e,o)
            end
            if #e.operands == 1 then
                emit(op)
                emitOperand(e.operands[1])
            elseif #e.operands == 2 then
                emitOperand(e.operands[1])
                emit(" %s ",op)
                emitOperand(e.operands[2])
            elseif op == "select" then
                emit("terralib.select")
                emitList(e.operands,"(",", ",")",emitExp)
            else
                emit("<??operator??>")
            end
        elseif e:is "index" then
            doparens(e,e.value)
            emit("[")
            emitExp(e.index)
            emit("]")
        elseif e:is "literal" then
            if e.type:ispointer() and e.type.type:isfunction() then
                emit(e.value.name)
            elseif e.type:isintegral() then
                emit(e.stringvalue or "<int>")
            elseif type(e.value) == "string" then
                emit("%q",e.value)
            else
                emit("%s",e.value)
            end
        elseif e:is "luafunction" then
            emit("<luafunction>")
        elseif e:is "cast" then
            emit("[")
            emitType(e.to)
            emit("](")
            emitExp(e.expression)
            emit(")")

        elseif e:is "sizeof" then
            emit("sizeof(%s)",e.oftype)
        elseif e:is "apply" then
            doparens(e,e.value)
            emit("(")
            emitParamList(e.arguments)
            emit(")")
        elseif e:is "extractreturn" then
            emit("<extract%d>",e.index)
        elseif e:is "select" then
            doparens(e,e.value)
            emit(".")
            emit(e.field)
        elseif e:is "vectorconstructor" then
            emit("vector(")
            emitParamList(e.expressions)
            emit(")")
        elseif e:is "arrayconstructor" then
            emit("array(")
            emitParamList(e.expressions)
            emit(")")
        elseif e:is "constructor" then
            emit("{")
            local anon = 0
            local keys = e.type:getlayout().entries:map(function(e) return e.key end)
            emitParamList(e.expressions,keys)
            emit("}")
        elseif e:is "constant" then
            if e.type:isprimitive() then
                emit(tonumber(e.value.object))
            else
                emit("<constant:",e.type,">")
            end
        elseif e:is "typedexpressionlist" then
            emitParamList(e)
        else
            emit("<??"..terra.kinds[e.kind].."??>")
        end
    end

    function emitParamList(pl,keys)
        local function emitE(e,i)
            if keys and keys[i] then
                emit(keys[i])
                emit(" = ")
            end
            emitExp(e)
        end
        emitList(pl.expressions,"",", ","",emitE)
        if pl.fncall then
            if #pl.expressions > 0 then
                emit(" #")
                emitExp(pl.fncall)
                emit("#")
            else
                emitExp(pl.fncall)
            end
        end
    end

    emit("terra")
    emitList(self.typedtree.parameters,"(",",",") : ",emitParam)
    emitList(self.type.returns,"{",", ","}",emitType)
    emit("\n")
    emitStmt(self.typedtree.body)
    emit("end\n")
end

-- END DEBUG

function terra.saveobj(filename,env,arguments)
    local cleanenv = {}
    for k,v in pairs(env) do
        if terra.isfunction(v) then
            v:emitllvm()
            local definitions = v:getdefinitions()
            if #definitions > 1 then
                error("cannot create a C function from an overloaded terra function, "..k)
            end
            cleanenv[k] = definitions[1]
        end
    end
    local isexe
    if filename:sub(-2) == ".o" then
        isexe = 0
    else
        isexe = 1
    end
    if not arguments then
        arguments = {}
    end
    return terra.saveobjimpl(filename,cleanenv,isexe,arguments)
end

terra.packages = {} --table of packages loaded using terralib.require()
terra.path = os.getenv("TERRA_PATH") or "?.t"
function terra.require(name)
    if not terra.packages[name] then
        local fname = name:gsub("%.","/")
        local file = nil
        for template in terra.path:gmatch("([^;]+);?") do
            local fpath = template:gsub("%?",fname)
            local handle = io.open(fpath,"r")
            if handle then
                file = fpath
                handle:close()
                break
            end
        end
        if not file then
            error("terra module not in path: "..name,2)
        end
        local fn, err = terra.loadfile(file)
        if not fn then
            error(err,0)
        end
        terra.packages[name] = { results = {fn()} }    
    end
    return unpack(terra.packages[name].results)
end
function terra.makeenvunstrict(env)
    if getmetatable(env) == Strict then
        return function(self,idx)
            return rawget(env,idx)
        end
    else return env end
end

function terra.new(terratype,...)
    terratype:complete()
    local typ = terratype:cstring()
    return ffi.new(typ,...)
end
function terra.sizeof(terratype,...)
    terratype:complete()
    local typ = terratype:cstring()
    return ffi.sizeof(typ,...)
end
function terra.offsetof(terratype,field)
    terratype:complete()
    local typ = terratype:cstring()
    if terra.issymbol(field) then
        field = "__symbol"..field.id
    end
    return ffi.offsetof(typ,field)
end

function terra.cast(terratype,obj)
    terratype:complete()
    local ctyp = terratype:cstring()
    if type(obj) == "function" then --functions are cached to avoid creating too many callback objects
        local fncache = terra.__wrappedluafunctions[obj]

        if not fncache then
            fncache = {}
            terra.__wrappedluafunctions[obj] = fncache
        end
        local cb = fncache[terratype]
        if not cb then
            cb = ffi.cast(ctyp,obj)
            fncache[terratype] = cb
        end
        return cb
    end
    return ffi.cast(ctyp,obj)
end

terra.constantobj = {}
terra.constantobj.__index = terra.constantobj

--c.object is the cdata value for this object
--string constants are handled specially since they should be treated as objects and not pointers
--in this case c.object is a string rather than a cdata object
--c.type is the terra type


function terra.isconstant(obj)
    return getmetatable(obj) == terra.constantobj
end

function terra.constant(a0,a1)
    if terra.types.istype(a0) then
        local c = setmetatable({ type = a0, object = a1 },terra.constantobj)
        --special handling for string literals
        if type(c.object) == "string" and c.type == rawstring then
            return c
        end

        --if the  object is not already cdata, we need to convert it
        if  type(c.object) ~= "cdata" or terra.typeof(c.object) ~= c.type then
            c.object = terra.cast(c.type,c.object)
        end
        return c
    else
        --try to infer the type, and if successful build the constant
        local init,typ = a0,nil
        if type(init) == "cdata" then
            typ = terra.typeof(init)
        elseif type(init) == "number" then
            typ = (terralib.isintegral(init) and int) or double
        elseif type(init) == "boolean" then
            typ = bool
        elseif type(init) == "string" then
            typ = rawstring
        else
            error("constant constructor requires explicit type for objects of type "..type(init))
        end
        return terra.constant(typ,init)
    end
end

function terra.typeof(obj)
    if type(obj) ~= "cdata" then
        error("cannot get the type of a non cdata object")
    end
    return terra.types.ctypetoterra[tonumber(ffi.typeof(obj))]
end

function terra.linklibrary(filename)
    terra.linklibraryimpl(filename)
end

terra.languageextension = {
    languages = terra.newlist();
    entrypoints = {}; --table mapping entry pointing tokens to the language that handles them
    tokentype = {}; --metatable for tokentype objects
    tokenkindtotoken = {}; --map from token's kind id (terra.kind.name), to the singleton table (terra.languageextension.name) 
}

function terra.loadlanguage(lang)
    local E = terra.languageextension
    if not lang or type(lang) ~= "table" then error("expected a table to define language") end
    lang.name = lang.name or "anonymous"
    local function haslist(field,typ)
        if not lang[field] then 
            error(field .. " expected to be list of "..typ)
        end
        for i,k in ipairs(lang[field]) do
            if type(k) ~= typ then
                error(field .. " expected to be list of "..typ.." but found "..type(k))
            end
        end
    end
    haslist("keywords","string")
    haslist("entrypoints","string")
    
    for i,e in ipairs(lang.entrypoints) do
        if E.entrypoints[e] then
            error(("language %s uses entrypoint %s already defined by language %s"):format(lang.name,e,E.entrypoints[e].name))
        end
        E.entrypoints[e] = lang
    end
    lang.keywordtable = {} --keyword => true
    for i,k in ipairs(lang.keywords) do
        lang.keywordtable[k] = true
    end
    for i,k in ipairs(lang.entrypoints) do
        lang.keywordtable[k] = true
    end

    E.languages:insert(lang)
end

function terra.languageextension.tokentype:__tostring()
    return self.name
end

do
    local special = { "name", "string", "number", "eof", "default" }
    --note: default is not a tokentype but can be used in libraries to match
    --a token that is not another type
    for i,k in ipairs(special) do
        local name = "<" .. k .. ">"
        local tbl = setmetatable({
            name = name }, terra.languageextension.tokentype )
        terra.languageextension[k] = tbl
        local kind = terra.kinds[name]
        if kind then
            terra.languageextension.tokenkindtotoken[kind] = tbl
        end
    end
end

function terra.runlanguage(lang,cur,lookahead,next,luaexpr,source,isstatement,islocal)
    local lex = {}
    
    lex.name = terra.languageextension.name
    lex.string = terra.languageextension.string
    lex.number = terra.languageextension.number
    lex.eof = terra.languageextension.eof
    lex.default = terra.languageextension.default

    lex._references = terra.newlist()
    lex.source = source

    local function maketoken(tok)
        if type(tok.type) ~= "string" then
            tok.type = terra.languageextension.tokenkindtotoken[tok.type]
            assert(type(tok.type) == "table") 
        end
        return tok
    end
    function lex:cur()
        self._cur = self._cur or maketoken(cur())
        return self._cur
    end
    function lex:lookahead()
        self._lookahead = self._lookahead or maketoken(lookahead())
        return self._lookahead
    end
    function lex:next()
        local v = self:cur()
        self._cur,self._lookahead = nil,nil
        next()
        return v
    end
    function lex:luaexpr()
        self._cur,self._lookahead = nil,nil --parsing an expression invalidates our lua representations 
        local expr = luaexpr()
        return function(env)
            setfenv(expr,env)
            return expr()
        end
    end

    function lex:ref(name)
        if type(name) ~= "string" then
            error("references must be identifiers")
        end
        self._references:insert(name)
    end

    function lex:typetostring(name)
        if type(name) == "string" then
            return name
        else
            return terra.kinds[name]
        end
    end
    
    function lex:nextif(typ)
        if self:cur().type == typ then
            return self:next()
        else return false end
    end
    function lex:expect(typ)
        local n = self:nextif(typ)
        if not n then
            self:errorexpected(tostring(typ))
        end
        return n
    end
    function lex:matches(typ)
        return self:cur().type == typ
    end
    function lex:lookaheadmatches(typ)
        return self:lookahead().type == typ
    end
    function lex:error(msg)
        error(msg,0) --,0 suppresses the addition of line number information, which we do not want here since
                     --this is a user-caused errors
    end
    function lex:errorexpected(what)
        self:error(what.." expected")
    end
    function lex:expectmatch(typ,openingtokentype,linenumber)
       local n = self:nextif(typ)
        if not n then
            if self:cur().linenumber == linenumber then
                lex:errorexpected(tostring(typ))
            else
                lex:error(string.format("%s expected (to close %s at line %d)",tostring(typ),tostring(openingtokentype),linenumber))
            end
        end
        return n
    end

    local constructor,names
    if isstatement and islocal and lang.localstatement then
        constructor,names = lang:localstatement(lex)
    elseif isstatement and not islocal and lang.statement then
        constructor,names = lang:statement(lex)
    elseif not islocal and lang.expression then
        constructor = lang:expression(lex)
    else
        lex:error("unexpected token")
    end
    
    if not constructor or type(constructor) ~= "function" then
        error("expected language to return a construction function")
    end

    local function isidentifier(str)
        local b,e = string.find(str,"[%a_][%a%d_]*")
        return b == 1 and e == string.len(str)
    end

    --fixup names    

    if not names then 
        names = {}
    end

    if type(names) ~= "table" then
        error("names returned from constructor must be a table")
    end

    if islocal and #names == 0 then
        error("local statements must define at least one name")
    end

    for i = 1,#names do
        if type(names[i]) ~= "table" then
            names[i] = { names[i] }
        end
        local name = names[i]
        if #name == 0 then
            error("name must contain at least one element")
        end
        for i,c in ipairs(name) do
            if type(c) ~= "string" or not isidentifier(c) then
                error("name component must be an identifier")
            end
            if islocal and i > 1 then
                error("local names must have exactly one element")
            end
        end
    end

    return constructor,names,lex._references
end

function terra.defaultmetamethod(method)
        local tbl = {
            __sub = "-";
            __add = "+";
            __mul = "*";
            __div = "/";
            __mod = "%";
            __lt = "<";
            __le = "<=";
            __gt = ">";
            __ge = ">=";
            __eq = "==";
            __ne = "~=";
            __and = "and";
            __or = "or";
            __not = "not";
            __xor = "^";
            __lshift = "<<";
            __rshift = ">>";
            __select = "select";
        }
    return tbl[method] and terra.defaultoperator(tbl[method])
end

function terra.defaultoperator(op)
    return function(...)
        --TODO: really should call createterraexpression rather than assuming these are quotes
        local exps = terra.newlist({...}):map(function(x) 
            assert(terralib.isquote(x))
            return x.tree 
        end)
        local tree = terra.newtree(terralib.newanchor(2), { kind = terra.kinds.operator, operator = terra.kinds[op], operands = exps })
        return terra.newquote(tree)
    end
end

_G["terralib"] = terra --terra code can't use "terra" because it is a keyword
--io.write("done\n")

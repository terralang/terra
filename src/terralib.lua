-- See Copyright Notice in ../LICENSE.txt

local ffi = require("ffi")

-- LINE COVERAGE INFORMATION
if false then
    local converageloader = loadfile("coverageinfo.lua")
    local linetable = converageloader and converageloader() or {}
    local function dumplineinfo()
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
    -- make a fake ffi object that causes dumplineinfo to be called when
    -- the lua state is removed
    ffi.cdef [[
        typedef struct {} __linecoverage;
    ]]
    ffi.metatype("__linecoverage", { __gc = dumplineinfo } )
    _G[{}] = ffi.new("__linecoverage")
end

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
    local body = { linenumber = info and info.currentline or 0, filename = info and info.short_src or "unknown" }
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

function terra.list:map(fn,...)
    local l = terra.newlist()
    if type(fn) == "function" then
        for i,v in ipairs(self) do
            l[i] = fn(v,...)
        end 
    else
        for i,v in ipairs(self) do
            local sel = v[fn]
            if type(sel) == "function" then
                l[i] = sel(v,...)
            else
                l[i] = sel
            end
        end
    end
    return l
end
function terra.list:insertall(elems)
    for i,e in ipairs(elems) do
        self:insert(e)
    end
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
    return begin..table.concat(self:map(tostring),sep)..finish
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
    self._localenv = setmetatable(e,{ __index = self._localenv })
end
function terra.environment:leaveblock()
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

function terra.newenvironment(_luaenv)
    local self = setmetatable({},terra.environment)
    self._luaenv = _luaenv
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

function terra.diagnostics:errorlist()
    return self._errors[#self._errors]
end

function terra.diagnostics:printsource(anchor)
    if not anchor.offset then 
        return
    end
    local filename = anchor.filename
    local filetext = self.filecache[filename] 
    if not filetext then
        local file = io.open(filename,"r")
        if file then
            filetext = file:read("*all")
            self.filecache[filename] = filetext
            file:close()
        end
    end
    if filetext then --if the code did not come from a file then we don't print the carrot, since we cannot (easily) find the text
        local begin,finish = anchor.offset + 1,anchor.offset + 1
        local TAB,NL = ("\t"):byte(),("\n"):byte()
        while begin > 1 and filetext:byte(begin) ~= NL do
            begin = begin - 1
        end
        if begin > 1 then
            begin = begin + 1
        end
        while finish < filetext:len() and filetext:byte(finish + 1) ~= NL do
            finish = finish + 1
        end
        local errlist = self:errorlist()
        local line = filetext:sub(begin,finish) 
        errlist:insert(line)
        errlist:insert("\n")
        for i = begin,anchor.offset do
            errlist:insert((filetext:byte(i) == TAB and "\t") or " ")
        end
        errlist:insert("^\n")
    end
end

function terra.diagnostics:clearfilecache()
    self.filecache = {}
end
terra.diagnostics.source = {}
function terra.diagnostics:reporterror(anchor,...)
    if not anchor or not anchor.filename or not anchor.linenumber then
        print(debug.traceback())
        print(terralib.tree.printraw(anchor))
        error("nil anchor")
    end
    local errlist = self:errorlist()
    errlist:insert(anchor.filename..":"..anchor.linenumber..": ")
    local printedsource = false
    local function printsource()
        errlist:insert("\n")
        self:printsource(anchor)
        printedsource = true
    end
    for _,v in ipairs({...}) do
        if v == self.source then
            printsource()
        else
            errlist:insert(tostring(v))
        end
    end
    if not printedsource then
        printsource()
    end
end

function terra.diagnostics:haserrors()
    return #self._errors[#self._errors] > 0
end

function terra.diagnostics:begin()
    table.insert(self._errors,terra.newlist())
end

function terra.diagnostics:finish()
    local olderrors = table.remove(self._errors)
    local haderrors = #olderrors > 0
    if haderrors then
        self._errors[#self._errors]:insert(olderrors)
    end
    return haderrors
end

function terra.diagnostics:finishandabortiferrors(msg,depth)
    local errors = table.remove(self._errors)
    if #errors > 0 then
        local flatlist = {msg,"\n"}
        local function insert(l) 
            if type(l) == "table" then
                for i,e in ipairs(l) do
                    insert(e)
                end
            else
                table.insert(flatlist,l)
            end
        end
        insert(errors)
        self:clearfilecache()
        error(table.concat(flatlist),depth+1)
    end
end

function terra.newdiagnostics()
    return setmetatable({ filecache = {}, _errors = { terra.newlist() } },terra.diagnostics)
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
    if not self.untypedtree.returntype then
        return false, terra.types.error
    end

    local params = self.untypedtree.parameters:map(function(entry) return entry.type end)
    local ret   = self.untypedtree.returntype
    self.type = terra.types.functype(params,ret) --for future calls
    
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
    self.type:completefunction(anchor)
    self.state = "emittedllvm"
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
    elseif self.state == "uninitializedc" then --this is a stub generated by the c wrapper, connect it with the right llvm_value object and set llvm_ptr
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
    return ffiwrapper(...)
end
function terra.funcdefinition:getpointer()
    self:compile()
    if not self.ffiwrapper then
        self.ffiwrapper = ffi.cast(terra.types.pointer(self.type):cstring(),self.llvm_ptr)
    end
    return self.ffiwrapper
end

function terra.funcdefinition:setinlined(v)
    if self.state ~= "untyped" then
        error("inlining state can only be changed before typechecking",2)
    end
    self.alwaysinline = v
end

function terra.funcdefinition:disas()
    self:compile()
    print("definition ", self.type)
    terra.disassemble(self)
end
function terra.funcdefinition:printstats()
    self:compile()
    print("definition ", self.type)
    for k,v in pairs(self.stats) do
        print("",k,v)
    end
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
terra.func.__index = function(self,idx)
    local r = terra.func[idx]
    if r then return r end
    return function(self,...)
        local ND = #self.definitions
        if ND == 1 then --faster path, avoid creating a table of arguments
            local dfn = self.definitions[1]
            return dfn[idx](dfn,...)
        elseif ND == 0 then
            error("attempting to call "..idx.." on undefined function",2)
        end
        local results
        for i,dfn in ipairs(self.definitions) do
            local r = { dfn[idx](dfn,...) }
            results = results or r
        end
        return unpack(results)
    end
end

function terra.func:__call(...)
    if rawget(self,"fastcall") then
        return self.fastcall(...)
    end
    if #self.definitions == 1 then --generate fast path for the non-overloaded case
        local defn = self.definitions[1]
        local ptr = defn:getpointer() --forces compilation
        self.fastcall = ptr
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
    v.name = self.name --propagate function name to definition 
                       --this will be used as the name for llvm debugging, etc.
    self.fastcall = nil
    self.definitions:insert(v)
end

function terra.func:getdefinitions()
    return self.definitions
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
terra.macro.__call = function(self,...)
    if not self.fromlua then
        error("macros must be called from inside terra code",2)
    end
    return self.fromlua(...)
end
function terra.macro:run(ctx,tree,...)
    if self._internal then
        return self.fromterra(ctx,tree,...)
    else
        return self.fromterra(...)
    end
end
function terra.ismacro(t)
    return getmetatable(t) == terra.macro
end

function terra.createmacro(fromterra,fromlua)
    return setmetatable({fromterra = fromterra,fromlua = fromlua}, terra.macro)
end
function terra.internalmacro(...) 
    local m = terra.createmacro(...)
    m._internal = true
    return m
end

_G["macro"] = terra.createmacro --introduce macro intrinsic into global namespace

-- END MACRO


function terra.israwlist(l)
    if terra.islist(l) then
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
    if not self.tree:is "typedexpression" or not self.tree.expression:is "luaobject" or not terra.types.istype(self.tree.expression.value) then
        error("quoted value is not a type")
    end
    return self.tree.expression.value
end
function terra.quote:istyped()
    return self.tree:is "typedexpression" and not self.tree.expression:is "luaobject"
end
function terra.quote:gettype()
    if not self:istyped() then
        error("not a typed quote")
    end
    return self.tree.expression.type
end
function terra.quote:islvalue()
    if not self:istyped() then
        error("not a typed quote")
    end
    return self.tree.expression.lvalue
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
            local t,typ = {},e.type
            for i,r in ipairs(typ:getentries()) do
                local v,e = getvalue(e.expressions[i]) 
                if e then return nil,e end
                local key = typ.convertible == "tuple" and i or r.field
                t[key] = v
            end
            return t
        elseif e:is "typedexpression" then
            return getvalue(e.expression)
        elseif e:is "operator" and e.operator == terra.kinds["-"] and #e.operands == 1 then
            local v,er = getvalue(e.operands[1])
            return type(v) == "number" and -v, er
        else
            return nil, "not a constant value (note: :asvalue() isn't implement for all constants yet)"
        end
    end
    return getvalue(self.tree)
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
function terra.symbol:tocname() return "__symbol"..tostring(self.id) end

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
    local function newfunctiondefinition(newtree,env,reciever)
        local obj = { untypedtree = newtree, filename = newtree.filename, state = "untyped", stats = {} }
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
        assert(name and type(name) == "string")
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
                if terra.islist(v) then
                    return getrecords(v)
                else
                    return getstructentry(v)
                end
            end)
        end
        local success,metatype 
        if tree.metatype then
            success,metatype = terra.evalluaexpression(diag,env,tree.metatype)
        end
        st.entries = getrecords(tree.records)
        st.tree = tree --to track whether the struct has already beend defined
                       --we keep the tree to improve error reporting
        st.anchor = tree --replace the anchor generated by newstruct with this struct definition
                         --this will cause errors on the type to be reported at the definition
        if success then
            local success,err = pcall(metatype,st)
            if not success then
                diag:reporterror(tree,"Error evaluating metatype function: "..err)
            end
        end
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
            local obj, tree = args[idx], args[idx+1]
            idx = idx + 2
            if "s" == c then
                layoutstruct(obj,tree,envfn())
            elseif "f" == c or "m" == c then
                local reciever = nil
                if "m" == c then
                    reciever = args[idx]
                    idx = idx + 1
                end
                obj:adddefinition(newfunctiondefinition(tree,envfn(),reciever))
            else
                error("unknown object format: "..c)
            end
        end
    end

    function terra.anonstruct(tree,envfn)
        local st = terra.types.newstruct("anon",2)
        layoutstruct(st,tree,envfn())
        return st
    end

    function terra.anonfunction(tree,envfn)
        local fn = mkfunction("anon ("..tree.filename..":"..tree.linenumber..")")
        fn:adddefinition(newfunctiondefinition(tree,envfn(),nil))
        return fn
    end

    function terra.newcfunction(name,typ)
        local obj = { type = typ, state = "uninitializedc" }
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

do 

    --some utility functions used to generate unique types and names
    
    --returns a function string -> string that makes names unique by appending numbers
    local function uniquenameset(sep)
        local cache = {}
        local function get(name)
            local count = cache[name]
            if not count then
                cache[name] = 1
                return name
            end
            local rename = name .. sep .. tostring(count)
            cache[name] = count + 1
            return get(rename) -- the string name<sep><count> might itself be a type name already
        end
        return get
    end
    --sanitize a string, making it a valid lua/C identifier
    local function tovalididentifier(name)
        return tostring(name):gsub("[^_%w]","_"):gsub("^(%d)","_%1"):gsub("^$","_") --sanitize input to be valid identifier
    end
    
    local function memoizefunction(fn)
        local info = debug.getinfo(fn,'u')
        local nparams = not info.isvararg and info.nparams
        local cachekey = {}
        local values = {}
        local nilkey = {} --key to use in place of nil when a nil value is seen
        return function(...)
            local key = cachekey
            for i = 1,nparams or select('#',...) do
                local e = select(i,...)
                if e == nil then e = nilkey end
                local n = key[e]
                if not n then
                    n = {}; key[e] = n
                end
                key = n
            end
            local v = values[key]
            if not v then
                v = fn(...); values[key] = v
            end
            return v
        end
    end
    
    local types = {}
    
    types.type = { name = false, tree = false, undefined = false, incomplete = false, convertible = false, cachedcstring = false, llvm_type = false, llvm_ccinfo = false, llvm_definingfunction = false} --all types have this as their metatable
    types.type.__index = function(self,key)
        local N = tonumber(key)
        if N then
            return types.array(self,N) -- int[3] should create an array
        else
            local m = types.type[key]  -- int:ispointer() (which translates to int["ispointer"](self)) should look up ispointer in types.type
            if m == nil then error("type has no field "..tostring(key),2) end
            return m
        end
    end
    
    types.type.__tostring = memoizefunction(function(self)
        if self:isstruct() then 
            if self.metamethods.__typename then
                local status,r = pcall(function() 
                    return tostring(self.metamethods.__typename(self))
                end)
                if status then return r end
            end
            return self.name
        elseif self:ispointer() then return "&"..tostring(self.type)
        elseif self:isvector() then return "vector("..tostring(self.type)..","..tostring(self.N)..")"
        elseif self:isfunction() then return self.parameters:mkstring("{",",",self.isvararg and " ...}" or "}").." -> "..tostring(self.returntype)
        elseif self:isarray() then
            local t = tostring(self.type)
            if self.type:ispointer() then
                t = "("..t..")"
            end
            return t.."["..tostring(self.N).."]"
        end
        if not self.name then error("unknown type?") end
        return self.name
    end)
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
    
    function types.type:isunit()
      return types.unit == self
    end
    
    local applies_to_vectors = {"isprimitive","isintegral","isarithmetic","islogical", "canbeord"}
    for i,n in ipairs(applies_to_vectors) do
        types.type[n.."orvector"] = function(self)
            return self[n](self) or (self:isvector() and self.type[n](self.type))  
        end
    end
    local makevalid
    
    --pretty print of layout of type
    function types.type:printpretty()
        local seen = {}
        local function print(self,d)
            local function indent(l)
                io.write("\n")
                for i = 1,d+1+(l or 0) do 
                    io.write("  ")
                end
            end
            io.write(tostring(self))
            if seen[self] then return end
            seen[self] = true
            if self:isstruct() then
                io.write(":")
                local layout = self:getlayout()
                for i,e in ipairs(layout.entries) do
                    indent()
                    io.write(e.key..": ")
                    print(e.type,d+1)
                end
            elseif self:isarray() or self:ispointer() then
                io.write(" ->")
                indent()
                print(self.type,d+1)
            elseif self:isfunction() then
                io.write(": ")
                indent() io.write("parameters: ")
                print(types.tuple(unpack(self.parameters)),d+1)
                indent() io.write("returntype:")
                print(self.returntype,d+1)
            end
        end
        print(self,0)
        io.write("\n")
    end
    local function memoizeproperty(data)
        local name = data.name
        local defaultvalue = data.defaultvalue
        local erroronrecursion = data.erroronrecursion
        local getvalue = data.getvalue

        local errorresult = { "<errorresult>" }
        local key = "cached"..name
        local inside = "inget"..name
        types.type[key],types.type[inside] = false,false
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

    local function definecstruct(nm,layout)
        local str = "struct "..nm.." { "
        local entries = layout.entries
        for i,v in ipairs(entries) do
        
            local prevalloc = entries[i-1] and entries[i-1].allocation
            local nextalloc = entries[i+1] and entries[i+1].allocation
    
            if v.inunion and prevalloc ~= v.allocation then
                str = str .. " union { "
            end
            
            local keystr = terra.issymbol(v.key) and v.key:tocname() or v.key
            str = str..v.type:cstring().." "..keystr.."; "
            
            if v.inunion and nextalloc ~= v.allocation then
                str = str .. " }; "
            end
            
        end
        str = str .. "};"
        ffi.cdef(str)
    end
    local uniquetypenameset = uniquenameset("_")
    local function uniquecname(name) --used to generate unique typedefs for C
        return uniquetypenameset(tovalididentifier(name))
    end
    function types.type:cstring()
        if not self.cachedcstring then
            --assumption: cstring needs to be an identifier, it cannot be a derived type (e.g. int*)
            --this makes it possible to predict the syntax of subsequent typedef operations
            if self:isintegral() then
                self.cachedcstring = tostring(self).."_t"
            elseif self:isfloat() then
                self.cachedcstring = tostring(self)
            elseif self:ispointer() and self.type:isfunction() then --function pointers and functions have the same typedef
                local ftype = self.type
                local rt = (ftype.returntype:isunit() and "void") or ftype.returntype:cstring()
                local function getcstring(t)
                    if t == types.rawstring then
                        --hack to make it possible to pass strings to terra functions
                        --this breaks some lesser used functionality (e.g. passing and mutating &int8 pointers)
                        --so it should be removed when we have a better solution
                        return "const char *"
                    else
                        return t:cstring()
                    end
                end
                local pa = ftype.parameters:map(getcstring)
                if not self.cachedcstring then
                    pa = pa:mkstring("(",",","")
                    if ftype.isvararg then
                        pa = pa .. ",...)"
                    else
                        pa = pa .. ")"
                    end
                    local ntyp = uniquecname("function")
                    local cdef = "typedef "..rt.." (*"..ntyp..")"..pa..";"
                    ffi.cdef(cdef)
                    self.cachedcstring = ntyp
                end
            elseif self:isfunction() then
                error("asking for the cstring for a function?",2)
            elseif self:ispointer() then
                local value = self.type:cstring()
                if not self.cachedcstring then
                    local nm = uniquecname("ptr_"..value)
                    ffi.cdef("typedef "..value.."* "..nm..";")
                    self.cachedcstring = nm
                end
            elseif self:islogical() then
                self.cachedcstring = "bool"
            elseif self:isstruct() then
                local nm = uniquecname(tostring(self))
                ffi.cdef("typedef struct "..nm.." "..nm..";") --just make a typedef to the opaque type
                                                              --when the struct is 
                self.cachedcstring = nm
                if self.cachedlayout then
                    definecstruct(nm,self.cachedlayout)
                end
            elseif self:isarray() then
                local value = self.type:cstring()
                if not self.cachedcstring then
                    local nm = uniquecname(value.."_arr")
                    ffi.cdef("typedef "..value.." "..nm.."["..tostring(self.N).."];")
                    self.cachedcstring = nm
                end
            elseif self:isvector() then
                local value = self.type:cstring()
                local elemSz = ffi.sizeof(value)
                local nm = uniquecname(value.."_vec")
                local pow2 = 1 --round N to next power of 2
                while pow2 < self.N do pow2 = 2*pow2 end
                ffi.cdef("typedef "..value.." "..nm.." __attribute__ ((vector_size("..tostring(pow2*elemSz)..")));")
                self.cachedcstring = nm 
            elseif self == types.niltype then
                local nilname = uniquecname("niltype")
                ffi.cdef("typedef void * "..nilname..";")
                self.cachedcstring = nilname
            elseif self == types.opaque then
                self.cachedcstring = "void"
            elseif self == types.error then
                self.cachedcstring = "int"
            else
                error("NYI - cstring")
            end
            if not self.cachedcstring then error("cstring not set? "..tostring(self)) end
            
            --create a map from this ctype to the terra type to that we can implement terra.typeof(cdata)            
            local ctype = ffi.typeof(self.cachedcstring)
            types.ctypetoterra[tonumber(ctype)] = self
            local rctype = ffi.typeof(self.cachedcstring.."&")
            types.ctypetoterra[tonumber(rctype)] = self
            
            if self:isstruct() then
                local function index(obj,idx)
                    local method = self:getmethod(idx)
                    if terra.isfunction(method) or type(method) == "function" then
                        return method
                    end
                    if terra.ismacro(method) then
                        error("calling a terra macro directly from Lua is not supported",2)
                    end
                    return nil
                end
                ffi.metatype(ctype, self.metamethods.__luametatable or { __index = index })
            end
        end
        return self.cachedcstring
    end

    

    types.type.getentries = memoizeproperty{
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
            if type(entries) ~= "table" then
                diag:reporterror(self.anchor,"computed entries are not a table")
                return
            end
            local function checkentry(e,results)
                if type(e) == "table" then
                    local f = e.field or e[1] 
                    local t = e.type or e[2]
                    if terra.types.istype(t) and (type(f) == "string" or terra.issymbol(f)) then
                        results:insert { type = t, field = f}
                        return
                    elseif terra.israwlist(e) then
                        local union = terra.newlist()
                        for i,se in ipairs(e) do checkentry(se,union) end
                        results:insert(union)
                        return
                    end
                end
                terra.tree.printraw(e)
                diag:reporterror(self.anchor,"expected either a field type pair (e.g. { field = <string>, type = <type> } or {<string>,<type>} ), or a list of valid entries representing a union")
            end
            local checkedentries = terra.newlist()
            for i,e in ipairs(entries) do checkentry(e,checkedentries) end
            return checkedentries
        end
    }
    local function reportopaque(anchor)
        local msg = "attempting to use an opaque type where the layout of the type is needed"
        if anchor then
            local diag = terra.getcompilecontext().diagnostics
            if not diag:haserrors() then
                terra.getcompilecontext().diagnostics:reporterror(anchor,msg)
            end
        else
            error(msg,4)
        end
    end
    types.type.getlayout = memoizeproperty {
        name = "layout"; 
        defaultvalue = { entries = terra.newlist(), keytoindex = {}, invalid = true };
        erroronrecursion = "type recursively contains itself";
        getvalue = function(self,diag,anchor)
            local tree = self.anchor
            local entries = self:getentries(anchor)
            local nextallocation = 0
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
                    elseif t == types.opaque then
                        reportopaque(tree)    
                    end
                end
                ensurelayout(t)
                local entry = { type = t, key = k, allocation = nextallocation, inunion = uniondepth > 0 }
                
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
                    if terra.islist(e) then
                        beginunion()
                        addentrylist(e)
                        endunion()
                    else
                        addentry(e.field,e.type)
                    end
                end
            end
            addentrylist(entries)
            
            dbprint(2,"Resolved Named Struct To:")
            dbprintraw(2,self)
            if not diag:haserrors() and self.cachedcstring then
                definecstruct(self.cachedcstring,layout)
            end
            return layout
        end;
    }
    function types.type:completefunction(anchor)
        assert(self:isfunction())
        for i,p in ipairs(self.parameters) do p:complete(anchor) end
        self.returntype:complete(anchor)
        return self
    end
    function types.type:complete(anchor) 
        if self.incomplete then
            if self:isarray() then
                self.type:complete(anchor)
                self.incomplete = self.type.incomplete
            elseif self == types.opaque or self:isfunction() then
                reportopaque(anchor)
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
    
    local function defaultgetmethod(self,methodname)
        local fnlike = self.methods[methodname]
        if not fnlike and terra.ismacro(self.metamethods.__methodmissing) then
            fnlike = terra.internalmacro(function(ctx,tree,...)
                return self.metamethods.__methodmissing:run(ctx,tree,methodname,...)
            end)
        end
        return fnlike
    end
    function types.type:getmethod(methodname)
        if not self:isstruct() then return nil, "not a struct" end
        local gm = (type(self.metamethods.__getmethod) == "function" and self.metamethods.__getmethod) or defaultgetmethod
        local success,result = pcall(gm,self,methodname)
        if not success then
            return nil,"error while looking up method: "..result
        elseif result == nil then
            return nil, "no such method "..tostring(methodname).." defined for type "..tostring(self)
        else
            return result
        end
    end
        
    function types.istype(t)
        return getmetatable(t) == types.type
    end
    
    --map from luajit ffi ctype objects to corresponding terra type
    types.ctypetoterra = {}
    
    local function mktyp(v)
        return setmetatable(v,types.type)
    end
    local function mkincomplete(v)
        v.incomplete = true
        return setmetatable(v,types.type)
    end
    
    local function globaltype(name, typ)
        typ.name = typ.name or name
        rawset(_G,name,typ)
        types[name] = typ
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
            globaltype(name,typ)
            typ:cstring() -- force registration of integral types so calls like terra.typeof(1LL) work
        end
    end  
    
    globaltype("float", mktyp { kind = terra.kinds.primitive, bytes = 4, type = terra.kinds.float })
    globaltype("double",mktyp { kind = terra.kinds.primitive, bytes = 8, type = terra.kinds.float })
    globaltype("bool",  mktyp { kind = terra.kinds.primitive, bytes = 1, type = terra.kinds.logical})
    
    types.error = mktyp { kind = terra.kinds.error, name = "<error>" }
    globaltype("niltype",mktyp { kind = terra.kinds.niltype}) -- the type of the singleton nil (implicitly convertable to any pointer type)
    globaltype("opaque", mkincomplete { kind = terra.kinds.opaque }) -- an type of unknown layout used with a pointer (&opaque) to point to data of an unknown type
                                                                               -- equivalent to "void *"

    local function checkistype(typ)
        if not types.istype(typ) then 
            error("expected a type but found "..type(typ))
        end
    end
    
    types.pointer = memoizefunction(function(typ)
        checkistype(typ)
        if typ == types.error then return types.error end
        return mktyp { kind = terra.kinds.pointer, type = typ }
    end)
    local function checkarraylike(typ, N_)
        local N = tonumber(N_)
        checkistype(typ)
        if not N then
            error("expected a number but found "..type(N_))
        end
        return N
    end
    
    types.array = memoizefunction(function(typ, N_)
        local N = checkarraylike(typ,N_)
        if typ == types.error then return types.error end
        return mkincomplete { kind = terra.kinds.array, type = typ, N = N }
    end)
    
    types.vector = memoizefunction(function(typ,N_)
        local N = checkarraylike(typ,N_)
        if typ == types.error then return types.error end
        if not typ:isprimitive() then
            error("vectors must be composed of primitive types (for now...) but found type "..tostring(typ))
        end
        return mktyp { kind = terra.kinds.vector, type = typ, N = N }
    end)
    types.tuple = memoizefunction(function(...)
        local args = terra.newlist {...}
        local t = types.newstruct()
        for i,e in ipairs(args) do
            checkistype(e)
            t.entries:insert {"_"..(i-1),e}
        end
        t.metamethods.__typename = function(self)
            return args:mkstring("{",",","}")
        end
        t:setconvertible("tuple")
        return t
    end)
    local getuniquestructname = uniquenameset("$")
    function types.newstruct(displayname,depth)
        displayname = displayname or "anon"
        depth = depth or 1
        return types.newstructwithanchor(displayname,terra.newanchor(1 + depth))
    end
    local cnametostruct = { general = {}, tagged = {}} --map from llvm_name -> terra type used to make c structs unique per llvm_name
    function types.getorcreatecstruct(displayname,tagged)
        local namespace
        if displayname ~= "" then
            namespace = tagged and cnametostruct.tagged or cnametostruct.general
        end
        local typ = namespace and namespace[displayname]
        if not typ then
            typ = types.newstruct(displayname == "" and "anon" or displayname)
            typ.undefined = true
            if namespace then namespace[displayname] = typ end
        end
        return typ
    end
    function types.newstructwithanchor(displayname,anchor)
        
        assert(displayname ~= "")
        local name = getuniquestructname(displayname)
                
        local tbl = mkincomplete { kind = terra.kinds["struct"],
                            name = name, 
                            entries = terra.newlist(),
                            methods = {},
                            metamethods = {},
                            anchor = anchor                  
                          }
        function tbl:setconvertible(b)
            assert(self.incomplete)
            self.convertible = b
        end
        
        return tbl
    end
   
    function types.funcpointer(parameters,ret,isvararg)
        if types.istype(parameters) then
            parameters = {parameters}
        end
        if not types.istype(ret) and terra.israwlist(ret) then
            ret = #ret == 1 and ret[1] or types.tuple(unpack(ret))
        end
        return types.pointer(types.functype(parameters,ret,isvararg))
    end
    local functypeimpl = memoizefunction(function(isvararg,ret,...)
        local parameters = terra.newlist {...}
        for i,t in ipairs(parameters) do
            checkistype(t)
        end
        return mkincomplete { kind = terra.kinds.functype, parameters = parameters, returntype = ret, isvararg = isvararg }
    end)
    function types.functype(parameters,ret,isvararg)
        checkistype(ret)
        return functypeimpl(not not isvararg,ret,unpack(parameters))
    end
    types.unit = types.tuple()
    globaltype("int",types.int32)
    globaltype("uint",types.uint32)
    globaltype("long",types.int64)
    globaltype("intptr",types.uint64)
    globaltype("ptrdiff",types.int64)
    globaltype("rawstring",types.pointer(types.int8))
    terra.types = types
    terra.memoize = memoizefunction
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
            return v.tree
        elseif terra.istree(v) then
            --if this is a raw tree, we just drop it in place and hope the user knew what they were doing
            return v
        elseif type(v) == "cdata" then
            local typ = terra.typeof(v)
            if typ:isaggregate() then --when an aggregate is directly referenced from Terra we get its pointer
                                      --a constant would make an entire copy of the object
                local ptrobj = createsingle(terra.constant(terra.types.pointer(typ),v))
                return terra.newtree(anchor, { kind = terra.kinds.operator, operator = terra.kinds["@"], operands = terra.newlist { ptrobj } }) 
            end
            return createsingle(terra.constant(typ,v))
        elseif type(v) == "number" or type(v) == "boolean" or type(v) == "string" then
            return createsingle(terra.constant(v))
        elseif terra.isconstant(v) then
            if v.stringvalue then --strings are handled specially since they are a pointer type (rawstring) but the constant is actually string data, not just the pointer
                return terra.newtree(anchor, { kind = terra.kinds.literal, value = v.stringvalue, type = terra.types.rawstring })
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
        return terra.newtree(anchor, { kind = terra.kinds.treelist, trees = values})
    else
        return createsingle(v)
    end
end

function terra.specialize(origtree, luaenv, depth)
    local env = terra.newenvironment(luaenv)
    local diag = terra.newdiagnostics()
    diag:begin()
    local translatetree, translategenerictree, translatelist, resolvetype, createformalparameterlist, desugarfornum
    local function evaltype(anchor,typ)
        local success, v = terra.evalluaexpression(diag,env:combinedenv(),typ)
        if success and terra.types.istype(v) then return v end
        if success and terra.israwlist(v) then
            for i,t in ipairs(v) do
                if not terra.types.istype(t) then
                    diag:reporterror(anchor,"expected a type but found ",type(v))
                    return terra.types.error
                end
            end
            return #v == 1 and v[1] or terra.types.tuple(unpack(v))
        end
        if success then
            diag:reporterror(anchor,"expected a type but found ",type(v))
        end
        return terra.types.error
    end
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

            if terra.types.istype(value) and value:isstruct() then --class method lookup, this is handled when typechecking
                return ee
            end

            local success,selected = terra.invokeuserfunction(e,false,function() return value[field] end)
            if not success or selected == nil then
                diag:reporterror(e,"no field ", field," in lua object")
                return ee
            end
            return terra.createterraexpression(diag,e,selected)
        elseif e:is "luaexpression" then     
            local success, value = terra.evalluaexpression(diag,env:combinedenv(),e)
            if not success then value = {} end
            return terra.createterraexpression(diag, e, value)
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
            local returntype = e.returntype and evaltype(e,e.returntype)
            local body = translatetree(e.body)
            return e:copy { parameters = parameters, returntype = returntype, body = body }
        elseif e:is "fornum" then
            --we desugar this early on so that we don't have to have special handling for the definitions/scoping
            return translatetree(desugarfornum(e))
        elseif e:is "block" then
            env:enterblock()
            local r = translategenerictree(e)
            env:leaveblock()
            return r
        elseif e:is "repeat" then
            --special handling for order of repeat
            local nb = translatetree(e.body)
            local nc = translatetree(e.condition)
            if nb ~= e.body or nc ~= e.condition then
                return e:copy { body = nb, condition = nc }
            else
                return e
            end
        elseif e:is "treelist" then
            --special handling for ordering of treelist
            local ns = e.statements and translatelist(e.statements)
            local nt = e.trees and translatelist(e.trees)
            local ne = e.expressions and translatelist(e.expressions)
            if ns ~= e.statements or nt ~= e.trees or ne ~= e.expressions then
                return e:copy { statements = ns, trees = nt, expressions = ne }
            else
                return e
            end
        else
            return translategenerictree(e)
        end
    end
    function createformalparameterlist(paramlist, requiretypes)
        local result = terra.newlist()
        for i,p in ipairs(paramlist) do
            if p.type or p.name.name then
                --treat the entry as a _single_ parameter if any are true:
                --it has an explicit type
                --it is a string (and hence cannot be multiple items) then
            
                local typ = p.type and evaltype(p,p.type)
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
            variables = terra.newlist{ s.variable };
            initializers = terra.newlist{mkvar("<i>")}
        })
        newstmts:insert(newvaras)
        for _,v in pairs(s.body.body.statements) do
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
            body = terra.newtree(s, { kind = terra.kinds.treelist, statements = newstmts });
        })
        
        local wh = terra.newtree(s, {
            kind = terra.kinds["while"];
            condition = cond;
            body = nbody;
        })

        local newlist = terra.newtree(s, { kind = terra.kinds.treelist, statements = terra.newlist {dv,wh} } )
    
        return terra.newtree(s, { kind = terra.kinds.block, body = newlist } )
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
            return startline + tonumber(line) - 1, err
        else
            return startline, errmsg
        end
    end
    if not terra.istree(e) or not e:is "luaexpression" then
       print(debug.traceback())
       terra.tree.printraw(e)
       error("not a lua expression?") 
    end
    assert(type(e.expression) == "function")
    local fn = e.expression
    local oldenv = getfenv(fn)
    setfenv(fn,env)
    local success,v = pcall(fn)
    setfenv(fn,oldenv) --otherwise, we hold false reference to env
    if not success then --v contains the error message
        local ln,err = parseerrormessage(e.linenumber,v)
        diag:reporterror(e:copy( { linenumber = ln }),"error evaluating lua code: ", diag.source, "lua error was:\n", err)
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
    local checklet -- (e.g. 3,4 of foo(3,4))

    --tree constructors for trees created in the typechecking process
    local function createcast(exp,typ)
        return terra.newtree(exp, { kind = terra.kinds.cast, from = exp.type, to = typ, type = typ:complete(exp), expression = exp })
    end
    
    local validkeystack = { {} }
    local validexpressionkeys = { [validkeystack[1]] = true}
    local function entermacroscope()
        local k = {}
        validexpressionkeys[k] = true
        table.insert(validkeystack,k)
    end
    local function leavemacroscope()
        local k = table.remove(validkeystack)
        validexpressionkeys[k] = nil
    end
    local function createtypedexpression(exp)
        return terra.newtree(exp, { kind = terra.kinds.typedexpression, expression = exp, key = validkeystack[#validkeystack] })
    end
    local function createfunctionliteral(anchor,e)
        local fntyp = ctx:referencefunction(anchor,e)
        local typ = terra.types.pointer(fntyp)
        return terra.newtree(anchor, { kind = terra.kinds.literal, value = e, type = typ })
    end
    
    local function insertaddressof(ee)
        return terra.newtree(ee,{ kind = terra.kinds.operator, type = terra.types.pointer(ee.type), operator = terra.kinds["&"], operands = terra.newlist{ee} })
    end
    
    local function insertdereference(e)
        local ret = terra.newtree(e,{ kind = terra.kinds.operator, operator = terra.kinds["@"], operands = terra.newlist{e}, lvalue = true })
        if not e.type:ispointer() then
            diag:reporterror(e,"argument of dereference is not a pointer type but ",e.type)
            ret.type = terra.types.error 
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

    local function ensurelvalue(e)
        if not e.lvalue then
            diag:reporterror(e,"argument to operator must be an lvalue")
        end
    end
    local function checklvalue(ee)
        local e = checkexp(ee)
        ensurelvalue(e) 
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
    
    --create a new variable allocation and a var node that refers to it, used to create temporary variables
    local function allocvar(anchor,typ,name)
        local av = terra.newtree(anchor, { kind = terra.kinds.allocvar, name = name , type = typ:complete(anchor), lvalue = true })
        local v = insertvar(anchor,typ,name,av)
        return av,v
    end
    
    function structcast(explicit,exp,typ, speculative)
        local cast = createcast(exp,typ)
        local from = exp.type:getlayout(exp)
        local to = typ:getlayout(exp)

        local valid = true
        local function err(...)
            valid = false
            if not speculative then
                diag:reporterror(exp,...)
            end
        end
        local var_ref
        cast.structvariable,var_ref = allocvar(exp,exp.type,"<structcast>")
        
        local initialized = {}
        cast.entries = terra.newlist()
        if #from.entries > #to.entries or (not explicit and #from.entries ~= #to.entries) then
            err("structural cast invalid, source has ",#from.entries," fields but target has only ",#to.entries)
            return cast, valid
        end
        for i,entry in ipairs(from.entries) do
            local selected = insertselect(var_ref,entry.key)
            local offset = exp.type.convertible == "tuple" and i - 1 or to.keytoindex[entry.key]
            if not offset then
                err("structural cast invalid, result structure has no key ", entry.key)
            else
                local v = insertcast(selected,to.entries[offset+1].type)
                cast.entries:insert { index = offset, value = v }
            end
        end
        
        return cast, valid
    end
    
    function insertcast(exp,typ,speculative) --if speculative is true, then an error will not be reported and the caller should check the second return value to see if the cast was valid
        if typ == nil or not terra.types.istype(typ) or not exp.type then
            print(debug.traceback())
        end
        if typ == exp.type or typ == terra.types.error or exp.type == terra.types.error then
            return exp, true
        else
            if ((typ:isprimitive() and exp.type:isprimitive()) or
                (typ:isvector() and exp.type:isvector() and typ.N == exp.type.N)) and
               not typ:islogicalorvector() and not exp.type:islogicalorvector() then
                return createcast(exp,typ), true
            elseif typ:ispointer() and exp.type:ispointer() and typ.type == terra.types.opaque then --implicit cast from any pointer to &opaque
                return createcast(exp,typ), true
            elseif typ:ispointer() and exp.type == terra.types.niltype then --niltype can be any pointer
                return createcast(exp,typ), true
            elseif typ:isstruct() and typ.convertible and exp.type:isstruct() and exp.type.convertible then 
                return structcast(false,exp,typ,speculative)
            elseif typ:ispointer() and exp.type:isarray() and typ.type == exp.type.type then
                return createcast(exp,typ), true
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
                entermacroscope()
                local quotedexp = terra.newquote(createtypedexpression(exp))
                local success,result = terra.invokeuserfunction(exp, true,__cast,exp.type,typ,quotedexp)
                if success then
                    local result = checkexp(terra.createterraexpression(diag,exp,result))
                    if result.type ~= typ then 
                        diag:reporterror(exp,"user-defined cast returned expression with the wrong type.")
                    end
                    leavemacroscope()
                    return result,true
                else
                    leavemacroscope()
                    errormsgs:insert(result)
                end
            end

            if not speculative then
                diag:reporterror(exp,"invalid conversion from ",exp.type," to ",typ)
                for i,e in ipairs(errormsgs) do
                    diag:reporterror(exp,"user-defined cast failed: ",e)
                end
            end
            return createcast(exp,typ), false
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
            if typ.bytes < terra.types.intptr.bytes then
                diag:reporterror(exp,"pointer to ",typ," conversion loses precision")
            end
            return createcast(exp,typ)
        elseif (typ:isprimitive() and exp.type:isprimitive())
            or (typ:isvector() and exp.type:isvector() and typ.N == exp.type.N) then --explicit conversions from logicals to other primitives are allowed
            return createcast(exp,typ)
        elseif typ:isstruct() and exp.type:isstruct() and exp.type.convertible then 
            return structcast(true,exp,typ)
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
                return terra.types.double
            else
                err()
                return terra.types.error
            end
        elseif a:ispointer() and b == terra.types.niltype then
            return a
        elseif a == terra.types.niltype and b:ispointer() then
            return b
        elseif a:isvector() and b:isvector() and a.N == b.N then
            local rt = typemeet(op,a.type,b.type)
            return (rt == terra.types.error and rt) or terra.types.vector(rt,a.N)
        elseif (a:isvector() and b:isprimitive()) or (b:isvector() and a:isprimitive()) then
            if a:isprimitive() then
                a,b = b,a --ensure a is vector and b is primitive
            end
            local rt = typemeet(op,a.type,b)
            return (rt == terra.types.error and rt) or terra.types.vector(rt,a.N)
        elseif a:isstruct() and b:isstruct() and a.convertible == "tuple" and b.convertible == "tuple" and #a.entries == #b.entries then
            local entries = terra.newlist()
            local as,bs = a:getentries(),b:getentries()
            for i,ae in ipairs(as) do
                local be = bs[i]
                local rt = typemeet(op,ae.type,be.type)
                if rt == terra.types.error then return rt end
                entries:insert(rt)
            end
            return terra.types.tuple(unpack(entries))
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
            return e:copy { type = terra.types.ptrdiff, operands = terra.newlist {ascompletepointer(l),ascompletepointer(r)} }
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
        local rt = terra.types.bool
        if t:isaggregate() then
            diag:reporterror(e,"cannot compare aggregate type ",t)
        elseif t:isvector() then
            rt = terra.types.vector(terra.types.bool,t.N)
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
            if cond.type:isvector() and cond.type.type == terra.types.bool then
                if not t:isvector() or t.N ~= cond.type.N then
                    diag:reporterror(ee,"conditional in select is not the same shape as ",cond.type)
                end
            elseif cond.type ~= terra.types.bool then
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
    
    local defersinlocalscope,checklocaldefers --functions used to determine if defer statements are in the wrong places
                                              --defined with machinery for checking statements
    
    local function checkoperator(ee)
        local op_string = terra.kinds[ee.operator]
        
        --check non-overloadable operators first
        if op_string == "@" then
            local e = checkexp(ee.operands[1])
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
        
        local ndefers = defersinlocalscope()
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
            return checkcall(ee, overloads, operands, "all", true, false)
        else
            local r = op(ee,operands)
            if (op_string == "and" or op_string == "or") and operands[1].type:islogical() then
                checklocaldefers(ee, ndefers)
            end
            return r
        end
    end

    --functions to handle typecheck invocations (functions,methods,macros,operator overloads)
    local function removeluaobject(e)
        if not e:is "luaobject" or e.type == terra.types.error then 
            return e --don't repeat error messages
        elseif terra.isfunction(e.value) then
            local definitions = e.value:getdefinitions()
            if #definitions ~= 1 then
                diag:reporterror(e,(#definitions == 0 and "undefined") or "overloaded", " functions cannot be used as values")
                return e:copy { type = terra.types.error }
            end
            return createfunctionliteral(e,definitions[1])
        else
            if terra.types.istype(e.value) then
                diag:reporterror(e, "expected a terra expression but found terra type ", tostring(e.value), ". If this is a cast, you may have omitted the required parentheses: [T](exp)")
            else  
                diag:reporterror(e, "expected a terra expression but found ",type(e.value))
            end
            return e:copy { type = terra.types.error }
        end
    end
    
    local function checkexpressions(expressions,allowluaobject)
        local nes = terra.newlist()
        for i,e in ipairs(expressions) do
            local ne = checkexp(e,allowluaobject)
            if ne:is "treelist" and not ne.statements then
                nes:insertall(ne.expressions)
            else
                nes:insert(ne)
            end
        end
        return nes
    end
    
   function checklet(anchor, statements, expressions)
        local ns = statements and statements:map(checkstmt)
        local ne = expressions and checkexpressions(expressions)
        local r = terra.newtree(anchor, { kind = terra.kinds.treelist, statements = ns, expressions = ne })
        if ne and #ne == 1 then
            r.type,r.lvalue = ne[1].type,ne[1].lvalue
        else
            r.type = not ne and terra.types.unit or terra.types.tuple(unpack(ne:map("type")))
        end
        r.type:complete(anchor)
        return r
    end
    
    local function insertvarargpromotions(param)
        if param.type == terra.types.float then
            return insertcast(param,terra.types.double)
        elseif param.type:isarray() then
            --varargs are only possible as an interface to C (or Lua) where arrays are not value types
            --this can cause problems (e.g. calling printf) when Terra passes the value
            --so we degrade the array into pointer when it is an argument to a vararg parameter
            return insertcast(param,terra.types.pointer(param.type.type))
        end
        --TODO: do we need promotions for integral data types or does llvm already do that?
        return param
    end

    local function tryinsertcasts(anchor, typelists,castbehavior, speculate, allowambiguous, paramlist)
        local PERFECT_MATCH,CAST_MATCH,TOP = 1,2,math.huge
         
        local function trylist(typelist, speculate)
            if #typelist ~= #paramlist then
                if not speculate then
                    diag:reporterror(anchor,"expected "..#typelist.." parameters, but found "..#paramlist)
                end
                return false
            end
            local results,matches = terra.newlist(),terra.newlist()
            for i,typ in ipairs(typelist) do
                local param,result,match,valid = paramlist[i]
                if typ == "passthrough" or typ == param.type then
                    result,match = param,PERFECT_MATCH
                else
                    match = CAST_MATCH
                    if castbehavior == "all" or i == 1 and castbehavior == "first" then
                        result,valid = insertrecievercast(param,typ,speculate)
                    elseif typ == "vararg" then
                        result,valid = insertvarargpromotions(param),true
                    else
                        result,valid = insertcast(param,typ,speculate)
                    end
                    if not valid then return false end
                end
                results[i],matches[i] = result,match
            end
            return true,results,matches
        end
        if #typelists == 1 then
            local valid,results = trylist(typelists[1],speculate)
            if not valid then
                return paramlist,nil
            else
                return results, 1
            end
        else
            local function meetwith(a,b)
                local ale, ble = true,true
                local meet = terra.newlist()
                for i = 1,#paramlist do
                    local m = math.min(a[i] or TOP,b[i] or TOP)
                    ale = ale and a[i] == m
                    ble = ble and b[i] == m
                    a[i] = m
                end
                return ale,ble --a = a meet b, a <= b, b <= a
            end

            local results,matches = terra.newlist(),terra.newlist()
            for i,typelist in ipairs(typelists) do
                local valid,nr,nm = trylist(typelist,true)
                if valid then
                    local ale,ble = meetwith(matches,nm)
                    if ale == ble then
                        if ale and not matches.exists then
                            results = terra.newlist()
                        end
                        results:insert( { expressions = nr, idx = i } )
                        matches.exists = ale
                    elseif ble then
                        results = terra.newlist { { expressions = nr, idx = i } }
                        matches.exists = true
                    end
                end
            end
            if #results == 0 then
                --no options were valid and our caller wants us to, lets emit some errors
                if not speculate then
                    diag:reporterror(anchor,"call to overloaded function does not apply to any arguments")
                    for i,typelist in ipairs(typelists) do
                        diag:reporterror(anchor,"option ",i," with type ",typelist:mkstring("(",",",")"))
                        trylist(typelist,false)
                    end
                end
                return paramlist,nil
            else
                if #results > 1 and not allowambiguous then
                    local strings = results:map(function(x) return typelists[x.idx]:mkstring("type list (",",",") ") end)
                    diag:reporterror(anchor,"call to overloaded function is ambiguous. can apply to ",unpack(strings))
                end 
                return results[1].expressions, results[1].idx
            end
        end
    end
    
    local function insertcasts(anchor, typelist,paramlist) --typelist is a list of target types (or the value "passthrough"), paramlist is a parameter list that might have a multiple return value at the end
        return tryinsertcasts(anchor, terra.newlist { typelist }, "none", false, false, paramlist)
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

        local fnlike,errmsg
        if ismeta then
            fnlike = objtyp.metamethods[methodname]
            errmsg = fnlike == nil and "no such metamethodmethod "..methodname.." defined for type "..tostring(objtyp)
        else
            fnlike,errmsg = objtyp:getmethod(methodname)
        end

        if not fnlike then
            diag:reporterror(anchor,errmsg)
            return anchor:copy { type = terra.types.error }
        end

        fnlike = terra.createterraexpression(diag, anchor, fnlike) 
        local fnargs = terra.newlist { reciever }
        for i,a in ipairs(arguments) do
            fnargs:insert(a)
        end
        return checkcall(anchor, terra.newlist { fnlike }, fnargs, "first", false, isstatement)
    end

    local function checkmethod(exp, isstatement)
        local methodname = exp.name
        assert(type(methodname) == "string" or terra.issymbol(methodname))
        local reciever = checkexp(exp.value)
        local arguments = checkexpressions(exp.arguments,true)
        return checkmethodwithreciever(exp, false, methodname, reciever, arguments, isstatement)
    end

    local function checkapply(exp, isstatement)
        local fnlike = checkexp(exp.value,true)
        local arguments = checkexpressions(exp.arguments,true)
        if not fnlike:is "luaobject" then
            if fnlike.type:isstruct() or fnlike.type:ispointertostruct() then
                return checkmethodwithreciever(exp, true, "__apply", fnlike, arguments, isstatement) 
            end
        end
        return checkcall(exp, terra.newlist { fnlike } , arguments, "none", false, isstatement)
    end
    function checkcall(anchor, fnlikelist, arguments, castbehavior, allowambiguous, isstatement)
        --arguments are always typed trees, or a lua object
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
            callee.type.type:completefunction(anchor)
            return terra.newtree(anchor, { kind = terra.kinds.apply, arguments = paramlist, paramtypes = paramlist:map("type"), value = callee, type = callee.type.type.returntype })
        end

        local function generatenativewrapper(fn)
            local paramlist = arguments:map(removeluaobject)
            local varargslist = paramlist:map(function(p) return "vararg" end)
            paramlist = tryinsertcasts(anchor, terra.newlist{varargslist},castbehavior, false, false, paramlist)
            local castedtype = terra.types.funcpointer(paramlist:map("type"),{})
            local cb = terra.cast(castedtype,fn)
            local fptr = terra.pointertolightuserdata(cb)
            return terra.newtree(anchor, { kind = terra.kinds.luafunction, callback = cb, fptr = fptr, type = castedtype }),paramlist
        end
        
        if #terrafunctions > 0 then
            local paramlist = arguments:map(removeluaobject)
            local function getparametertypes(fn) --get the expected types for parameters to the call (this extends the function type to the length of the parameters if the function is vararg)
                local fntyp = fn.type.type
                if not fntyp.isvararg then return fntyp.parameters end
                local vatypes = terra.newlist()
                vatypes:insertall(fntyp.parameters)
                for i = 1,#paramlist - #fntyp.parameters do
                    vatypes:insert("vararg")
                end
                return vatypes
            end
            local typelists = terrafunctions:map(getparametertypes)
            local castedarguments,valididx = tryinsertcasts(anchor,typelists,castbehavior, fnlike ~= nil, allowambiguous, paramlist)
            if valididx then
                return createcall(terrafunctions[valididx],castedarguments)
            end
        end

        if fnlike then
            if terra.ismacro(fnlike) then
                entermacroscope()
                
                local quotes = arguments:map(function(a)
                    return terra.newquote(createtypedexpression(a))
                end)
                local success, result = terra.invokeuserfunction(anchor, false, fnlike.run, fnlike, diag, anchor, unpack(quotes))
                if success then
                    local newexp = terra.createterraexpression(diag,anchor,result)
                    result = isstatement and checkstmt(newexp) or checkexp(newexp,true)
                else
                    result = anchor:copy { type = terra.types.error }
                end
                
                leavemacroscope()
                return result
            elseif type(fnlike) == "function" then
                local callee,paramlist = generatenativewrapper(fnlike)
                return createcall(callee,paramlist)
            else 
                error("fnlike is not a function/macro?")
            end
        end
        assert(diag:haserrors())
        return anchor:copy { type = terra.types.error }
    end

    --functions that handle the checking of expressions
    
    local function checkintrinsic(e)
        local params = checkexpressions(e.arguments)
        local types = params:map("type")
        local name,intrinsictype = e.typefn(types)
        if type(name) ~= "string" then
            diag:reporterror(e,"expected an intrinsic name but found ",tostring(name))
            return e:copy { type = terra.types.error }
        elseif intrinsictype == terra.types.error then
            diag:reporterror(e,"intrinsic ",name," does not support arguments: ",unpack(types))
            return e:copy { type = terra.types.error }
        elseif not terra.types.istype(intrinsictype) or not intrinsictype:ispointertofunction() then
            diag:reporterror(e,"expected intrinsic to resolve to a function type but found ",tostring(intrinsictype))
            return e:copy { type = terra.types.error }
        end
        params = insertcasts(e,intrinsictype.type.parameters,params)
        return e:copy { type = intrinsictype.type.returntype, name = name, arguments = params, intrinsictype = intrinsictype }
    end

    local function checksymbol(sym)
        assert(terra.issymbol(sym) or type(sym) == "string")
        return sym
    end

    function checkexp(e_, allowluaobjects)
        local function docheck(e)
            if not terra.istree(e) then
                print("not a tree?")
                print(debug.traceback())
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
                local v = checkexp(e.value,true)
                local field = checksymbol(e.field)
                --check for and handle Type.staticmethod
                if v:is "luaobject" and terra.types.istype(v.value) and v.value:isstruct() then
                    local fnlike, errmsg = v.value:getmethod(field)
                    if not fnlike then
                        diag:reporterror(e,errmsg)
                        return e:copy { type = terra.types.error }
                    end
                    return terra.createterraexpression(diag,e,fnlike)
                end
                
                v = removeluaobject(v)
                
                if v.type:ispointertostruct() then --allow 1 implicit dereference
                    v = insertdereference(v)
                end

                if v.type:isstruct() then
                    local ret, success = insertselect(v,field)
                    if not success then
                        --struct has no member field, call metamethod __entrymissing
                        local typ = v.type
                        if terra.ismacro(typ.metamethods.__entrymissing) then
                            local named = terra.internalmacro(function(ctx,tree,...)
                                return typ.metamethods.__entrymissing:run(ctx,tree,field,...)
                            end)
                            local getter = terra.createterraexpression(diag, e, named) 
                            return checkcall(v, terra.newlist{ getter }, terra.newlist { v }, "first", false, false)
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
            elseif e:is "typedexpression" then --expression that has been previously typechecked and re-injected into the compiler
                if not validexpressionkeys[e.key] then --if it went through a macro, it could have been retained by lua code and returned to a different scope or even a different function
                                                       --we check that this didn't happen by checking that we are still inside the same scope where the expression was created
                    diag:reporterror(e,"cannot use a typed expression from one scope/function in another")
                    diag:reporterror(ftree,"typed expression used in this function.")
                end
                return e.expression
            elseif e:is "operator" then
                return checkoperator(e)
            elseif e:is "index" then
                local v = checkexp(e.value)
                local idx = checkexp(e.index)
                local typ,lvalue = terra.types.error, v.type:ispointer() or (v.type:isarray() and v.lvalue) 
                if v.type:ispointer() or v.type:isarray() or v.type:isvector() then
                    typ = v.type.type
                    if not idx.type:isintegral() and idx.type ~= terra.types.error then
                        diag:reporterror(e,"expected integral index but found ",idx.type)
                    end
                    if v.type:isarray() then
                        v = insertcast(v,terra.types.pointer(typ))
                    end
                else
                    if v.type ~= terra.types.error then
                        diag:reporterror(e,"expected an array or pointer but found ",v.type)
                    end
                end
                return e:copy { type = typ, lvalue = lvalue, value = v, index = idx }
            elseif e:is "explicitcast" then
                return insertexplicitcast(checkexp(e.value),e.totype)
            elseif e:is "sizeof" then
                e.oftype:complete(e)
                return e:copy { type = terra.types.uint64 }
            elseif e:is "vectorconstructor" or e:is "arrayconstructor" then
                local entries = checkexpressions(e.expressions)
                local N = #entries
                         
                local typ
                if e.oftype ~= nil then
                    typ = e.oftype:complete(e)
                else
                    if N == 0 then
                        diag:reporterror(e,"cannot determine type of empty aggregate")
                        return e:copy { type = terra.types.error }
                    end
                    
                    --figure out what type this vector has
                    typ = entries[1].type
                    for i,e2 in ipairs(entries) do
                        typ = typemeet(e,typ,e2.type)
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
                local typs = entries:map(function(x) return typ end)
                entries = insertcasts(e,typs,entries)
                return e:copy { type = aggtype, expressions = entries }
            elseif e:is "attrload" then
                local addr = checkexp(e.address)
                if not addr.type:ispointer() then
                    diag:reporterror(e,"address must be a pointer but found ",addr.type)
                    return e:copy { type = terra.types.error }
                end
                return e:copy { type = addr.type.type, address = addr }
            elseif e:is "attrstore" then
                local addr = checkexp(e.operands[1])
                if not addr.type:ispointer() then
                    diag:reporterror(e,"address must be a pointer but found ",addr.type)
                    return e:copy { type = terra.types.error }
                end
                local value = insertcast(checkexp(e.operands[2]),addr.type.type)
                return e:copy { address = addr, value = value, type = terra.types.unit }
            elseif e:is "apply" then
                return checkapply(e,false)
            elseif e:is "method" then
                return checkmethod(e,false)
            elseif e:is "treelist" then
                symbolenv:enterblock()
                local result = checklet(e,e.statements, e.trees or e.expressions)
                symbolenv:leaveblock()
                return result
           elseif e:is "constructor" then
                local paramlist = terra.newlist()
                local named = 0
                for i,f in ipairs(e.records) do
                    local value = checkexp(f.value)
                    named = named + (f.key and 1 or 0)
                    if not f.key and value:is "treelist" and not value.statements then
                        paramlist:insertall(value.expressions)
                    else
                        paramlist:insert(value)
                    end
                end
                local typ = terra.types.error
                if named == 0 then
                    typ = terra.types.tuple(unpack(paramlist:map("type")))
                elseif named == #e.records then
                    typ = terra.types.newstructwithanchor("anon",e)
                    typ:setconvertible("named")
                    for i,e in ipairs(e.records) do
                        typ.entries:insert({field = e.key, type = paramlist[i].type})
                    end
                else
                    diag:reporterror(e, "some entries in constructor are named while others are not")
                end
                return e:copy { type = typ:complete(e), expressions = paramlist }
            elseif e:is "intrinsic" then
                return checkintrinsic(e)
            else
                diag:reporterror(e,"statement found where an expression is expected ", terra.kinds[e.kind])
                return e:copy { type = terra.types.error }
            end
        end
        
        local result = docheck(e_)
        --freeze all types returned by the expression (or list of expressions)
        if not result:is "luaobject" then
            assert(terra.types.istype(result.type))
            result.type:complete(result)
        end

        --remove any lua objects if they are not allowed in this context
        if not allowluaobjects then
            result = removeluaobject(result)
        end
        
        return result
    end

    --helper functions used in checking statements:
    
    local function checkexptyp(re,target)
        local e = checkexp(re)
        if e.type ~= target then
            diag:reporterror(e,"expected a ",target," expression but found ",e.type)
            e.type = terra.types.error
        end
        return e
    end
    local function checkcond(c)
        local N = defersinlocalscope()
        local r = checkexptyp(c,terra.types.bool)
        checklocaldefers(c,N)
        return r
    end
    local function checkcondbranch(s)
        local e = checkcond(s.condition)
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
        return params:map(function(p) return terra.newtree(p, {kind = terra.kinds.allocvar, name = p.name, symbol = p.symbol, type = p.type, lvalue = true})  end)
    end


    --state that is modified by checkstmt:
    
    local return_stmts = terra.newlist() --keep track of return stms, these will be merged at the end, possibly inserting casts
    
    local labels = {} --map from label name to definition (or, if undefined to the list of already seen gotos that target that label)
    local loopstmts = terra.newlist() -- stack of loopstatements (for resolving where a break goes)
    local scopeposition = terra.newlist() --list(int), count of number of defer statements seens at each level of block scope, used for unwinding defer statements during break/goto
    
    
    local function getscopeposition()
        local sp = terra.newlist()
        for i,p in ipairs(scopeposition) do sp[i] = p end
        return sp
    end
    local function enterloop()
        local bt = {position = getscopeposition()}
        loopstmts:insert(bt)
        return bt
    end
    local function leaveloop()
        loopstmts:remove()
    end
    function defersinlocalscope()
        return scopeposition[#scopeposition]
    end
    function checklocaldefers(anchor,c)
        if defersinlocalscope() ~= c then
            diag:reporterror(anchor, "defer statements are not allowed in conditional expressions")
        end
    end
    --calculate the number of deferred statements that will fire when jumping from stack position 'from' to 'to'
    --if a goto crosses a deferred statement, we detect that and report an error
    local function numberofdeferredpassed(anchor,from,to)
        local N = math.max(#from,#to)
        for i = 1,N do
            local t,f = to[i] or 0, from[i] or 0
            if t < f then
                local c = f - t
                for j = i+1,N do
                    if (to[j] or 0) ~= 0 then
                        diag:reporterror(anchor,"goto crosses the scope of a deferred statement")
                    end
                    c = c + (from[j] or 0)
                end
                return c
            elseif t > f then
                diag:reporterror(anchor,"goto crosses the scope of a deferred statement")
                return 0
            end
        end
        return 0
    end
    
    local function createassignment(anchor,lhs,rhs)
        for i,exp in ipairs(lhs) do ensurelvalue(exp) end
        if #lhs > #rhs and #rhs > 0 then
            local last = rhs[#rhs]
            if last.type:isstruct() and last.type.convertible == "tuple" and #last.type.entries + #rhs - 1 == #lhs then
                --struct pattern match
                local av,v = allocvar(anchor,last.type,"<structpattern>")
                local newlhs,lhsp,rhsp = terralib.newlist(),terralib.newlist(),terralib.newlist()
                for i,l in ipairs(lhs) do
                    if i < #rhs then
                        newlhs:insert(l)
                    else
                        lhsp:insert(l)
                        rhsp:insert((insertselect(v,"_"..tostring(i - #rhs))))
                    end
                end
                newlhs[#rhs] = av
                local a1,a2 = createassignment(anchor,newlhs,rhs), createassignment(anchor,lhsp,rhsp)
                return terra.newtree(anchor, {kind = terra.kinds.treelist, statements = terra.newlist { a1,a2 }})
            end
        end
        local vtypes = lhs:map(function(v) return v.type or "passthrough" end)
        rhs = insertcasts(anchor,vtypes,rhs)
        for i,v in ipairs(lhs) do
            v.type = rhs[i] and rhs[i].type or terra.types.error
        end
        return terra.newtree(anchor,{kind = terra.kinds.assignment, lhs = lhs, rhs = rhs })
    end
    -- checking of statements
    function checkstmt(s)
        if s:is "block" then
            symbolenv:enterblock()
            scopeposition:insert(0)
            local r = checkstmt(s.body)
            table.remove(scopeposition)
            symbolenv:leaveblock()
            return s:copy {body = r}
        elseif s:is "return" then
            local rstmt = s:copy { expression = checklet(s,nil,s.expressions) }
            return_stmts:insert( rstmt )
            return rstmt
        elseif s:is "label" then
            local ss = s:copy {}
            local label = checksymbol(ss.value)
            ss.labelname = tostring(label)
            ss.position = getscopeposition()
            local lbls = labels[label] or terra.newlist()
            if terra.istree(lbls) then
                diag:reporterror(s,"label defined twice")
                diag:reporterror(lbls,"previous definition here")
            else
                for _,v in ipairs(lbls) do
                    v.definition = ss
                    v.deferred = numberofdeferredpassed(v,v.position,ss.position)
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
                ss.deferred = numberofdeferredpassed(s,scopeposition,ss.definition.position)
            else
                ss.position = getscopeposition()
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
                ss.deferred = numberofdeferredpassed(s,scopeposition,ss.breaktable.position)
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
            local els = (s.orelse and checkstmt(s.orelse))
            return s:copy{ branches = br, orelse = els }
        elseif s:is "repeat" then
            local breaktable = enterloop()
            local new_body = checkstmt(s.body)
            local e = checkcond(s.condition)
            leaveloop()
            return s:copy { body = new_body, condition = e, breaktable = breaktable }
        elseif s:is "defvar" then
            local lhs = checkformalparameterlist(s.variables)
            local res = s.initializers and createassignment(s,lhs,checkexpressions(s.initializers)) 
                        or terra.newtree(s, {kind = terra.kinds.treelist, statements = lhs})
            --add the variables to current environment
            for i,v in ipairs(lhs) do
                assert(terra.issymbol(v.symbol))
                symbolenv:localenv()[v.symbol] = v
            end
            return res
        elseif s:is "assignment" then
            local rhs = checkexpressions(s.rhs)
            local lhs = checkexpressions(s.lhs)
            return createassignment(s,lhs,rhs)
        elseif s:is "apply" then
            return checkapply(s,true)
        elseif s:is "method" then
            return checkmethod(s,true)
        elseif s:is "treelist" then
            return checklet(s,s.trees or s.statements, s.expressions)
        elseif s:is "defer" then
            local call = checkexp(s.expression)
            if not call:is "apply" then
                diag:reporterror(s.expression,"deferred statement must resolve to a function call")
            end
            scopeposition[#scopeposition] = scopeposition[#scopeposition] + 1
            return s:copy { expression = call }
        else
            return checkexp(s)
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
    local returntype = ftree.returntype or #return_stmts == 0 and terra.types.unit
    if not returntype then --calculate the meet of all return type to calculate the actual return type
        for _,stmt in ipairs(return_stmts) do
            local typ = stmt.expression.type
            returntype = returntype and typemeet(stmt.expression,returntype,typ) or typ
        end
    end
    
    local fntype = terra.types.functype(parameter_types,returntype):completefunction(ftree)

    --now cast each return expression to the expected return type
    for _,stmt in ipairs(return_stmts) do
        stmt.expression = insertcast(stmt.expression,returntype)
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
    local args = terra.newlist {"-O3","-Wno-deprecated",...}
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
terra.sizeof = terra.internalmacro(
function(diag,tree,typ)
    return terra.newtree(tree,{ kind = terra.kinds.sizeof, oftype = typ:astype()})
end,
function (terratype,...)
    terratype:complete()
    return terra.llvmsizeof(terratype)
end
)
_G["sizeof"] = terra.sizeof
_G["vector"] = terra.internalmacro(
function(diag,tree,...)
    if not diag then
        error("nil first argument in vector constructor")
    end
    if not tree then
        error("nil second argument in vector constructor")
    end
    local exps = terra.newlist({...}):map(function(x) return x.tree end)
    return terra.newtree(tree,{ kind = terra.kinds.vectorconstructor, expressions = exps })
end,
terra.types.vector
)
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
terra.unpackstruct = terra.internalmacro(function(diag,tree,obj)
    local typ = obj:gettype()
    if not obj or not typ:isstruct() or typ.convertible ~= "tuple" then
        return obj
    end
    if not obj:islvalue() then diag:reporterror("expected an lvalue") end
    local result = terralib.newlist()
    for i,e in ipairs(typ:getentries()) do 
        if e.field then
            result:insert(terra.newtree(tree, {kind = terra.kinds.select, field = e.field, value = obj.tree }))
        end
    end
    return result
end,
function(cdata)
    local t = type(cdata) == "cdata" and terra.typeof(cdata)
    if not t or not t:isstruct() or t.convertible ~= "tuple" then 
      return cdata
    end
    local results = terralib.newlist()
    for i,e in ipairs(t:getentries()) do
        if e.field then
            local nm = terra.issymbol(e.field) and e.field:tocname() or e.field
            results:insert(cdata[nm])
        end
    end
    return unpack(results)
end)
_G["unpackstruct"] = terra.unpackstruct
_G["unpacktuple"] = terra.unpackstruct
_G["tuple"] = terra.types.tuple
_G["global"] = terra.global

terra.select = terra.internalmacro(function(diag,tree,guard,a,b)
    return terra.newtree(tree, { kind = terra.kinds.operator, operator = terra.kinds.select, operands = terra.newlist{guard.tree,a.tree,b.tree}})
end)

local function createattributetable(q)
    local attr = q:asvalue()
    if type(attr) ~= "table" then
        error("attributes must be a table")
    end
    local cleanattr = { nontemporal = attr.nontemporal and true,
                        alignment = (type(attr.align) == "number" and attr.align),
                        isvolatile = attr.isvolatile and true} 
    return cleanattr
end

terra.attrload = terra.internalmacro( function(diag,tree,addr,attr)
    if not addr or not attr then
        error("attrload requires two arguments")
    end
    return terra.newtree(tree, { kind = terra.kinds.attrload, address = addr.tree, attributes = createattributetable(attr) } )
end)

terra.attrstore = terra.internalmacro( function(diag,tree,addr,value,attr)
    if not addr or not value or not attr then
        error("attrstore requires three arguments")
    end
    return terra.newtree(tree, { kind = terra.kinds.attrstore, operands = terra.newlist { addr.tree, value.tree }, attributes = createattributetable(attr) })
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

function terra.func:__tostring()
    return "<terra function>"
end

local function printpretty(toptree,returntype)
    local env = terra.newenvironment({})
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
    local function emitIdent(name,sym)
        local lenv = env:localenv()
        local assignedname = lenv[sym]
        --if we haven't seen this symbol in this scope yet, assign a name for this symbol, favoring the non-mangled name
        if not assignedname then
            if lenv[name] then
                name = name.."$"..sym.id
            end
            lenv[name],lenv[sym],assignedname = true,name,name
        end
        emit("%s",assignedname)
    end
    local function emitParam(p)
        emitIdent(p.name,p.symbol)
        if p.type then 
            emit(" : %s",p.type)
        end
    end
    local emitStmt, emitExp,emitParamList,emitTreeList
    local function emitStmtList(lst) --nested Blocks (e.g. from quotes need "do" appended)
        for i,ss in ipairs(lst) do
            if ss:is "block" then
                begin("do\n")
                emitStmt(ss)
                begin("end\n")
            else
                emitStmt(ss)
            end
        end
    end
    local function emitAttr(a)
        emit("{ nontemporal = %s, align = %s, isvolatile = %s }",a.nontemporal or "false",a.align or "native",a.isvolatile or "false")
    end
    function emitStmt(s)
        if s:is "block" then
            enterblock()
            env:enterblock()
            emitStmt(s.body)
            env:leaveblock()
            leaveblock()
        elseif s:is "treelist" then
            if s.statements then
                emitStmtList(s.statements)
            end
            if s.trees then
                emitStmtList(s.trees)
            end
            if s.expressions then
                emitStmtList(s.expressions)
            end
            if s.next then
                emitStmt(s.next)
            end
        elseif s:is "apply" then
            begin("r%s = ",tostring(s):match("(0x.*)$"))
            emitExp(s)
            emit("\n")
        elseif s:is "return" then
            begin("return ")
            if s.expression then emitExp(s.expression)
            else emitParamList(s.expressions) end
            emit("\n")
        elseif s:is "label" then
            begin("::%s::\n",s.labelname or s.value)
        elseif s:is "goto" then
            begin("goto %s (%s)\n",s.definition and s.definition.labelname or s.label,s.deferred or "")
        elseif s:is "break" then
            begin("break (%s)\n",s.deferred or "")
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
            if s.orelse then
                begin("else\n")
                emitStmt(s.orelse)
            end
            begin("end\n")
        elseif s:is "repeat" then
            begin("repeat\n")
            enterblock()
            emitStmt(s.body)
            leaveblock()
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
            emitParamList(s.lhs)
            emit(" = ")
            emitParamList(s.rhs)
            emit("\n")
        elseif s:is "defer" then
            begin("defer ")
            emitExp(s.expression)
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
    local function doparens(ref,e,isrhs)
        local pr, pe = getprec(ref), getprec(e)
        if pr > pe or (isrhs and pr == pe) then
            emit("(")
            emitExp(e)
            emit(")")
        else
            emitExp(e)
        end
    end

    function emitExp(e)
        if e:is "var" then
            emitIdent(e.name,e.value)
        elseif e:is "allocvar" then
            emit("var ")
            emitParam(e)
        elseif e:is "operator" then
            local op = terra.kinds[e.operator]
            local function emitOperand(o,isrhs)
                doparens(e,o,isrhs)
            end
            if #e.operands == 1 then
                emit(op)
                emitOperand(e.operands[1])
            elseif #e.operands == 2 then
                emitOperand(e.operands[1])
                emit(" %s ",op)
                emitOperand(e.operands[2],true)
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
                emit("%s",tostring(e.value))
            end
        elseif e:is "luafunction" then
            emit("<lua %s>",tostring(e.callback))
        elseif e:is "cast" or e:is "explicitcast" then
            emit("[")
            emitType(e.to or e.totype)
            emit("](")
            emitExp(e.expression or e.value)
            emit(")")
        elseif e:is "sizeof" then
            emit("sizeof(%s)",e.oftype)
        elseif e:is "apply" then
            doparens(e,e.value)
            emit("(")
            emitParamList(e.arguments)
            emit(")")
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
            if e.type then
                local keys = e.type:getlayout().entries:map(function(e) return e.key end)
                emitList(keys,"",", "," = ",emit)
                emitParamList(e.expressions,keys)
            else
                local function emitRec(r)
                    if r.key then
                        emit("%s = ",r.key)
                    end
                    emitExp(r.value)
                end
                emitList(e.records,"",", ","",emitRec)
            end
            emit("}")
        elseif e:is "constant" then
            if e.type:isprimitive() then
                emit(tonumber(e.value.object))
            else
                emit("<constant:"..tostring(e.type)..">")
            end
        elseif e:is "treelist" then
            emitTreeList(e)
        elseif e:is "attrload" then
            emit("attrload(")
            emitExp(e.address)
            emit(", ")
            emitAttr(e.attributes)
            emit(")")
        elseif e:is "attrstore" then
            begin("attrstore(")
            emitExp(e.address)
            emit(", ")
            emitExp(e.value)
            emit(", ")
            emitAttr(e.attributes)
            emit(")\n")
        elseif e:is "intrinsic" then
            emit("intrinsic<%s>(",e.name)
            emitParamList(e.arguments)
            emit(")")
        elseif e:is "luaobject" then
            if terra.types.istype(e.value) then
                emit("[%s]",e.value)
            elseif terra.ismacro(e.value) then
                emit("<macro>")
            elseif terra.isfunction(e.value) then
                emit("%s",e.value.name or e.value:getdefinitions()[1].name or "<anonfunction>")
            else
                emit("<lua value: %s>",tostring(e.value))
            end
        elseif e:is "method" then
             doparens(e,e.value)
             emit(":%s",e.name)
             emit("(")
             emitParamList(e.arguments)
             emit(")")
        elseif e:is "typedexpression" then
            emitExp(e.expression)
        else
            emit("<??"..terra.kinds[e.kind].."??>")
        end
    end
    function emitParamList(pl)
        emitList(pl,"",", ","",emitExp)
    end
    function emitTreeList(pl)
        if pl.statements then
            emit("let\n")
            enterblock()
            emitStmtList(pl.statements)
            leaveblock()
            begin("in\n")
            enterblock()
            begin("")
        end
        local exps = pl.expressions or pl.trees
        if exps then
            emitList(exps,"",", ","",emitExp)
        end
        if pl.statements then
            leaveblock()
            emit("\n")
            begin("end")
        end
    end

    if toptree:is "function" then
        emit("terra")
        emitList(toptree.parameters,"(",",",") ",emitParam)
        if returntype then
            emit(": ")
            emitType(returntype)
        end
        emit("\n")
        emitStmt(toptree.body)
        emit("end\n")
    else
        emitExp(toptree)
        emit("\n")
    end
end

function terra.func:printpretty(printcompiled)
    printcompiled = (printcompiled == nil) or printcompiled
    for i,v in ipairs(self.definitions) do
        terra.printf("%s = ",v.name)
        v:printpretty(printcompiled)
    end
end

function terra.funcdefinition:printpretty(printcompiled)
    printcompiled = (printcompiled == nil) or printcompiled
    if not self.untypedtree then
        terra.printf("<extern : %s>\n",self.type)
        return
    end
    if printcompiled then
        self:compile()
        return printpretty(self.typedtree,self.type.returntype)
    else
        return printpretty(self.untypedtree,self.returntype)
    end
end
function terra.quote:printpretty()
    printpretty(self.tree)
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


package.path = (not os.getenv("LUA_PATH") and package.path .. ";./?.t") or package.path 
function terra.require(name)
    if package.loaded[name] == nil then
        local fname = name:gsub("%.","/")
        local file = nil
        for template in package.path:gmatch("([^;]+);?") do
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
        local result = fn()
        if package.loaded[name] == nil then
            package.loaded[name] = result ~= nil and result or true
        end
    end
    return package.loaded[name]
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
        if type(c.object) == "string" and c.type == terra.types.rawstring then
            c.stringvalue = c.object --save string type for special handling in compiler
        end

        --if the  object is not already cdata, we need to convert it
        if  type(c.object) ~= "cdata" or terra.typeof(c.object) ~= c.type then
            local obj = c.object
            c.object = terra.cast(c.type,obj)
            c.origobject = type(obj) == "cdata" and obj --conversion from obj -> &obj
                                                        --need to retain reference to obj or it can be GC'd
        end
        return c
    else
        --try to infer the type, and if successful build the constant
        local init,typ = a0,nil
        if type(init) == "cdata" then
            typ = terra.typeof(init)
        elseif type(init) == "number" then
            typ = (terra.isintegral(init) and terra.types.int) or terra.types.double
        elseif type(init) == "boolean" then
            typ = terra.types.bool
        elseif type(init) == "string" then
            typ = terra.types.rawstring
        else
            error("constant constructor requires explicit type for objects of type "..type(init))
        end
        return terra.constant(typ,init)
    end
end
_G["constant"] = terra.constant

function terra.typeof(obj)
    if type(obj) ~= "cdata" then
        error("cannot get the type of a non cdata object")
    end
    return terra.types.ctypetoterra[tonumber(ffi.typeof(obj))]
end

function terra.linklibrary(filename)
    terra.linklibraryimpl(filename,filename:match(".bc$"))
end

terra.languageextension = {
    tokentype = {}; --metatable for tokentype objects
    tokenkindtotoken = {}; --map from token's kind id (terra.kind.name), to the singleton table (terra.languageextension.name) 
}

function terra.importlanguage(languages,entrypoints,langstring)
    local lang = terra.require(langstring)
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
        if entrypoints[e] then
            error(("language '%s' uses entrypoint '%s' already defined by language '%s'"):format(lang.name,e,entrypoints[e].name),-1)
        end
        entrypoints[e] = lang
    end
    if not lang.keywordtable then
        lang.keywordtable = {} --keyword => true
        for i,k in ipairs(lang.keywords) do
            lang.keywordtable[k] = true
        end
        for i,k in ipairs(lang.entrypoints) do
            lang.keywordtable[k] = true
        end
    end
    table.insert(languages,lang)
end
function terra.unimportlanguages(languages,N,entrypoints)
    for i = 1,N do
        local lang = table.remove(languages)
        for i,e in ipairs(lang.entrypoints) do
            entrypoints[e] = nil
        end
    end
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
            local oldenv = getfenv(expr)
            setfenv(expr,env)
            local results = {expr()}
            setfenv(expr,oldenv)
            return unpack(results)
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

_G["operator"] = terra.internalmacro(function(diag,anchor,op,...)
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
    local opv = op:asvalue()
    opv = tbl[opv] or opv --operator can be __add or +
    local operands= terra.newlist()
    for i = 1,select("#",...) do
        operands:insert(select(i,...).tree)
    end
    return terra.newtree(anchor, { kind = terra.kinds.operator, operator = terra.kinds[opv], operands = operands })
end)
--called by tcompiler.cpp to convert userdata pointer to stacktrace function to the right type;
function terra.initdebugfns(traceback,backtrace,lookupsymbol,lookupline,disas)
    local P,FP = terra.types.pointer, terra.types.funcpointer
    local po = P(terra.types.opaque)
    local ppo = P(po)
    local p64 = P(terra.types.uint64)
    local ps = P(terra.types.rawstring) 
    terra.traceback = terra.cast(FP({po},{}),traceback)
    terra.backtrace = terra.cast(FP({ppo,terra.types.int,po,po},{terra.types.int}),backtrace)
    terra.lookupsymbol = terra.cast(FP({po,ppo,p64,ps,p64},{terra.types.bool}),lookupsymbol)
    terra.lookupline   = terra.cast(FP({po,po,ps,p64,p64},{terra.types.bool}),lookupline)
    terra.disas = terra.cast(FP({po,terra.types.uint64,terra.types.uint64},{}),disas)
end

_G["terralib"] = terra --terra code can't use "terra" because it is a keyword
--io.write("done\n")

--io.write("loading terra lib...")

local ffi = require("ffi")

local function dbprint(...) 
    if terra.isverbose then
        print(...)
    end
end
local function dbprintraw(obj)
    if terra.isverbose then
        obj:printraw()
    end
end

--debug wrapper around cdef function to print out all the things being defined
local oldcdef = ffi.cdef
ffi.cdef = function(...)
    dbprint(...)
    return oldcdef(...)
end

-- TREE
terra.tree = {} --metatype for trees
terra.tree.__index = terra.tree
function terra.tree:__tostring()
    return terra.kinds[self.kind].." <todo: retrieve from file>"
end
function terra.tree:is(value)
    return self.kind == terra.kinds[value]
end
 

function terra.tree:printraw()
    local function header(key,t)
        if type(t) == "table" and (getmetatable(t) == nil or type(getmetatable(t).__index) ~= "function") then
            return terra.kinds[t["kind"]] or ""
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
            elseif depth > 0 and (terra.isfunction(t) or terra.isfunctionvariant(t)) then
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
    for k,v in pairs(self) do
        if not new_tree[k] then
            new_tree[k] = v
        end
    end
    return setmetatable(new_tree,getmetatable(self))
end

function terra.treeload(ctx,self)
    if not self.expressionstring then
        error("tree was not an argument to a macro, I don't know what to do")
    else
        fn, err = loadstring("return " .. self.expressionstring)
        if err then
            local ln,err = terra.parseerror(self.linenumber,err)
            self.linenumber = ln
            terra.reporterror(ctx,self,err)
            return false
        else
            return true,fn
        end
    end
end

function terra.treeeval(ctx,t,fn)
    local env = ctx:combinedenv()
    setfenv(fn,env)
    local success,v = pcall(fn)
    if not success then --v contains the error message
        local ln,err = terra.parseerror(t.linenumber,v)
        local oldln = t.linenumber
        t.linenumber = ln
        terra.reporterror(ctx,t,err)
        t.linenumber = oldln
        return false
    end
    return true,v
end

function terra.newtree(ref,body)
    if not ref or not terra.istree(ref) then
        terra.tree.printraw(ref)
        print(debug.traceback())
        error("not a tree?",2)
    end
    body.offset = ref.offset
    body.linenumber = ref.linenumber
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
function terra.context:enterdef(luaenv)
    
    local definition = { 
        scopes = {}, --each time we enter a different quotation the scope changes
        symenv = {} --environment for dynamically created symbols, these have different scoping rules so they are stored in their own environment
    } 
    table.insert(self.definitions,definition)

    self:enterquote(luaenv,{})

end

function terra.context:definition()
    return self.definitions[#self.definitions]
end

function terra.context:scope()
    local defn = self:definition()
    return defn.scopes[#defn.scopes]
end

function terra.context:enterquote(luaenv,varenv)

    local combinedenv = { __index = function(_,idx) 
        return varenv[idx] or luaenv[idx] 
    end }
    setmetatable(combinedenv,combinedenv)

    local scope = {
        varenv = varenv,
        luaenv = luaenv,
        combinedenv = combinedenv
    }
    table.insert(self:definition().scopes,scope)
end

function terra.context:leavequote()
    table.remove(self:definition().scopes)
end

function terra.context:leavedef()
    table.remove(self.definitions)
end

function terra.context:enterblock()
    self:scope().varenv = setmetatable({},{ __index = self:varenv() })
    self:definition().symenv = setmetatable({},{ __index = self:symenv() })
end

function terra.context:leaveblock()
   self:scope().varenv = getmetatable(self:varenv()).__index
   self:definition().symenv = getmetatable(self:symenv()).__index
end


function terra.context:luaenv()
    return self:scope().luaenv
end
function terra.context:varenv()
    return self:scope().varenv
end
function terra.context:combinedenv()
    return self:scope().combinedenv
end
function terra.context:symenv()
    return self:definition().symenv
end

--terra.printlocation
--and terra.opensourcefile are inserted by C wrapper
function terra.context:printsource(anchor)
    local top = self.fileinfo[#self.fileinfo]
    if not top.filehandle then
        top.filehandle = terra.opensourcefile(top.filename)
    end
    if top.filehandle then --if the code did not come from a file then we don't print the carrot, since we cannot reopen the text
        terra.printlocation(top.filehandle,anchor.offset)
    end
end
function terra.context:reporterror(anchor,...)
    self.has_errors = true
    local top = self.fileinfo[#self.fileinfo]
    if not anchor then
        print(debug.traceback())
        error("nil anchor")
    end
    io.write(top.filename..":"..anchor.linenumber..": ")
    for _,v in ipairs({...}) do
        io.write(tostring(v))
    end
    io.write("\n")
    self:printsource(anchor)
end
function terra.context:enterfile(filename)
    table.insert(self.fileinfo,{ filename = filename })
end

function terra.context:leavefile(filename)
    local tbl = table.remove(self.fileinfo)
    if tbl.filehandle then
        terra.closesourcefile(tbl.filehandle)
        tbl.filehandle = nil
    end
end

function terra.context:isempty()
    return #self.definitions == 0
end


function terra.context:functionbegin(func)
    func.compileindex = self.nextindex
    func.lowlink = func.compileindex
    self.nextindex = self.nextindex + 1
    
    table.insert(self.functions,func)
    table.insert(self.tobecompiled,func)
    
end

function terra.context:functionend()
    local func = table.remove(self.functions)
    local prev = self.functions[#self.functions]
    if prev ~= nil then
        prev.lowlink = math.min(prev.lowlink,func.lowlink)
    end
    
    if func.lowlink == func.compileindex then
        local scc = terra.newlist{}
        repeat
            local tocompile = table.remove(self.tobecompiled)
            scc:insert(tocompile)
        until tocompile == func
        
        if not self.has_errors then
            terra.jit(scc)
        end
        
        for i,f in ipairs(scc) do
            if not self.has_errors then
                f:makewrapper()
            end
            f.state = "initialized"
        end
    end
    
end

function terra.context:functioncalls(func)
    local curfunc = self.functions[#self.functions]
    if curfunc then
        curfunc.lowlink = math.min(curfunc.lowlink,func.compileindex)
    end
end

function terra.newcontext()
    return setmetatable({definitions = {}, fileinfo = {}, functions = {}, tobecompiled = {}, nextindex = 0},terra.context)
end

-- END CONTEXT

-- FUNCVARIANT

-- a function variant is an implementation of a function for a particular set of arguments
-- functions themselves are overloadable. Each potential implementation is its own function variant
-- with its own compile state, type, AST, etc.
 
terra.funcvariant = {} --metatable for all function types
terra.funcvariant.__index = terra.funcvariant
function terra.funcvariant:env()
    self.envtbl = self.envtbl or self.envfunction() --evaluate the environment if needed
    self.envfunction = nil --we don't need the closure anymore
    return self.envtbl
end
function terra.funcvariant:peektype(ctx) --look at the type but don't compile the function (if possible)
                                         --this will return success, <type if success == true>
    if self.type then
        return true,self.type
    end
    
    if not self.untypedtree.return_types then
        return false
    end

    local params = terra.newlist()
    local function rt(t) return terra.resolvetype(ctx,t) end
    for _,v in ipairs(self.untypedtree.parameters) do
        params:insert(rt(v.type))
    end
    local rets = terra.resolvetype(ctx,self.untypedtree.return_types,true)
    self.type = terra.types.functype(params,rets) --for future calls
    return true, self.type
end
function terra.funcvariant:gettype(ctx)
    if self.state == "codegen" then --function is in the same strongly connected component of the call graph as its called, even though it has already been typechecked
        ctx:functioncalls(self)
        assert(self.type ~= nil, "no type in codegen'd function?")
        return self.type
    elseif self.state == "typecheck" then
        ctx:functioncalls(self)
        local success,typ = self:peektype(ctx) --we are already compiling this function, but if the return types are listed, we can resolve the type anyway 
        if success then
            return typ
        else
            return terra.types.error, "recursively called function needs an explicit return type"
        end
    else
        self:compile(ctx)
        return self.type
    end    
end
function terra.funcvariant:makewrapper()
    local fntyp = self.type
    
    local success,cfntyp,returnname = pcall(fntyp.cstring,fntyp)
    
    if not success then
        dbprint("cstring error: ",cfntyp)
        self.ffiwrapper = function()
            error("function not callable directly from lua")
        end
        return
    end
    
    self.ffireturnname = returnname
    self.ffiwrapper = ffi.cast(cfntyp,self.fptr)
    local passedaspointers = {}
    for i,p in ipairs(fntyp.parameters) do
        if p:ispassedaspointer() then
            passedaspointers[i] = p:cstring().."[1]"
            self.passedaspointers = passedaspointers --passedaspointers is only set if at least one of the arguments needs to be passed as a pointer
        end
    end
end

function terra.funcvariant:compile(ctx)
    
    if self.state == "initialized" then
        return
    end
    
    if self.state == "uninitializedc" then --this is a stub generated by the c wrapper, connect it with the right llvm_function object and set fptr
        terra.registercfunction(self)
        self:makewrapper()
        self.state = "initialized"
        return
    end
    
    if self.state ~= "uninitializedterra" then
        error("attempting to compile a function that is already in the process of being compiled.",2)
    end
    
    local ctx = ctx or terra.newcontext() -- if this is a top level compile, create a new compilation context
    
    dbprint("compiling function:")
    dbprintraw(self.untypedtree)
    dbprint("with local environment:")
    for k,v in pairs(self:env()) do
        dbprint("  ",k)
    end
    
    ctx:functionbegin(self)
    self.state = "typecheck"
    self.typedtree = self:typecheck(ctx)
    self.type = self.typedtree.type
    
    self.state = "codegen"
    
    if ctx.has_errors then 
        if ctx:isempty() then --if this was not the top level compile we let type-checking of other functions continue, 
                                --though we don't actually compile because of the errors
            error("Errors reported during compilation.")
        end
    else
        terra.codegen(self)
    end
    
    ctx:functionend(self)
    
end

function terra.funcvariant:__call(...)
    self:compile()
    
    if not self.type.issret and not self.passedaspointers then --fast path
        return self.ffiwrapper(...)
    else
    
        local params = {...}
        if self.passedaspointers then
            for idx,allocname in pairs(self.passedaspointers) do
                local a  = ffi.new(allocname) --create a copy of the C object and initialize it with the parameter
                a[0] = params[idx]
                params[idx] = a --replace the original parameter with the pointer
                
            end
        end
        
        if self.type.issret then
            local nr = #self.type.returns
            local result = ffi.new(self.ffireturnname)
            self.ffiwrapper(result,unpack(params))
            local rv = result[0]
            local rs = {}
            for i = 1,nr do
                table.insert(rs,rv["v"..i])
            end
            return unpack(rs)
        else
            return self.ffiwrapper(unpack(params))
        end
    end
end


function terra.isfunctionvariant(obj)
    return getmetatable(obj) == terra.funcvariant
end

--END FUNCVARIANT

-- FUNCTION
-- a function is a list of possible function variants that can be invoked
-- it is implemented this way to support function overloading, where the same symbol
-- may have different variants

terra.func = {} --metatable for all function types
terra.func.__index = terra.func

function terra.func:compile(ctx)
    for i,v in ipairs(self.variants) do
        v:compile(ctx)
    end
end

function terra.func:__call(...)
    self:compile()
    if #self.variants == 1 then --fast path for the non-overloaded case
        return self.variants[1](...)
    end
    
    local results
    for i,v in ipairs(self.variants) do
        --TODO: this is very inefficient, we should have a routine which
        --figures out which function to call based on argument types
        results = {pcall(v.__call,v,...)}
        if results[1] == true then
            table.remove(results,1)
            return unpack(results)
        end
    end
    --none of the variants worked, remove the final error
    error(results[2])
end

function terra.func:addvariant(v)
    self.variants:insert(v)
end

function terra.func:getvariants()
    return self.variants
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

function terra.globalvar:compile(ctx)

    local ctx = ctx or terra.newcontext()
    local globalinit = self.initializer --this initializer may initialize more than 1 variable, all of them are handled here
    
    globalinit.initfn:compile(ctx)
    
    local entries = globalinit.initfn.typedtree.body.statements[1].variables --extract definitions from generated function
    for i,v in ipairs(globalinit.globals) do
        v.tree = entries[i]
        v.type = v.tree.type
    end
    --this will happen when function referring to this GV is in the same strongly connected component as the global variables initializer
    if globalinit.initfn.state ~= "initialized" then 
        local tree = globalinit.initfn.untypedtree
        ctx:enterfile(tree.filename)
        ctx:reporterror(tree,"global variable recursively used by its own initializer")
        ctx:leavefile()
    end
    
    if not ctx.has_errors then
        globalinit.initfn()
    end
end

function terra.globalvar:gettype(ctx) 
    local state = self.initializer.initfn.state
    if state == "initialized" then
        return self.type
    elseif state == "uninitializedterra" then
        self:compile(ctx)
        assert(self.type ~= nil, "nil type?")
        return self.type
    else
        return terra.types.error, "reference to global variable in its own initializer"
    end
end

-- END GLOBALVAR

-- MACRO

terra.macro = {}
terra.macro.__index = terra.macro
terra.macro.__call = function(self,...)
    return self.fn(...)
end

function terra.ismacro(t)
    return getmetatable(t) == terra.macro
end

function terra.createmacro(fn)
    return setmetatable({fn = fn}, terra.macro)
end
_G["macro"] = terra.createmacro --introduce macro intrinsic into global namespace

-- END MACRO

-- QUOTE
terra.quote = {}
terra.quote.__index = terra.quote
function terra.isquote(t)
    return getmetatable(t) == terra.quote
end

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

function terra.quote:astype(ctx)
    local success,fn = terra.treeload(ctx,self.tree)
    
    if not success then
        return terra.types.error
    else
        local typtree = terra.newtree(self.tree, { kind = terra.kinds.luaexpression, expression = fn })
        return terra.resolvetype(ctx,typtree)
    end
end

function terra.quote:asvalue(ctx)
    local success,fn = terra.treeload(ctx,self.tree)
    if not success then
        return nil
    else
        local success,v = terra.treeeval(ctx,self.tree,fn)
        if not success then
            return nil
        else
            return v
        end
    end
end

function terra.quote:env()
    if not self.luaenv then
        self.luaenv = self.luaenvfunction()
        self.luaenvfunction = nil
    end
    return self.luaenv,self.varenv
end

-- END QUOTE

-- SYMBOL
terra.symbol = {}
terra.symbol.__index = terra.symbol
function terra.issymbol(s)
    return getmetatable(s) == terra.symbol
end
terra.symbol.count = 0

function terra.newsymbol(typ)
    if typ and not terra.types.istype(typ) then
        error("argument is not a type")
    end
    local self = setmetatable({
        id = terra.symbol.count,
        type = typ
    },terra.symbol)
    terra.symbol.count = terra.symbol.count + 1
    return self
end

function terra.symbol:__tostring()
    return "symbol ("..(self.displayname or tostring(self.id))..")"
end

_G["symbol"] = terra.newsymbol 

-- CONSTRUCTORS
do  --constructor functions for terra functions and variables
    local name_count = 0
    local function manglename(nm)
        local fixed = nm:gsub("[^A-Za-z0-9]","_") .. name_count --todo if a user writes terra foo, pass in the string "foo"
        name_count = name_count + 1
        return fixed
    end
    function terra.newfunctionvariant(newtree,name,env,reciever)
        local rawname = (name or newtree.filename.."_"..newtree.linenumber.."_")
        local fname = manglename(rawname)
        local obj = { untypedtree = newtree, filename = newtree.filename, envfunction = env, name = fname, state = "uninitializedterra" }
        local fn = setmetatable(obj,terra.funcvariant)
        
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
        
        return fn
    end
    
    local function mkfunction()
        return setmetatable({variants = terra.newlist()},terra.func)
    end
    
    function terra.newfunction(olddef,newtree,name,env,reciever)
        if not olddef then
            olddef = mkfunction()
        end
        
        olddef:addvariant(terra.newfunctionvariant(newtree,name,env,reciever))
        
        return olddef
    end
    
    function terra.newcfunction(name,typ)
        local obj = { name = name, type = typ, state = "uninitializedc" }
        setmetatable(obj,terra.funcvariant)
        
        local fn = mkfunction()
        fn:addvariant(obj)
        
        return fn
    end
    
    function terra.newvariables(tree,env)
        local globals = terra.newlist()
        local varentries = terra.newlist()
        
        local globalinit = {} --table to hold initialization information for this group of variables
        
        for i,v in ipairs(tree.variables) do
            local function nm(t) 
                if t.kind == terra.kinds.var then
                    return t.name
                elseif t.kind == terra.kinds.selectconst then
                    return nm(t.value) .. "_" .. t.field
                else
                    error("not a variable name?")
                end
            end
            local n = nm(v.name) .. "_" .. name_count
            name_count = name_count + 1
            local sym = terra.newtree(v, {kind = terra.kinds.symbol, name = n})
            local varentry = terra.newtree(v, { kind = terra.kinds.entry, name = sym, type = v.type })
            varentries:insert(varentry)
            
            local gv = setmetatable({initializer = globalinit},terra.globalvar)
            globals:insert(gv)
        end
        
        local anchor = tree.variables[1]
        local dv = terra.newtree(anchor, { kind = terra.kinds.defvar, variables = varentries, initializers = tree.initializers, isglobal = true})
        local body = terra.newtree(anchor, { kind = terra.kinds.block, statements = terra.newlist {dv} })
        local ftree = terra.newtree(anchor, { kind = terra.kinds["function"], parameters = terra.newlist(),
                                              is_varargs = false, filename = tree.filename, body = body})
        
        globalinit.initfn = terra.newfunctionvariant(ftree,nil,env)
        globalinit.globals = globals

        return unpack(globals)
    end
    
    local function newstructwithlayout(name,tree,env)
        local function buildstruct(typ,ctx)
            ctx:enterfile(tree.filename)
            ctx:enterdef(env())
            
            local function addstructentry(v)
                local resolvedtype = terra.resolvetype(ctx,v.type)
                if not typ:addentry(v.key,resolvedtype) then
                    terra.reporterror(ctx,v,"duplicate definition of field ",v.key)
                end
            end
            local function addrecords(records)
                for i,v in ipairs(records) do
                    if v.kind == terra.kinds["union"] then
                        typ:beginunion()
                        addrecords(v.records)
                        typ:endunion()
                    else
                        addstructentry(v)
                    end
                end
            end
            addrecords(tree.records)
            ctx:leavedef()
            ctx:leavefile()
        end
        
        local st = terra.types.newstruct(name)
        st.tree = tree --for debugging purposes, we keep the tree to improve error reporting
        st:addlayoutfunction(buildstruct)
        return st 
    end
    
    function terra.namedstruct(tree,name,env)
        return newstructwithlayout(name,tree,env)
    end
    
    function terra.anonstruct(tree,env)
       local st = newstructwithlayout("anon",tree,env)
        st:setconvertible(true)
        return st
    end
    
    function terra.newquote(tree,variant,luaenvorfn,varenv) -- kind == "exp" or "stmt"
        local obj = { tree = tree, variant = variant, varenv = varenv or {}}
        if type(luaenvorfn) == "function" then
            obj.luaenvfunction = luaenvorfn
        else
            obj.luaenv = luaenvorfn
        end
        setmetatable(obj,terra.quote)
        return obj
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
    function types.type:ispassedaspointer() --warning: if you update this, you also need to update the behavior in tcompiler.cpp's getType function to set the ispassedaspointer flag
        return self:isstruct() or self:isarray()
    end
    
    function types.type:iscanonical()
        return not self:isstruct() or not self.incomplete
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
        local r = base.."_"
        if name then
            r = r..name.."_"
        end
        r = r..next_type_id
        next_type_id = next_type_id + 1
        return r
    end
    
    function types.type:cstring()
        if not self.cachedcstring then
            
            local function definetype(base,name,value)
                local nm = uniquetypename(base,name)
                ffi.cdef("typedef "..value.." "..nm..";")
                return nm
            end
            
            --assumption: cachedcstring needs to be an identifier, it cannot be a derived type (e.g. int*)
            --this makes it possible to predict the syntax of subsequent typedef operations
            if self:isintegral() then
                self.cachedcstring = tostring(self).."_t"
            elseif self:isfloat() then
                self.cachedcstring = tostring(self)
            elseif self:ispointer() and self.type:isfunction() then --function pointers and functions have the same typedef
                self.cachedcstring = self.type:cstring()
            elseif self:ispointer() then
                local value = self.type:cstring()
                if not self.cachedcstring then --if this type was recursive then it might have created the value already   
                    self.cachedcstring = definetype(value,"ptr",value .. "*")
                end
            elseif self:islogical() then
                self.cachedcstring = "unsigned char"
            elseif self:isstruct() then
                local nm = uniquetypename(self.name)
                ffi.cdef("typedef struct "..nm.." "..nm..";") --first make a typedef to the opaque pointer
                self.cachedcstring = nm -- prevent recursive structs from re-entering this function by having them return the name
                local str = "struct "..nm.." { "
                for i,v in ipairs(self.entries) do
                
                    local prevalloc = self.entries[i-1] and self.entries[i-1].allocation
                    local nextalloc = self.entries[i+1] and self.entries[i+1].allocation
            
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
            elseif self:isarray() then
                local value = self.type:cstring()
                if not self.cachedcstring then
                    local nm = uniquetypename(value,"arr")
                    ffi.cdef("typedef "..value.." "..nm.."["..tostring(self.N).."];")
                    self.cachedcstring = nm
                end
            elseif self:isfunction() then
                local rt
                local rname
                if #self.returns == 0 then
                    rt = "void"
                elseif not self.issret then
                    rt = self.returns[1]:cstring()
                else
                    local rtype = "typedef struct { "
                    for i,v in ipairs(self.returns) do
                        rtype = rtype..v:cstring().." v"..tostring(i).."; "
                    end
                    rname = uniquetypename("return")
                    self.cachedreturnname = rname.."[1]"
                    rtype = rtype .. " } "..rname..";"
                    ffi.cdef(rtype)
                    rt = "void"
                end
                local function getcstring(t)
                    if t:ispassedaspointer() then
                        return types.pointer(t):cstring()
                    else
                        return t:cstring()
                    end
                end
                
                local pa = self.parameters:map(getcstring)
                
                if self.issret then
                    pa:insert(1,rname .. "*")
                end
                
                pa = pa:mkstring("(",",",")")
                local ntyp = uniquetypename("function")
                local cdef = "typedef "..rt.." (*"..ntyp..")"..pa..";"
                ffi.cdef(cdef)
                self.cachedcstring = ntyp
            elseif self == types.niltype then
                local nilname = uniquetypename("niltype")
                ffi.cdef("typedef void * "..nilname..";")
                self.cachedcstring = nilname
            elseif self == types.error then
                self.cachedcstring = "int"
            else
                error("NYI - cstring")
            end    
        end
        if not self.cachedcstring then error("cstring not set? "..tostring(self)) end
        
        return self.cachedcstring,self.cachedreturnname --cachedreturnname is only set for sret functions where we need to know the name of the struct to allocate to hold the return value
    end
    
    function types.type:getcanonical(ctx) --overriden by named structs to build their member tables and by proxy types to lazily evaluate their type
        if self:isvector() or self:ispointer() or self:isarray() then
            self.type:getcanonical(ctx)
        elseif self:isfunction() then
            self.parameters:map(function(e) e:getcanonical(ctx) end)
            self.returns   :map(function(e) e:getcanonical(ctx) end)
        end
        return self
    end
    
    types.type.methods = {} --metatable of all types
    types.type.methods.as = macro(function(ctx,tree,exp,typ)
        return terra.newtree(tree,{ kind = terra.kinds.explicitcast, totype = typ:astype(ctx), value = exp.tree })
    end)    
    function types.istype(t)
        return getmetatable(t) == types.type
    end
    
    --map from unique type identifier string to the metadata for the type
    types.table = {}
    
    
    local function mktyp(v)
        v.methods = setmetatable({},{ __index = types.type.methods }) --create new blank method table
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
            registertype(name,
                         mktyp { kind = terra.kinds.primitive, bytes = size, type = terra.kinds.integer, signed = s})
        end
    end  
    
    registertype("float", mktyp { kind = terra.kinds.primitive, bytes = 4, type = terra.kinds.float })
    registertype("double",mktyp { kind = terra.kinds.primitive, bytes = 8, type = terra.kinds.float })
    registertype("bool",  mktyp { kind = terra.kinds.primitive, bytes = 1, type = terra.kinds.logical})
    
    types.error   = registertype("error",  mktyp { kind = terra.kinds.error })
    types.niltype = registertype("niltype",mktyp { kind = terra.kinds.niltype}) -- the type of the singleton nil (implicitly convertable to any pointer type)
    
    local function checkistype(typ)
        if not types.istype(typ) then 
            print(debug.traceback())
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
            return mktyp { kind = terra.kinds.array, type = typ, N = N }
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
    
    function types.newstruct(displayname)
        
        local name = getuniquestructname(displayname)
                
        local tbl = mktyp { kind = terra.kinds["struct"],
                            name = name, 
                            displayname = displayname, 
                            entries = terra.newlist(), 
                            keytoindex = {}, 
                            nextunnamed = 0, 
                            nextallocation = 0,
                            layoutfunctions = terra.newlist(),
                            incomplete = true                            
                          }
                            
        function tbl:addentry(k,t)
            assert(self.incomplete)
            local entry = { type = t, key = k, hasname = true, allocation = self.nextallocation, inunion = self.inunion ~= nil }
            if not k then
                entry.hasname = false
                entry.key = "_"..tostring(self.nextunnamed)
                self.nextunnamed = self.nextunnamed + 1
            end
            
            local notduplicate = self.keytoindex[entry.key] == nil          
            self.keytoindex[entry.key] = #self.entries
            self.entries:insert(entry)
            
            if self.inunion then
                self.unionisnonempty = true
            else
                self.nextallocation = self.nextallocation + 1
            end
            
            return notduplicate
        end
        function tbl:beginunion()
            assert(self.incomplete)
            if not self.inunion then
                self.inunion = 0
            end
            self.inunion = self.inunion + 1
        end
        function tbl:endunion()
            assert(self.incomplete)
            self.inunion = self.inunion - 1
            if self.inunion == 0 then
                self.inunion = nil
                if self.unionisnonempty then
                    self.nextallocation = self.nextallocation + 1
                end
                self.unionisnonempty = nil
            end
        end
        
        
        function tbl:getcanonical(ctx)
        
            assert(self.incomplete)
            
            self.getcanonical = nil -- if we recursively try to evaluate this type then just return it
            
            for i,layoutfn in ipairs(self.layoutfunctions) do
                layoutfn(self,ctx)
            end
            
            self.incomplete = nil
            
            local function checkrecursion(t)
                if t == self then
                    if self.tree then
                        ctx:enterfile(self.tree.filename)
                        terra.reporterror(ctx,self.tree,"type recursively contains itself")
                        ctx:leavefile()
                    else
                        --TODO: emit where the user-defined type was first used
                        error("programmatically defined type contains itself")
                    end
                elseif t:isstruct() then
                    for i,v in ipairs(t.entries) do
                        checkrecursion(v.type)
                    end
                elseif t:isarray() or t:isvector() then
                    checkrecursion(t.type)
                end
            end
            for i,v in ipairs(self.entries) do
                checkrecursion(v.type)
            end
            
            dbprint("Resolved Named Struct To:")
            dbprintraw(self)
            return self
        
        end
        
        function tbl:addlayoutfunction(fn)
            assert(self.incomplete)
            self.layoutfunctions:insert(fn)
        end
        
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
        
        function checkalltypes(l)
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
            local issret = #returns > 1 or (#returns == 1 and returns[1]:ispassedaspointer())
            return mktyp { kind = terra.kinds.functype, parameters = parameters, returns = returns, isvararg = isvararg, issret = issret }
        end)
    end
    --a function type that represents lua functions in the type checker
    types.luafunction = registertype("luafunction",
                          mktyp { 
                            kind = terra.kinds.functype, 
                            islua = true,
                            parameters = terra.newlist(), 
                            returns = terra.newlist(), 
                            isvararg = true, 
                            issret = false
                          })
    
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


-- TYPECHECKER
function terra.reporterror(ctx,anchor,...)
    ctx:reporterror(anchor,...)
    return terra.types.error
end

function terra.parseerror(startline, errmsg)
    local line,err = errmsg:match(":([0-9]+):(.*)")
    return startline + tonumber(line) - 1, err
end

function terra.resolveluaexpression(ctx,e)
    if not terra.istree(e) or not e:is "luaexpression" then
        print(debug.traceback())
        e:printraw()
        error("not a lua expression?")
    end
    return terra.treeeval(ctx,e,e.expression)
end

function terra.resolvetype(ctx,t,returnlist)
    local function wrap(r)
        if returnlist then
            return terra.newlist {r}
        else
            return r
        end
    end
    if terra.types.istype(t) then --if the AST contains a direct reference to a type, then accept that, otherwise try to evaluate the type
        return wrap(t:getcanonical(ctx))
    end
        
    local success,typ = terra.resolveluaexpression(ctx,t)
    
    if not success then
        return wrap(terra.types.error)
    end
    
    if terra.types.istype(typ) then
        return wrap(typ:getcanonical(ctx))
    elseif returnlist and type(typ) == "table" then
        local rl = terra.newlist()
        for i,v in ipairs(typ) do
            if terra.types.istype(v) then
                rl:insert(v:getcanonical(ctx))
            else
                terra.reporterror(ctx,t,"expected a type but found ", type(v))
                rl:insert(terra.types.error)
            end
        end
        return rl
    else
        terra.reporterror(ctx,t,"expected a type but found ", type(typ))
        return wrap(terra.types.error)
    end
end
local function map(lst,fn)
    r = {}
    for i,v in ipairs(lst) do
        r[i] = fn(v)
    end
    return r
end
--[[
statements:

"assignment" (need convertible to, l-exp tracking)
"goto" (done)
"break" (done)
"label" (done)
"while" (done)
"repeat" (done)
"fornum" (need is numeric)
"forlist" (need to figure out how iterators will work...)
"block" (done)
"if" (done)
"defvar" (done - except for multi-return and that checkexp doesn't consider coersions yet)
"return" (done - except for final check)

expressions:
"var" (done)
"select" (done - except struct extract)
"literal" (done)
"constructor"
"index"
"method"
"apply"
"operator" (done - except pointer operators)


other:
"recfield"
"listfield"
"function"
"ifbranch" (done)

]]


function terra.funcvariant:typecheck(ctx)
    
    
    --initialization
    ctx:enterfile(self.filename)
    ctx:enterdef(self:env())
    
    
    local ftree = self.untypedtree
    
    
    --wrapper for resolve type, if returnlist is true then resolvetype will return a list of types (e.g. the return value of a function)
    local function resolvetype(t,returnlist)
        return terra.resolvetype(ctx,t,returnlist)
    end
    
    
    -- TYPECHECKING FUNCTION DECLARATIONS
    --declarations of local functions used in type checking
    local insertcast,structcast, insertvar, insertselect,asrvalue,aslvalue,
          checkexp,checkstmt, checkrvalue,resolvequote,
          checkparameterlist, checkcall,checkmethodorcall, createspecial, resolveluaspecial,
          insertdereference, insertuntypeddereference, insertaddressof
          
          
    --cast  handlint functions
    --insertcast handles implicitly allowed casts
    --insertexplicitcast handles casts performed using the :as method
    --structcast handles casting from an anonymous structure type to another struct type
    
    function structcast(cast,exp,typ, speculative) --if speculative is true, then errors will not be reported (caller must check)
        local from = exp.type
        local to = typ
        
    
        local valid = true
        local function err(...)
            valid = false
            if not speculative then
                terra.reporterror(ctx,exp,...)
            end
        end
        
        cast.structvariable = terra.newtree(exp, { kind = terra.kinds.entry, name = "<structcast>", type = from })
        local var_ref = insertvar(exp,from,cast.structvariable.name,cast.structvariable)
        
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
    
    local function createcast(exp,typ)
        return terra.newtree(exp, { kind = terra.kinds.cast, from = exp.type, to = typ, type = typ, expression = exp })
    end
    
    local function createtypedexpression(exp)
        assert(exp.type)
        return terra.newtree(exp, { kind = terra.kinds.typedexpression, exp = exp})
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
                if typ:isstruct() and typ.methods.__cast then
                    cast_fns:insert(typ.methods.__cast)
                elseif typ:ispointertostruct() then
                    addcasts(typ.type)
                end
            end
            addcasts(exp.type)
            addcasts(typ)

            for i,__cast in ipairs(cast_fns) do
                local quotedexp = terra.newquote(createtypedexpression(exp),"exp",ctx:luaenv(),ctx:varenv())
                local valid,result = __cast(ctx,exp,exp.type,typ,quotedexp)
                if valid then
                    return checkrvalue(createspecial(exp,result))
                end
            end

            if not speculative then
                terra.reporterror(ctx,exp,"invalid conversion from ",exp.type," to ",typ)
            end
            return cast_exp, false
        end
    end
    local function insertexplicitcast(exp,typ) --all implicit casts are allowed plus some additional casts like from int to pointer, pointer to int, and int to int
        if typ == exp.type then
            return exp
        elseif typ:ispointer() and exp.type:ispointer() then
            return createcast(exp,typ)
        elseif typ:ispointer() and exp.type:isintegral() then --int to pointer
            return createcast(exp,typ)
        elseif typ:isintegral() and exp.type:ispointer() then
            if typ.bytes < intptr.bytes then
                terra.reporterror(ctx,exp,"pointer to ",typ," conversion loses precision")
            end
            return createcast(exp,typ)
        elseif typ:isprimitive() and exp.type:isprimitive() then --explicit conversions from logicals to other primitives are allowed
            return createcast(exp,typ)
        else
            return insertcast(exp,typ) --otherwise, allow any implicit casts
        end
    end
    
    local function insertrecievercast(exp,typ,speculative) --casts allow for method recievers a:b(c,d) ==> b(a,c,d), but 'a' has additional allowed implicit casting rules
                                                           --type can also be == "vararg" if the expected type of the reciever was an argument to the varargs of a function (this often happens when it is a lua function
         if typ == "vararg" then
             return insertaddressof(exp), true
         elseif typ:ispointer() and not exp.type:ispointer() then
             --implicit address of allowed for recievers
             return insertcast(insertaddressof(exp),typ,speculate)
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
    --functions to calculate what happens when two types are input to a binary method
    
    local function typemeet(op,a,b)
        local function err()
            terra.reporterror(ctx,op,"incompatible types: ",a," and ",b)
        end
        if a == terra.types.error or b == terra.types.error then
            return terra.types.error
        elseif a == b then
            return a
        elseif a.kind == terra.kinds.primitive and b.kind == terra.kinds.primitive then
            if a:isintegral() and b:isintegral() then
                if a.bytes < b.bytes then
                    return b
                elseif b.bytes > a.bytes then
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

    local function createformalparameterlist(paramlist)
        local result = terra.newlist()
        for i,p in ipairs(paramlist) do
            if i ~= #paramlist or p.type or p.name.name then
                local entry = p:copy{ type = p.type and resolvetype(p.type), 
                                      name = checksymbol(p.name,true)}
                result:insert(entry)
            else
                assert(p.name.expression)
                local success, value = terra.resolveluaexpression(ctx,p.name.expression)
                if success then
                    local symlist = (terra.israwlist(value) and value) or terra.newlist{ value }
                    for i,sym in ipairs(symlist) do
                        if terra.issymbol(sym) then
                            result:insert(p:copy { name = sym })
                        else
                            terra.reporterror(ctx,p,"expected a symbol but found ",type(sym))
                        end
                    end
                end
            end
        end
        for i,entry in ipairs(result) do
            if terra.issymbol(entry.name) and not entry.type then --if the symbol was given a type but the parameter didn't have one
                                                                  --it takes the type of the symbol
                entry.type = entry.name.type and entry.name.type:getcanonical(ctx)
            end
        end
        return result
    end

    local function checkunary(ee,operands,property)
        local e = operands[1]
        if e.type ~= terra.types.error and not e.type[property](e.type) then
            terra.reporterror(ctx,e,"argument of unary operator is not valid type but ",e.type)
            return e:copy { type = terra.types.error }
        end
        return ee:copy { type = e.type, operands = terra.newlist{e} }
    end 
    
    
    local function meetbinary(e,property,lhs,rhs)
        local t,l,r = typematch(e,lhs,rhs)
        if t ~= terra.types.error and not t[property](t) then
            terra.reporterror(ctx,e,"arguments of binary operator are not valid type but ",t)
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
        local function aspointer(exp) --convert pointer like things into pointers
            return (insertcast(exp,terra.types.pointer(exp.type.type)))
        end
        -- subtracting 2 pointers
        if  pointerlike(l.type) and pointerlike(r.type) and l.type.type == r.type.type and e.operator == terra.kinds["-"] then
            return e:copy { type = ptrdiff, operands = terra.newlist {aspointer(l),aspointer(r)} }
        elseif pointerlike(l.type) and r.type:isintegral() then -- adding or subtracting a int to a pointer 
            return e:copy { type = terra.types.pointer(l.type.type), operands = terra.newlist {aspointer(l),r} }
        elseif l.type:isintegral() and pointerlike(r.type) then
            return e:copy { type = terra.types.pointer(r.type.type), operands = terra.newlist {aspointer(r),l} }
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
    
    local function checklvalue(ee)
        local e = checkexp(ee)
        if not e.lvalue then
            terra.reporterror(ctx,e,"argument to operator must be an lvalue")
            e.type = terra.types.error
        end
        return e
    end
        
    function insertaddressof(ee)
        local e = aslvalue(ee)
        local ret = terra.newtree(e,{ kind = terra.kinds.operator, type = terra.types.pointer(ee.type), operator = terra.kinds["&"], operands = terra.newlist{e} })
        return ret
    end
    
    function insertdereference(ee)
        local e = asrvalue(ee)
        local ret = terra.newtree(e,{ kind = terra.kinds.operator, operator = terra.kinds["@"], operands = terra.newlist{e}, lvalue = true })
        if not e.type:ispointer() then
            terra.reporterror(ctx,e,"argument of dereference is not a pointer type but ",e.type)
            ret.type = terra.types.error 
        elseif e.type.type:isfunction() then
            --function pointer dereference does nothing, return the input
            return e
        else
            ret.type = e.type.type
        end
        return ret
    end
    
    function insertuntypeddereference(obj)
        return terra.newtree(obj,{ kind = terra.kinds.operator, operator = terra.kinds["@"], operands = terra.newlist{obj}})
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
                terra.reporterror(ctx,ee,"arguments to shift must be integers but found ",a.type," and ", b.type)
            end
        end
        
        return ee:copy { type = typ, operands = terra.newlist{a,b} }
    end
    
    function checkifelse(ee,operands)
        local cond = operands[1]
        local t,l,r = typematch(ee,operands[2],operands[3])
        if cond.type ~= terra.types.error and t ~= terra.types.error then
            if cond.type:isvector() and cond.type.type == bool then
                if not t:isvector() or t.N ~= cond.type.N then
                    print(ee)
                    terra.reporterror(ctx,ee,"conditional in select is not the same shape as ",cond.type)
                end
            elseif cond.type ~= bool then
                print(ee)
                terra.reporterror(ctx,ee,"expected a boolean or vector of booleans but found ",cond.type)   
            end
        end
        return ee:copy { type = t, operands = terra.newlist{cond,l,r}}
    end

    local operator_table = {
        ["-"] = { checkarithpointer, "__sub" };
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
            return false, insertdereference(e)
        elseif op_string == "&" then
            local e = checklvalue(ee.operands[1])
            local ty = terra.types.pointer(e.type)
            return false, ee:copy { type = ty, operands = terra.newlist{e} }
        end
        
        local op, overloadmethod = unpack(operator_table[op_string] or {})
        if op == nil then
            terra.reporterror(ctx,ee,"operator ",op_string," not defined in terra code.")
            return false, ee:copy { type = terra.types.error }
        end
        local operands = ee.operands:map(checkrvalue)
        
        local overload = nil
        for i,e in ipairs(operands) do
            if e.type:isstruct() then
                overload = e.type.methods[overloadmethod] --TODO: be more intelligent here about merging overloaded functions so that all possibilities are considered
                if overload then
                    break
                end
            end
        end
        
        if overload then
            return checkcall(ee,createspecial(ee,overload),operands:map(createtypedexpression),ee.operands,"all",true)
        else
            return false, op(ee,operands)
        end
    end
    
    local function createextractreturn(fncall, index, t)
        fncall.result = fncall.result or {} --create a new result table (if there is not already one), to link this extract with the function call
        return terra.newtree(fncall,{ kind = terra.kinds.extractreturn, index = index, result = fncall.result, type = t})
    end
    local function iscall(t)
        return t.kind == terra.kinds.apply or t.kind == terra.kinds.method
    end
    local function canreturnmultiple(t)
        return iscall(t) or t.kind == terra.kinds.var or t.kind == terra.kinds.select
    end

    function checksymbol(sym,requiresymbol)
        if sym.name then
            return sym.name
        else
            local success, value = terra.resolveluaexpression(ctx,sym.expression)
            if not success then 
                return "<error>"
            end
            if type(value) ~= "string" and not terra.issymbol(value) then
                terra.reporterror(ctx,sym,"expected a string or symbol but found ",type(value))
                return "<error>"
            end
            if requiresymbol and type(value) == "string" then
               terra.reporterror(ctx,sym,"expected a symbol but found string") 
            end
            return value
        end
    end

    function checkparameterlist(anchor,params) --individual params may be already typechecked (e.g. if they were a method call receiver) 
                                               --in this case they are treated as single expressions
        local exps = terra.newlist()
        local multiret = nil
        
        local minsize = #params --minsize is either the number of explicitly listed parameters (a,b,c) minsize == 3
                                --or 1 less than this number if 'c' is a macro/quotelist that has 0 elements

        local addelement, addelements
        function addelements(elems,depth)
            if #elems == 0 and depth == 1 then
                minsize = minsize - 1
            end
            for i,v in ipairs(elems) do
                addelement(v, depth + 1, i == #elems)
            end
        end
        function addelement(elem,depth,islast)
            if not islast or elem.truncated then
                exps:insert(checkrvalue(elem))
            else
                elem = resolveluaspecial(elem)
                if iscall(elem) then
                    local ismacro, multifunc = checkmethodorcall(elem,false)
                    if ismacro then --call was a macro, handle the results as if they were in the list
                        addelement(multifunc, depth, islast) --multiple returns, are added to the list, like function calls these are optional                        
                    else
                        if #multifunc.types == 1 then
                            exps:insert(multifunc) --just insert it as a normal single-return function
                        else --remember the multireturn function and insert extract nodes into the expression list
                            multiret = multifunc
                            if #multifunc.types == 0 and depth == 1 then
                                minsize = minsize - 1
                            end
                            for i,t in ipairs(multifunc.types) do
                                exps:insert(createextractreturn(multiret, i - 1, t))
                            end
                        end
                    end
                elseif elem:is "quote" then
                    resolvequote(elem,elem.quote,"exp",function(tree)
                        addelement(tree,depth,islast)
                    end)
                elseif elem:is "speciallist" then
                    addelements(elem.values, depth)
                else
                    exps:insert(checkrvalue(elem))
                end
            end
        end

        addelements(params,0)
        
        local maxsize = #exps
        return terra.newtree(anchor, { kind = terra.kinds.parameterlist, parameters = exps, minsize = minsize, maxsize = maxsize, call = multiret })
    end
    
    local function tryinsertcasts(typelists,paramlist)
        
        local function trylist(typelist, speculate)
            local allvalid = true
            if #typelist > paramlist.maxsize then
                allvalid = false
                if not speculate then
                    terra.reporterror(ctx,paramlist,"expected at least "..#typelist.." parameters, but found only "..paramlist.maxsize)
                end
            elseif #typelist < paramlist.minsize then
                allvalid = false
                if not speculate then
                    terra.reporterror(ctx,paramlist,"expected no more than "..#typelist.." parameters, but found at least "..paramlist.minsize)
                end
            end
            
            local results = terra.newlist{}
            
            for i,param in ipairs(paramlist.parameters) do
                local typ = typelist[i]
                
                local result,valid
                if typ == nil or typ == "passthrough" then
                    result,valid = param,true 
                elseif paramlist.recievers == "all" or (i == 1 and paramlist.recievers == "first") then
                    result,valid = insertrecievercast(param,typ,speculate)
                elseif typ == "vararg" then
                    result,valid = param,true
                else
                    result,valid = insertcast(param,typ,speculate)
                end
                results[i] = result
                allvalid = allvalid and valid
            end
            
            return results,allvalid
            
        end
        
        if #typelists == 1 then
            local typelist = typelists[1]    
            local results,allvalid = trylist(typelist,false)
            assert(#results == paramlist.maxsize)
            paramlist.parameters = results
            paramlist.size = #typelist
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
                    else
                        local optiona = typelists[valididx]:mkstring("(",",",")")
                        local optionb = typelist:mkstring("(",",",")")
                        terra.reporterror(ctx,paramlist,"call to overloaded function is ambiguous. can apply to both ", optiona, " and ", optionb)
                        break
                    end
                end
            end
            
            if valididx then
               paramlist.parameters = validcasts
               paramlist.size = #typelists[valididx]
            else
                --no options were valid, lets emit some errors
                terra.reporterror(ctx,paramlist,"call to overloaded function does not apply to any arguments")
                for i,typelist in ipairs(typelists) do
                    terra.reporterror(ctx,paramlist,"option ",i," with type ",typelist:mkstring("(",",",")"))
                    trylist(typelist,false)
                end
            end
            return valididx
        end
    end
    
    local function insertcasts(typelist,paramlist) --typelist is a list of target types (or the value "passthrough"), paramlist is a parameter list that might have a multiple return value at the end
        return tryinsertcasts(terra.newlist { typelist }, paramlist)
    end
    
    
    local function insertfunctionliteral(anchor,e)
        local fntyp,errstr = e:gettype(ctx)
        if fntyp == terra.types.error then
            terra.reporterror(ctx,anchor,"error resolving function literal. ",errstr)
        end
        local typ = fntyp and terra.types.pointer(fntyp)
        return terra.newtree(anchor, { kind = terra.kinds.literal, value = e, type = typ or terra.types.error })
    end
    
    function checkmethodorcall(exp, mustreturnatleast1)
        local function checkmethod(reciever,untypedreciever,methodname)
            local fnobj = reciever.type.methods[methodname]
            if reciever.type:ispointer() and not fnobj then --if the reciever was a pointer, but did not have that method, then dereference and look  up in object
                untypedreciever = insertuntypeddereference(untypedreciever)
                fnobj = reciever.type.type.methods[methodname]
                reciever = asrvalue(insertdereference(reciever))
            end
            fnobj = fnobj and createspecial(untypedreciever,fnobj)
            
            if not fnobj then
                terra.reporterror(ctx,exp,"no such method ",methodname," defined for type ",reciever.type)
                return false, exp:copy { kind = terra.kinds.apply, arguments = terra.newlist(), type = terra.types.error, types = terra.newlist() }
            end
            
            local untypedarguments = terra.newlist { untypedreciever }
            local arguments = terra.newlist { createtypedexpression(reciever) }
            
            for _,v in ipairs(exp.arguments) do
                untypedarguments:insert(v)
                arguments:insert(v)
            end
            
            return checkcall(exp,fnobj,arguments,untypedarguments,"first",mustreturnatleast1)
        end
        
        if exp:is "method" then --desugar method a:b(c,d) call by first adding a to the arglist (a,c,d) and typechecking it
                                --then extract a's type from the parameter list and look in the method table for "b" 
            local methodname = checksymbol(exp.name)
            return checkmethod(checkrvalue(exp.value),exp.value,methodname)
        else
            local fn = exp.fn or checkexp(exp.value,true) --node may be either untyped checked (exp.fn == nil) or the function may already have been typed (e.g. in the select operator)
            if fn.type and (fn.type:isstruct() or fn.type:ispointertostruct()) then
                return checkmethod(fn,exp.value,"__apply")
            end
            return checkcall(exp,fn,exp.typedarguments or exp.arguments,exp.arguments,exp.recievers or "none",mustreturnatleast1)
        end
        
    end
    
    function checkcall(anchor, fn, arguments, untypedarguments, recievers, mustreturnatleast1) --mustreturnatleast1 means we must return at least one value because the function was used in an expression, otherwise it was used as a statement and can return none
                                                                     --returns true, <macro exp list> if call was a macro
                                                                     --returns false, <typed tree> otherwise
        local function resolvemacro(macrocall,anchor,...)
            local macroargs = {}
            for i,v in ipairs({...}) do
                v.filename = self.filename
                macroargs[i] = terra.newquote(v,"exp",ctx:luaenv(),ctx:varenv())
            end
            local result = macrocall(ctx,anchor,unpack(macroargs))
            return createspecial(anchor,result)
        end
        
        local function getparametertypes(fntyp,paramlist) --get the expected types for parameters to the call (this extends the function type to the length of the parameters if the function is vararg)
            if not fntyp.isvararg then
                return fntyp.parameters
            end
            
            local vatypes = terra.newlist()
            
            for i,v in ipairs(paramlist.parameters) do
                if i <= #fntyp.parameters then
                    vatypes[i] = fntyp.parameters[i]
                else
                    vatypes[i] = "vararg"
                end
            end
            return vatypes
        end
        
        local function generatenativewrapper(fn,paramlist)
            local paramtypes = paramlist.parameters:map(function(p) return p.type end)
            local castedtype = terra.types.funcpointer(paramtypes,{})
            local cb = ffi.cast(castedtype:cstring(),fn)
            local fptr = terra.pointertolightuserdata(cb)
            return terra.newtree(anchor, { kind = terra.kinds.luafunction, callback = cb, fptr = fptr, type = castedtype })
        end
        
        local alternatives = terra.newlist()
        --check for and dispatch all macros, or build the list of possible function calls
        if fn:is "luaobject" then
            if terra.ismacro(fn.value) then
                 return true,resolvemacro(fn.value,anchor,unpack(untypedarguments))
            elseif terra.types.istype(fn.value) and fn.value:isstruct() then
                local typfn = fn.value:getcanonical(ctx)
                local castmacro = macro(function(ctx,tree,arg)
                    return terra.newtree(tree, { kind = terra.kinds.explicitcast, value = arg.tree, totype = typfn })
                end)
                return true, resolvemacro(castmacro,anchor,unpack(untypedarguments))
            elseif type(fn.value) == "function" then
                alternatives:insert( { type = terra.types.luafunction, fn = fn.value } ) 
            elseif terra.isfunction(fn.value) then
                for i,v in ipairs(fn.value:getvariants()) do
                    local fnlit = insertfunctionliteral(anchor,v)
                    if fnlit.type ~= terra.types.error then
                        alternatives:insert( { type = fnlit.type.type, fn = fnlit } )
                    end
                end
            else
                terra.reporterror(ctx,anchor,"expected a function or macro but found lua value of type ",type(fn.value))
            end
        elseif fn.type:ispointer() and fn.type.type:isfunction() then
            alternatives:insert( { type = fn.type.type, fn = asrvalue(fn) })
        else
            if fn.type ~= terra.types.error then
                terra.reporterror(ctx,anchor,"expected a function but found ",fn.type)
            end
        end
        
        --OK, no macros! we can check the parameter list safely now
        local paramlist = checkparameterlist(anchor,arguments)
        paramlist.recievers = recievers
        
        local typelists = alternatives:map(function(a) return getparametertypes(a.type,paramlist) end)
        local valididx = tryinsertcasts(typelists,paramlist)
        local typ,types,callee
        if valididx then
            local fntyp = alternatives[valididx].type
            callee = alternatives[valididx].fn
            if type(callee) == "function" then
                callee = generatenativewrapper(fn.value,paramlist)
            end
            types = fntyp.returns
            if #types > 0 then
                typ = types[1]
            elseif mustreturnatleast1 then
                typ = terra.types.error
                terra.reporterror(ctx,anchor,"expected call to return at least 1 value")
            end --otherwise this is used in statement context and does not require a type
        else
            typ = terra.types.error
            types = terra.newlist()
        end
        local callexp = terra.newtree(anchor, { kind = terra.kinds.apply, arguments = paramlist, value = callee, type = typ, types = types })
        return false, callexp
    end
    
    function asrvalue(ee)
        if ee.lvalue then
            return terra.newtree(ee,{ kind = terra.kinds.ltor, type = ee.type, expression = ee })
        else
            return ee
        end
    end
    
    function aslvalue(ee) --this is used in a few cases where we allow rvalues to become lvalues
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
    
    function checkrvalue(e)
        local ee = checkexp(e)
        return asrvalue(ee)
    end
    
    function insertselect(v, field)
        local tree = terra.newtree(v, { type = terra.types.error, kind = terra.kinds.select, field = field, value = v, lvalue = v.lvalue })
        assert(v.type:isstruct())
        local index = v.type.keytoindex[field]
        
        if index == nil then
            return nil,false
        end
        tree.index = index
        tree.type = v.type.entries[index+1].type
        return tree,true
    end
    
    function insertvar(anchor, typ, name, definition)
        return terra.newtree(anchor, { kind = terra.kinds["var"], type = typ, name = name, definition = definition, lvalue = true }) 
    end
    
    --takes a raw lua object and creates a tree that represents that object in terra code
    function createspecial(anchor,v)
        if terra.israwlist(v) then
            local values = terra.newlist()
            for _,i in ipairs(v) do
                values:insert(createspecial(anchor,i))
            end
            return terra.newtree(anchor, { kind = terra.kinds.speciallist, values = values})
        elseif terra.isglobalvar(v) then
            local typ,errstr = v:gettype(ctx) -- this will initialize the variable if it is not already
            if typ ~= terra.types.error then
                return insertvar(anchor,typ,v.tree.name,v.tree)
            else
                terra.reporterror(ctx,anchor," error resolving global variable. ",errstr)
                return anchor:copy{type = terra.types.error}
            end
        elseif terra.issymbol(v) then
            local definition = ctx:symenv()[v]
            if not definition then
                terra.reporterror(ctx,anchor,"variable '"..tostring(v).."' not found")
                return insertvar(anchor,terra.types.error,tostring(v),nil)
            end
            return insertvar(anchor,definition.type,tostring(v),definition)
        elseif terra.isfunction(v) then
            local variants = v:getvariants()
            if #variants == 1 then
                return insertfunctionliteral(anchor,variants[1])
            else
                return terra.newtree(anchor, { kind = terra.kinds.luaobject, value = v })
            end
        elseif terra.isquote(v) then
            return terra.newtree(anchor, { kind = terra.kinds.quote, quote = v})
        elseif terra.istree(v) then
            --if this is a raw tree, we just drop it in place and hope the user knew what they were doing
            return v
        elseif type(v) == "number" then
            return terra.newtree(anchor, { kind = terra.kinds.literal, value = v, type = double })
        elseif type(v) == "boolean" then
            return terra.newtree(anchor, { kind = terra.kinds.literal, value = v, type = bool })
        elseif type(v) == "string" then
            return terra.newtree(anchor, { kind = terra.kinds.literal, value = v, type = rawstring })
        elseif terra.ismacro(v) or type(v) == "table" or type(v) == "function" then
            return terra.newtree(anchor, { kind = terra.kinds.luaobject, value = v })
        else
            terra.reporterror(ctx,anchor,"lua object of type ", type(v), " not understood by terra code.")
            return anchor:copy { type = terra.types.error }
        end
    end
    
    --takes a tree and resolves references to lua objects that can result from partial evaluation
    --if the tree is not a var or select, it will just be returned
    --if it is a var, it will be resolved to its definition
    --if that definition is terra code, the var is returned with the definition field set
    --if it is a special object (e.g. terra function, macro, quote, global var), it will insert the appropriate tree in its place
    --if it is a select node a.b it first check 'a' as an expression.
    --if that turns into a luaobject then it will try to perform the partial evaluation of the select
    --otherwise, it will just typecheck the normal select operator
    
    --this function is (and must remain) idempotent (i.e. resolveluaspecial(e) == resolveluaspecial(resolveluaspecial(e)) )
    --to accomplish this, it guarentees that e.type is set for any var/select returned from the expression and will
    --not operator on a var/select node with the type already resolved
    
    function resolveluaspecial(e)
        local canbespecial = (e:is "var" or e:is "select" or e:is "luaexpression") and not e.type
        if not canbespecial then
            return e
        end
        
        if e:is "var" then
            local v = ctx:varenv()[e.name]
            if v ~= nil then
                return e:copy { type = v.type, definition = v, lvalue = true }
            end
            
            v = ctx:luaenv()[e.name]  
            
            if v == nil then
                terra.reporterror(ctx,e,"variable '"..e.name.."' not found")
                return e:copy { type = terra.types.error }
            end
            
            return createspecial(e,v)
                
        elseif e:is "select" then
            local untypedv = e.value
            local v = checkexp(untypedv,true)
            local field = checksymbol(e.field)
            if v:is "luaobject" then
                if type(v.value) ~= "table" then
                    terra.reporterror(ctx,e,"expected a table but found ", type(v.value))
                    return e:copy{ type = terra.types.error }
                end

                local selected = v.value[field]
                if selected == nil then
                    terra.reporterror(ctx,e,"no field ",field," in lua object")
                    return e:copy { type = terra.types.error }
                end
                
                return createspecial(e,selected)
            else
                if v.type:ispointertostruct() then --allow 1 implicit dereference
                    v = insertdereference(v)
                    untypedv = insertuntypeddereference(untypedv)
                end
                if v.type:isstruct() then
                    local ret, success = insertselect(v,field)
                    if not success then
                        --struct has no member field, look for a getter __get<field>
                        local getter = v.type.methods["__get"..field]
                        if getter then
                            return terra.newtree(v, { kind = terra.kinds.apply, fn = createspecial(v,getter), arguments = terra.newlist{untypedv}, typedarguments = terra.newlist{createtypedexpression(v)}, recievers = "first"})
                        else
                            terra.reporterror(ctx,v,"no field ",field," in terra object of type ",v.type)
                            return e:copy { type = terra.types.error }
                        end
                    else
                        return ret
                    end
                else
                    terra.reporterror(ctx,v,"expected a structural type")
                    return e:copy { type = terra.types.error }
                end
            end
        elseif e:is "luaexpression" then     
            local success, value = terra.resolveluaexpression(ctx,e)
            return createspecial(e, (success and value) or {})
        end
        terra.tree.printraw(e)
        error("unresolved special?")
    end
    
    
    function checkexp(e_,allowluaobjects) --if allowluaobjects is true, then checkexp can return trees with kind luaobject (e.g. for partial eval)
        local function handlemacro(ismacro,exp)
            if ismacro then
                return checkexp(exp,allowluaobjects)
            else
                return exp
            end
        end
        local function docheck(e)
            if e:is "luaobject" then
                return e
            elseif e:is "literal" then
                return e
            elseif e:is "var" then
                assert(e.type ~= nil, "found an unresolved var in checkexp")
                return e --we already resolved and typed the variable in resolveluaspecial
            elseif e:is "select" then
                assert(e.type ~= nil,"found an unresolved select in checkexp")
                return e --select has already been resolved by resolveluaspecial
            elseif e:is "typedexpression" then --expression that has been previously typechecked and re-injected into the compiler
                assert(e.exp.type)
                return e.exp
            elseif e:is "operator" then
                return handlemacro(checkoperator(e))
            elseif e:is "index" then
                local v = checkexp(e.value)
                local idx = checkrvalue(e.index)
                local typ,lvalue
                if v.type:ispointer() or v.type:isarray() or v.type:isvector() then
                    typ = v.type.type
                    if not idx.type:isintegral() and idx.type ~= terra.types.error then
                        terra.reporterror(ctx,e,"expected integral index but found ",idx.type)
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
                        terra.reporterror(ctx,e,"expected an array or pointer but found ",v.type)
                    end
                end
                return e:copy { type = typ, lvalue = lvalue, value = v, index = idx }
            elseif e:is "explicitcast" then
                return insertexplicitcast(checkrvalue(e.value),e.totype)
            elseif e:is "sizeof" then
                return e:copy { type = uint64 }
            elseif e:is "vectorconstructor" or e:is "arrayconstructor" then
                local entries = checkparameterlist(e,e.expressions)
                local N = entries.maxsize
                
                
                local typ
                if e.oftype ~= nil then
                    typ = e.oftype
                else
                    if N == 0 then
                        terra.reporterror(ctx,e,"cannot determine type of empty aggregate")
                        return e:copy { type = terra.types.error }
                    end
                    
                    --figure out what type this vector has
                    typ = entries.parameters[1].type
                    for i,p in ipairs(entries.parameters) do
                        typ = typemeet(e,typ,p.type)
                    end
                end
                
                local aggtype
                if e:is "vectorconstructor" then
                    if not typ:isprimitive() and typ ~= terra.types.error then
                        terra.reporterror(ctx,e,"vectors must be composed of primitive types (for now...) but found type ",type(typ))
                        return e:copy { type = terra.types.error }
                    end
                    aggtype = terra.types.vector(typ,N)
                else
                    aggtype = terra.types.array(typ,N)
                end
                
                --insert the casts to the right type in the parameter list
                local typs = entries.parameters:map(function(x) return typ end)
                
                insertcasts(typs,entries)
                
                return e:copy { type = aggtype, expressions = entries }
                
            elseif iscall(e) then
                return handlemacro(checkmethodorcall(e,true))
            elseif e:is "speciallist" then
                if #e.values == 0 then
                    terra.reporterror(ctx,e,"expected list of expressions to have at least 1 object")
                    return e:copy { type = terra.types.error }
                else
                    return checkexp(e.values[1],allowluaobjects)
                end
            elseif e:is "quote" then
                local function checkquote(tree)
                    return checkexp(tree,allowluaobjects)
                end
                return resolvequote(e,e.quote,"exp",checkquote)
            elseif e:is "constructor" then
                local typ = terra.types.newstruct("anon")
                typ:setconvertible(true)
                
                local paramlist = terra.newlist{}
                
                for i,f in ipairs(e.records) do
                    if i == #e.records and f.key and canreturnmultiple(f.value) then
                        --if there is a key assigned to a multireturn then it gets truncated to 1 value
                        f.value.truncated = true
                    end
                    paramlist:insert(f.value)
                end
                
                local entries = checkparameterlist(e,paramlist)
                entries.size = entries.maxsize
                
                for i,v in ipairs(entries.parameters) do
                    local rawkey = e.records[i] and e.records[i].key
                    local k = nil
                    if rawkey then
                        k = checksymbol(rawkey)
                    end
                    if not typ:addentry(k,v.type) then
                        terra.reporterror(ctx,v,"duplicate definition of field ",k)
                    end
                end
                
                return e:copy { expressions = entries, type = typ:getcanonical(ctx) }
            end
            e:printraw()
            print(debug.traceback())
            error("NYI - expression "..terra.kinds[e.kind],2)
        end
        
        local result = docheck(resolveluaspecial(e_))
        
        if result:is "luaobject" and not allowluaobjects then
            local found
            if terra.isfunction(result.value) then
                found = "an overloaded function"
            else
                found = type(result.value)
            end
            terra.reporterror(ctx,result, "expected a terra expression but found "..found)
            result.type = terra.types.error
        end
        
        return result
       
    end
    
    function resolvequote(anchor,q,variant,checkfn)
        if variant == "exp" and q.variant == "stmt" then
            terra.reporterror(ctx,anchor,"found a quoted ",q.variant, " where a ",variant, " is expected.")
            return anchor:copy { type = terra.types.error }
        end
        ctx:enterfile(q.tree.filename)
        ctx:enterquote(q:env()) --q:env() returns both the luaenv and varenv here
        local r = checkfn(q.tree)
        ctx:leavequote()
        ctx:leavefile()
        return r
    end
    
    local function checkexptyp(re,target)
        local e = checkrvalue(re)
        if e.type ~= target then
            terra.reporterror(ctx,e,"expected a ",target," expression but found ",e.type)
            e.type = terra.types.error
        end
        return e
    end
    local function checkcondbranch(s)
        local e = checkexptyp(s.condition,bool)
        local b = checkstmt(s.body)
        return s:copy {condition = e, body = b}
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
    
    function checkstmt(s_)
        local s = resolveluaspecial(s_)
        if s:is "block" then
            ctx:enterblock()
            local r = s.statements:flatmap(checkstmt)
            ctx:leaveblock()
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
                terra.reporterror(ctx,s,"label defined twice")
                terra.reporterror(ctx,lbls,"previous definition here")
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
                terra.reporterror(ctx,s,"break found outside a loop")
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
            ctx:enterblock() --we don't use block here because, unlike while loops, the condition needs to be checked in the scope of the loop
            local new_blk = s.body:copy { statements = s.body.statements:map(checkstmt) }
            local e = checkexptyp(s.condition,bool)
            ctx:leaveblock()
            leaveloop()
            return s:copy { body = new_blk, condition = e, breaktable = breaktable }
        elseif s:is "defvar" then
            local res
            
            local lhs = createformalparameterlist(s.variables)

            if s.initializers then
                local params = checkparameterlist(s,s.initializers)
                
                local vtypes = terra.newlist()
                for i,v in ipairs(lhs) do
                    vtypes:insert(v.type or "passthrough")
                end
                
                insertcasts(vtypes,params)
                
                for i,v in ipairs(lhs) do
                    v.type = (params.parameters[i] and params.parameters[i].type) or terra.types.error
                end
                
                res = s:copy { variables = lhs, initializers = params }
            else
                for i,v in ipairs(lhs) do
                    local typ = terra.types.error
                    if not v.type then
                        terra.reporterror(ctx,v,"type must be specified for uninitialized variables")
                        v.type = terra.types.error
                    end
                end
                res = s:copy { variables = lhs }
            end     
            --add the variables to current environment 
            --unless they are global variables (which are resolved through lua's env)
            if not s.isglobal then
                for i,v in ipairs(lhs) do
                    if terra.issymbol(v.name) then
                        ctx:symenv()[v.name] = v
                    else 
                        ctx:varenv()[v.name] = v
                    end
                end
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
        elseif s:is "fornum" then
            function mkdefs(...)
                local lst = terra.newlist()
                for i,v in pairs({...}) do
                    local sym = terra.newtree(s,{ kind = terra.kinds.symbol, name = v})
                    lst:insert( terra.newtree(s,{ kind = terra.kinds.entry, name = sym }) )
                end
                return lst
            end
            
            function mkvar(a)
                assert(type(a) == "string")
                return terra.newtree(s,{ kind = terra.kinds["var"], name = a })
            end
            
            function mkop(op,a,b)
               return terra.newtree(s, {
                kind = terra.kinds.operator;
                operator = terra.kinds[op];
                operands = terra.newlist { mkvar(a), mkvar(b) };
                })
            end

            local dv = terra.newtree(s, { 
                kind = terra.kinds.defvar;
                variables = mkdefs("<i>","<limit>","<step>");
                initializers = terra.newlist({s.initial,s.limit,s.step})
            })
            
            local lt = mkop("<","<i>","<limit>")
            
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
                condition = lt;
                body = nbody;
            })
        
            local desugared = terra.newtree(s, { kind = terra.kinds.block, statements = terra.newlist {dv,wh} } )
            --desugared:printraw()
            return checkstmt(desugared)
        elseif iscall(s) then
            local ismacro, c = checkmethodorcall(s,false) --allowed to be void, if this was a macro then this might return a list of values, which are flattened into the enclosing block (see list.flatmap)
            if ismacro then
                return checkstmt(c)
            else
                return c
            end
        elseif s:is "speciallist" then
            return s.values:flatmap(checkstmt)
        elseif s:is "quote" then
            local function checkquote(tree) 
                --each quoted statement is wrapped in a block tree if is has variant "stmt", which we ignore here and return a list of statements
                if s.quote.variant == "stmt" then
                    return tree.statements:flatmap(checkstmt)
                else
                --an exp is being used a block level, don't try to unwrap it
                    return terra.newlist {checkstmt(tree)}
                end
            end
            return resolvequote(anchor,s.quote,"stmt",checkquote)
        else
            return checkexp(s)
        end
        error("NYI - "..terra.kinds[s.kind],2)
    end
    
    -- actual implementation begins here
    --  generate types for parameters, if return types exists generate a types for them as well
    local typed_parameters = createformalparameterlist(ftree.parameters)
    local parameter_types = terra.newlist() --just the types, used to create the function type
    for _,v in ipairs(typed_parameters) do
        if not v.type then
            terra.reporterror(ctx,v,"symbol representing a parameter must have a type")
            v.type = terra.types.error
        end
        parameter_types:insert( v.type )
        local env = (terra.issymbol(v.name) and ctx:symenv()) or ctx:varenv()
        if env[v.name] then
            terra.reporterror(ctx,v,"duplicate definition of parameter ",v.name)
        end
        env[v.name] = v
    end

    local result = checkstmt(ftree.body)
    for _,v in pairs(labels) do
        if not terra.istree(v) then
            terra.reporterror(ctx,v[1],"goto to undefined label")
        end
    end
    
    
    dbprint("Return Stmts:")
    
    
    local return_types
    if ftree.return_types then --take the return types to be as specified
        return_types = resolvetype(ftree.return_types,true)
    else --calculate the meet of all return type to calculate the actual return type
        if #return_stmts == 0 then
            return_types = terra.newlist()
        else
            local minsize,maxsize
            for _,stmt in ipairs(return_stmts) do
                if return_types == nil then
                    return_types = terra.newlist()
                    for i,exp in ipairs(stmt.expressions.parameters) do
                        return_types[i] = exp.type
                    end
                    minsize = stmt.expressions.minsize
                    maxsize = stmt.expressions.maxsize
                else
                    minsize = math.max(minsize,stmt.expressions.minsize)
                    maxsize = math.min(maxsize,stmt.expressions.maxsize)
                    if minsize > maxsize then
                        terra.reporterror(ctx,stmt,"returning a different length from previous return")
                    else
                        for i,exp in ipairs(stmt.expressions) do
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
    
    --now cast each return expression to the expected return type
    for _,stmt in ipairs(return_stmts) do
        insertcasts(return_types,stmt.expressions)
    end
    
    
    local typedtree = ftree:copy { body = result, parameters = typed_parameters, labels = labels, type = terra.types.functype(parameter_types,return_types) }
    
    dbprint("TypedTree")
    dbprintraw(typedtree)
    
    ctx:leavedef()
    ctx:leavefile()
    
    return typedtree
end

-- END TYPECHECKER

-- INCLUDEC

function terra.includecstring(code)
    return terra.registercfile(code,{"-I",".","-O3"})
end
function terra.includec(fname)
    return terra.includecstring("#include \""..fname.."\"\n")
end

function terra.includetableindex(tbl,name)    --this is called when a table returned from terra.includec doesn't contain an entry
    local v = getmetatable(tbl).errors[name]  --it is used to report why a function or type couldn't be included
    if v then
        error("includec: error importing symbol '"..name.."': "..v, 2)
    else
        error("includec: imported symbol '"..name.."' not found.",2)
    end
    return nil
end

-- GLOBAL MACROS
_G["sizeof"] = macro(function(ctx,tree,typ)
    return terra.newtree(tree,{ kind = terra.kinds.sizeof, oftype = typ:astype(ctx)})
end)
_G["vector"] = macro(function(ctx,tree,...)
    if terra.types.istype(ctx) then --vector used as a type constructor vector(int,3)
        return terra.types.vector(ctx,tree)
    end
    --otherwise this is a macro that constructs a vector literal
    local exps = terra.newlist({...}):map(function(x) return x.tree end)
    return terra.newtree(tree,{ kind = terra.kinds.vectorconstructor, expressions = exps })
    
end)
_G["vectorof"] = macro(function(ctx,tree,typ,...)
    local exps = terra.newlist({...}):map(function(x) return x.tree end)
    return terra.newtree(tree,{ kind = terra.kinds.vectorconstructor, oftype = typ:astype(ctx), expressions = exps })
end)
_G["array"] = macro(function(ctx,tree,...)
    local exps = terra.newlist({...}):map(function(x) return x.tree end)
    return terra.newtree(tree, { kind = terra.kinds.arrayconstructor, expressions = exps })
end)
_G["arrayof"] = macro(function(ctx,tree,typ,...)
    local exps = terra.newlist({...}):map(function(x) return x.tree end)
    return terra.newtree(tree, { kind = terra.kinds.arrayconstructor, oftype = typ:astype(ctx), expressions = exps })
end)

terra.select = macro(function(ctx,tree,guard,a,b)
    return terra.newtree(tree, { kind = terra.kinds.operator, operator = terra.kinds.select, operands = terra.newlist{guard.tree,a.tree,b.tree}})
end)
-- END GLOBAL MACROS

function terra.pointertolightuserdatahelper(cdataobj,assignfn,assignresult)
    local afn = ffi.cast("void (*)(void *,void**)",assignfn)
    afn(cdataobj,assignresult)
end

function terra.saveobj(filename,env,arguments)
    local cleanenv = {}
    for k,v in pairs(env) do
        if terra.isfunction(v) then
            v:compile()
            local variants = v:getvariants()
            if #variants > 1 then
                error("cannot create a C function from an overloaded terra function, "..k)
            end
            cleanenv[k] = variants[1]
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

function terra.require(name)
    if not terra.packages[name] then
        local file = name .. ".t"
        local fn, err = terra.loadfile(file)
        if not fn then
            error(err)
        end
        terra.packages[name] = { results = {fn()} }    
    end
    return unpack(terra.packages[name].results)
end

_G["terralib"] = terra --terra code can't use "terra" because it is a keyword
--io.write("done\n")

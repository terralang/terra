io.write("loading terra lib...")

--[[
some experiments with ffi to call function given a function pointer
local ffi = require("ffi")
print("push function is: "..type(functest))
ffi.cdef("typedef struct { void (*fn)(double,double); } my_struct;") 
func = ffi.cast("my_struct*",functest)
func.fn(1,2)
]]
local ffi = require("ffi")

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
        if type(t) == "table" then
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
            elseif depth > 0 and terra.isfunction(t) then
                return --don't print the entire nested function...
            end
            parents[t] = true
            depth = depth + 1
            for k,v in pairs(t) do
                if k ~= "kind" and k ~= "offset" and k ~= "linenumber" then
                    local prefix = spacing..k..": "
                    print(prefix..header(k,v))
                    if isList(v) then
                        printElem(v,string.rep(" ",2+#spacing))
                    else
                        printElem(v,string.rep(" ",2+#prefix))
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
function terra.newtree(ref,body)
    if not ref or not terra.istree(ref) then
        error("not a tree?",2)
    end
    body.offset = ref.offset
    body.linenumber = ref.linenumber
    return setmetatable(body,terra.tree)
end

function terra.istree(v) 
    return terra.tree == getmetatable(v)
end

terra.func = {} --metatable for all function types
terra.func.__index = terra.func
function terra.func:env()
    self.envtbl = self.envtbl or self.envfunction() --evaluate the environment if needed
    self.envfunction = nil --we don't need the closure anymore
    return self.envtbl
end
function terra.func:gettype(ctx)
    if self.type then --already typechecked
        return self.type
    else --we need to compile the function now because it has been referenced
        if self.iscompiling then
            if self.untypedtree.return_types then --we are already compiling this function, but the return types are listed, so we can resolve the type anyway  
                local params = terra.newlist()
                local function rt(t) return terra.resolvetype(ctx,t) end
                for _,v in ipairs(self.untypedtree.parameters) do
                    params:insert(rt(v.type))
                end
                local rets = self.untypedtree.return_types:map(rt)
                self.type = terra.types.functype(params,rets) --for future calls
                return self.type
            else
                terra.reporterror(ctx,self.untypedtree,"recursively called function needs an explicit return type")
                return terra.types.error
            end
        else
            self:compile(ctx)
            return self.type
        end
    end
    
end
function terra.func:makewrapper()
    local fntyp = self.typedtree.type
    
    local rt
    local rname
    if #fntyp.returns == 0 then
        rt = "void"
    elseif #fntyp.returns == 1 then
        rt = fntyp.returns[1]:cstring()
    else
        local rtype = "typedef struct { "
        for i,v in ipairs(fntyp.returns) do
            rtype = rtype..v:cstring().." v"..tostring(i).."; "
        end
        rname = self.name.."_return_t"
        self.ffireturnname = rname.."[1]"
        rtype = rtype .. " } "..rname..";"
        print(rtype)
        ffi.cdef(rtype)
        rt = "void"
    end
    local function getcstring(t)
        return t:cstring()
    end
    local pa = fntyp.parameters:map(getcstring)
    
    if #fntyp.returns > 1 then
        pa:insert(1,rname .. "*")
    end
    
    pa = pa:mkstring("(",",",")")
    local ntyp = self.name.."_t"
    local cdef = "typedef struct { "..rt.." (*fn)"..pa.."; } "..ntyp..";"
    print(cdef)
    ffi.cdef(cdef)
    self.ffiwrapper = ffi.cast(ntyp.."*",self.fptr)
end

terra.context = {}
terra.context.__index = terra.context
function terra.context:push(filename, env)
    local tbl = { filename = filename, env = env } 
    table.insert(self.stack,tbl)
end
function terra.context:pop()
    local tbl = table.remove(self.stack)
    if tbl.filehandle then
        terra.closesourcefile(tbl.filehandle)
        tbl.filehandle = nil
    end
end
function terra.context:env()
    return self.stack[#self.stack].env
end
function terra.context:setenv(env)
    self.stack[#self.stack].env = env
end
--terra.printlocation
--and terra.opensourcefile are inserted by C wrapper
function terra.context:printsource(anchor)
    local top = self.stack[#self.stack]
    if not top.filehandle then
        top.filehandle = terra.opensourcefile(top.filename)
    end
    terra.printlocation(top.filehandle,anchor.offset)
end
function terra.context:reporterror(anchor,...)
    self.has_errors = true
    local top = self.stack[#self.stack]
    io.write(top.filename..":"..anchor.linenumber..": ")
    for _,v in ipairs({...}) do
        io.write(tostring(v))
    end
    io.write("\n")
    self:printsource(anchor)
end
function terra.context:isempty()
    return #self.stack == 0
end

function terra.newcontext()
    return setmetatable({stack = {}},terra.context)
end

function terra.func:compile(ctx)
    ctx = ctx or terra.newcontext() -- if this is a top level compile, create a new compilation context
    print("compiling function:")
    self.untypedtree:printraw()
    print("with local environment:")
    terra.tree.printraw(self:env())
    self.typedtree = self:typecheck(ctx)
    self.type = self.typedtree.type
    
    if ctx.has_errors then 
        if ctx:isempty() then --if this was not the top level compile we let type-checking of other functions continue, 
                                --though we don't actually compile because of the errors
            error("Errors reported during compilation.")
        end
    else 
        --now call llvm to compile...
        terra.compile(self)
        self:makewrapper()
    end
end

function terra.func:__call(...)
    if not self.typedtree then
        self:compile()
    end
    
    --TODO: generate code to do this for each function rather than interpret it on every call
    local nr = #self.typedtree.type.returns
    if nr > 1 then
        local result = ffi.new(self.ffireturnname)
        self.ffiwrapper.fn(result,...)
        local rv = result[0]
        local rs = {}
        for i = 1,nr do
            table.insert(rs,rv["v"..i])
        end
        return unpack(rs)
    else
        return self.ffiwrapper.fn(...)
    end
end


function terra.isfunction(obj)
    return getmetatable(obj) == terra.func
end

terra.globalvar = {} --metatable for all global variables
terra.globalvar.__index = terra.globalvar

function terra.isglobalvar(obj)
    return getmetatable(obj) == terra.globalvar
end

function terra.globalvar:compile(ctx)

    ctx = ctx or terra.newcontext()
    local globalinit = self.initializer --this initializer may initialize more than 1 variable, all of them are handled here
    
    
    globalinit.initfn:compile(ctx)
    
    --TODO: we need to detect if initfn relies on a function (fn) already being compiled lower on the stack.
    --if so, that means that fn uses these global variables, but the initializers for these global variables requires fn, which is a cyclic dependency.
    --detecting this requires know if everything below the call to compile has been completed
    
    --running initfn will  initialize the variables
    globalinit.initfn()
    
    local entries = globalinit.initfn.typedtree.body.statements[1].variables --extract definitions from generated function
    for i,v in ipairs(globalinit.globals) do
        v.tree = entries[i]
        v.type = v.tree.type
    end
    
end
function terra.globalvar:gettype(ctx) 
    if self.type then
        return self.type
    else --we need to compile
        self:compile(ctx)
        if self.type == nil then
            error("nil type?")
        end
        return self.tree.type
    end
end

do  --constructor functions for terra functions and variables
    local name_count = 0
    local function manglename(nm)
        local fixed = nm:gsub("[^A-Za-z0-9]","_") .. name_count --todo if a user writes terra foo, pass in the string "foo"
        name_count = name_count + 1
        return fixed
    end
    function terra.newfunction(olddef,newtree,name,env,reciever)
        if olddef then
            error("NYI - overloaded functions",2)
        end
        local rawname = (name or newtree.filename.."_"..newtree.linenumber.."_")
        local fname = manglename(rawname)
        local obj = { untypedtree = newtree, filename = newtree.filename, envfunction = env, name = fname }
        local fn = setmetatable(obj,terra.func)
        
        --handle desugaring of methods defintions by adding an implicit self argument
        if reciever ~= nil then
            local pointerto = terra.types.pointer
            local addressof = terra.newtree(newtree, { kind = terra.kinds["type"], expression = function() return pointerto(reciever) end })
            local implicitparam = terra.newtree(newtree, { kind = terra.kinds.entry, name = "self", type = addressof })
            table.insert(newtree.parameters,1,implicitparam) --add the implicit parameter to the parameter list
        end
        
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
                elseif t.kind == terra.kinds.select then
                    return nm(t.value) .. "_" .. t.field
                else
                    error("not a variable name?")
                end
            end
            local n = nm(v.name) .. "_" .. name_count
            name_count = name_count + 1
            
            local varentry = terra.newtree(v, { kind = terra.kinds.entry, name = n, type = v.type })
            varentries:insert(varentry)
            
            local gv = setmetatable({initializer = globalinit},terra.globalvar)
            globals:insert(gv)
        end
        
        local anchor = tree.variables[1]
        local dv = terra.newtree(anchor, { kind = terra.kinds.defvar, variables = varentries, initializers = tree.initializers, isglobal = true})
        local body = terra.newtree(anchor, { kind = terra.kinds.block, statements = terra.newlist {dv} })
        local ftree = terra.newtree(anchor, { kind = terra.kinds["function"], parameters = terra.newlist(),
                                              is_varargs = false, filename = tree.filename, body = body})
        
        globalinit.initfn = terra.newfunction(nil,ftree,nil,env)
        globalinit.globals = globals

        return unpack(globals)
    end
    
    function terra.namedstruct(tree,name,env)
        return terra.types.newnamedstruct(name,manglename(name),tree,env)
    end
    function terra.anonstruct(tree,env)
       return terra.types.newanonstruct(tree,env)
    end
end


--[[
types take the form
primitive(name)
pointer(typ)
array(typ,N)
struct(types)
union(types)
named(name,typ), where typ is the unnamed structural type and name is the internally generated unique name for the type
functype(arguments,results) 
]]
do --construct type table that holds the singleton value representing each unique type
   --eventually this will be linked to the LLVM object representing the type
   --and any information about the operators defined on the type
    local types = {}
    
    
    types.type = {} --all types have this as their metatable
    types.type.__index = types.type
    
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
    function types.type:isfunction()
        return self.kind == terra.kinds.functype
    end
    function types.type:isstruct()
        return self.kind == terra.kinds["struct"]
    end
    
    function types.type:iscanonical()
        return self.kind ~= terra.kinds.proxy
    end
    
    function types.type:cstring()
        if self:isintegral() then
            return tostring(self).."_t"
        elseif self:isfloat() then
            return tostring(self)
        elseif self:ispointer() then
            return self.type:cstring().."*"
        elseif self:islogical() then
            return "unsigned char"
        elseif self:isstruct() then
            return "void *" --TODO: this should actually declare the struct and make wrapper should handle the wrapping up of struct values
        else
            error("NYI - cstring")
        end
    end
    
    function types.type:getcanonical(ctx) --overriden by named structs to build their member tables and by proxy types to lazily evaluate their type
        return self
    end
    
    function types.istype(t)
        return getmetatable(t) == types.type
    end
    
    --map from unique type identifier string to the metadata for the type
    types.table = {}
    
    local function mktyp(v)
        v.methods = {} --create new blank method table
        return setmetatable(v,types.type)
    end
    
    --initialize integral types
    local integer_sizes = {1,2,4,8}
    for _,size in ipairs(integer_sizes) do
        for _,s in ipairs{true,false} do
            local name = "int"..tostring(size * 8)
            if not s then
                name = "u"..name
            end
            local typ = mktyp { kind = terra.kinds.primitive, bytes = size, type = terra.kinds.integer, signed = s, name = name}
            types.table[name] = typ
        end
    end  
    
    types.table["float"] = mktyp { kind = terra.kinds.primitive, bytes = 4, type = terra.kinds.float, name = "float" }
    types.table["double"] = mktyp { kind = terra.kinds.primitive, bytes = 8, type = terra.kinds.float, name = "double" }
    types.table["bool"] = mktyp { kind = terra.kinds.primitive, bytes = 1, type = terra.kinds.logical, name = "bool" }
    
    types.error = mktyp { kind = terra.kinds.error , name = "error" } --object representing where the typechecker failed
    
    local function checkistype(typ)
        if not types.istype(typ) then 
            error("expected a type but found "..type(typ))
        end
    end
    
    function types.pointer(typ)
        checkistype(typ)
    
        if typ == types.error then return types.error end
        
        local function create(typ)
            local name = "&"..typ.name 
            local value = types.table[name]
            if value == nil then
                value = mktyp { kind = terra.kinds.pointer, type = typ, name = name }
                setmetatable(value.methods, { __index = typ.methods } ) --if a method is not defined on the pointer class explicitly it is looked up in the pointee
                types.table[name] = value
            end
            return value
        end
        if typ:iscanonical() then
            return create(typ)
        else
            local proxy = mktyp { kind = terra.kinds.proxy }
            function proxy:getcanonical(ctx) 
                if self.type then return self.type end
                self.type = create(typ:getcanonical(ctx)) 
                return self.type
            end
            return proxy
        end
    end
    
    function types.array(typ,sz)
        --TODO
    end
    function types.primitive(name)
        return types.table[name] or types.error
    end
    
    function types.newemptystruct(typ)
        local tbl = mktyp { kind = terra.kinds["struct"],entries = terra.newlist(), keytoindex = {}, nextunnamed = 0 }
        for k,v in pairs(typ) do
            tbl[k] = v 
        end
        function tbl:addentry(k,t)
            local entry = { type = t, key = k, hasname = true }
            if not k then
                entry.hasname = false
                entry.key = "_"..tostring(self.nextunnamed)
                self.nextunnamed = self.nextunnamed + 1
            end
            local notduplicate = self.keytoindex[entry.key] == nil          
            self.keytoindex[entry.key] = #self.entries
            self.entries:insert(entry)
            return notduplicate
        end
        
        return tbl
    end
    
    function types.canonicalanonstruct(prototype)
        local name = "struct { "
        for i,v in ipairs(prototype.entries) do
            name = name .. v.key .. " : " .. v.type.name .. "; "
        end
        name = name .. "}"
        
        if types.table[name] then
            return types.table[name]
        else
            prototype.name = name
            types.table[name] = prototype
            return prototype
        end
    end
    
    local function buildstruct(ctx,typ,tree,env)
        ctx:push(tree.filename,env())
        for i,v in ipairs(tree.records) do
            local resolvedtype = terra.resolvetype(ctx,v.type)
            if not v.key and typ.isnamed then
                terra.reporterror(ctx,v,"elements of a named struct must be named")
            end
            if not typ:addentry(v.key,resolvedtype) then
                terra.reporterror(ctx,v,"duplicate definition of field ",v.key)
            end
        end
        ctx:pop()
    end
    
    function types.newanonstruct(tree,env)
        local proxy = mktyp { kind = terra.kinds.proxy }
        
        function proxy:getcanonical(ctx)
            local typ = types.newemptystruct {}
            if self.canonicalizing then
                terra.reporterror(ctx,tree,"anonymous structs cannot be recursive.")
                return terra.types.error
            elseif self.type then
                return self.type
            else --get the actual unique type for this unamed struct
                self.canonicalizing = true
                buildstruct(ctx,typ,tree,env)
                self.canonicalizing = nil
                self.type = types.canonicalanonstruct(typ)
                return self.type
            end
        end
        
        return proxy
    end
    
    function types.newnamedstruct(displayname, name,tree,env)
        local typ = types.newemptystruct { name = name, displayname = displayname, isnamed = true }
        function typ:getcanonical(ctx)
            self.getcanonical = nil -- if we recursively try to evaluate this type then just return it
            
            buildstruct(ctx,typ,tree,env)
            
            local function checkrecursion(t)
                if t == self then
                    terra.reporterror(ctx,tree,"type recursively contains itself")
                elseif t:isstruct() then
                    for i,v in ipairs(t.entries) do
                        checkrecursion(v.type)
                    end
                end
                --TODO: need to check for arrays when they are implemented
            end
            for i,v in ipairs(self.entries) do
                checkrecursion(v.type)
            end
            
            print("Resolved Named Struct To:")
            self:printraw()
            return self
        end
        return typ
    end
    
    function types.funcpointer(parameters,returns)
        if types.istype(parameters) then
            parameters = {parameters}
        end
        if types.istype(returns) then
            returns = {returns}
        end
        return types.pointer(types.functype(parameters,returns))
    end
    
    function types.functype(parameters,returns)
        
        local function create(parameters,returns)
            local function getname(t) return t.name end
            local a = terra.list.map(parameters,getname):mkstring("{",",","}")
            local r = terra.list.map(returns,getname):mkstring("{",",","}")
            local name = a.."->"..r
            local value = types.table[name]
            if value == nil then
                value = mktyp { kind = terra.kinds.functype, parameters = parameters, returns = returns, name = name }
            end
            return value
        end
        
        function checkalltypes(l)
            for i,v in ipairs(l) do
                checkistype(v)
            end
        end
        checkalltypes(parameters)
        checkalltypes(returns)
        
        local function makeproxy()
            local proxy = mktyp { kind = terra.kinds.proxy, parameters = parameters, returns = returns }
            function proxy:getcanonical(ctx)
                if self.type then return self.type end
                
                local function mapcanon(l)
                    local nl = terra.newlist()
                    for i,v in ipairs(l) do
                        nl:insert(v:getcanonical(ctx))
                    end
                    return nl
                end
                self.type = create(mapcanon(parameters),mapcanon(returns))
                return self.type
            end
            return proxy
        end
        
        local function checkcanon(l)
            for i,v in ipairs(l) do
                if not v:iscanonical() then
                    return makeproxy()
                end
            end
            return nil
        end
        
        return checkcanon(parameters) or checkcanon(returns) or create(parameters,returns)
        
    end
    
    for name,typ in pairs(types.table) do
        --introduce primitive types into global namespace
        -- outside of the typechecker and internal terra modules
        _G[name] = typ 
    end
    _G["int"] = int32
    _G["long"] = int64
    _G["intptr"] = uint64
    _G["ptrdiff"] = int64

    terra.types = types
end


function terra.reporterror(ctx,anchor,...)
    ctx:reporterror(anchor,...)
    return terra.types.error
end

function terra.resolvetype(ctx,t)
    if not t:is "type" then
        print(debug.traceback())
        t:printraw()
        error("not a type?")
    end
    
    local env = ctx:env()
    local fn = t.expression
    setfenv(fn,env)
    
    local success,typ = pcall(fn)
    
    if not success then --typ contains the error message
        local line,err = typ:match(":([0-9]+):(.*)")
        t.linenumber = t.linenumber + tonumber(line) - 1
        terra.reporterror(ctx,t,err)
        return terra.types.error
    end
    
    if terra.types.istype(typ) then
        return typ:getcanonical(ctx)
    else
        terra.reporterror(ctx,t,"expected a type but found ", type(typ))
        return terra.types.error
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


function terra.func:typecheck(ctx)
    
    ctx:push(self.filename,self:env())
    
    self.iscompiling = true --to catch recursive compilation calls
    
    local ftree = self.untypedtree
    
    local function resolvetype(t)
        return terra.resolvetype(ctx,t)
    end
    
    
    
    
    local insertcast,structcast, insertvar, insertselect,asrvalue
    
    function structcast(cast,exp,typ)
        local from = exp.type
        local to = typ
        
        cast.structvariable = terra.newtree(exp, { kind = terra.kinds.entry, name = "<structcast>", type = from })
        local var_ref = insertvar(exp,from,cast.structvariable.name,cast.structvariable)
        
        local indextoinit = {}
        for i,entry in ipairs(from.entries) do
            local selected = asrvalue(insertselect(var_ref,entry.key))
            if entry.hasname then
                local offset = to.keytoindex[entry.key]
                if not offset then
                    terra.reporterror(ctx,exp, "structural cast invalid, result structure has no key ", entry.key)
                else
                    if indextoinit[offset] then
                        terra.reporterror(ctx,exp, "structural cast invalid, ",entry.key," initialized more than once")
                    end
                    indextoinit[offset] = insertcast(selected,to.entries[offset+1].type)
                end
            else
                --find the first non initialized entry
                local offset = 0
                while offset < #to.entries and indextoinit[offset] do
                    offset = offset + 1
                end
                if offset == #to.entries then
                    terra.reporterror(ctx,exp,"structural cast invalid, too many unnamed fields")
                else
                    indextoinit[offset] = insertcast(selected,to.entries[offset+1].type)
                end
            end
        end
        
        cast.entries = terra.newlist()
        for i,v in pairs(indextoinit) do
            cast.entries:insert( { index = i, value = v } )
        end
        
        return cast
    end
    
    function insertcast(exp,typ)
        if typ == exp.type or typ == terra.types.error or exp.type == terra.types.error then
            return exp
        else
            local cast_exp = terra.newtree(exp, { kind = terra.kinds.cast, from = exp.type, to = typ, type = typ, expression = exp })
            if typ:isprimitive() and exp.type:isprimitive() and not typ:islogical() and not exp.type:islogical() then
                return cast_exp
            elseif typ:isstruct() and exp.type:isstruct() and not exp.type.isnamed then 
                return structcast(cast_exp,exp,typ)
            else
                terra.reporterror(ctx,exp,"invalid conversion from ",exp.type," to ",typ)
                return cast_exp
            end
        end
    end
    
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
            end
        else
            err()
            return terra.types.error
        end
    end
    local function typematch(op,lstmt,rstmt)
        local inputtype = typemeet(op,lstmt.type,rstmt.type)
        return inputtype, insertcast(lstmt,inputtype), insertcast(rstmt,inputtype)
    end
    
    -- 1. generate types for parameters, if return types exists generate a types for them as well
    local typed_parameters = terra.newlist()
    local parameter_types = terra.newlist() --just the types, used to create the function type
    for _,v in ipairs(ftree.parameters) do
        local typ = resolvetype(v.type)
        typed_parameters:insert( v:copy({ type = typ }) )
        parameter_types:insert( typ )
        --print(v.name,parameters_to_type[v.name])
    end
    
    local return_stmts = terra.newlist() --keep track of return stms, these will be merged at the end, possibly inserting casts
    
    local parameters_to_type = {}
    for _,v in ipairs(typed_parameters) do
        parameters_to_type[v.name] = v
    end
    
    
    local labels = {} --map from label name to definition (or, if undefined to the list of already seen gotos that target that label)
    
    local env = parameters_to_type
    
    local typingenv = { __index = function(_,idx) 
        return env[idx] or self:env()[idx] 
    end }
    setmetatable(typingenv,typingenv)
    ctx:setenv(typingenv)
    
    local function enterblock()
        env = setmetatable({},{ __index = env })
    end
    local function leaveblock()
        env = getmetatable(env).__index
    end
    
    local loopstmts = terra.newlist()
    local function enterloop()
        local bt = {}
        loopstmts:insert(bt)
        return bt
    end
    local function leaveloop()
        loopstmts:remove()
    end
    
    local checkexp,checkstmt, checkexpraw, checkrvalue
    
    local function checkunary(ee,property)
        local e = checkrvalue(ee.operands[1])
        if e.type ~= terra.types.error and not e.type[property](e.type) then
            terra.reporterror(ctx,e,"argument of unary operator is not valid type but ",t)
            return e:copy { type = terra.types.error }
        end
        return ee:copy { type = e.type, operands = terra.newlist{e} }
    end 
    
    
    local function meetbinary(e,property,lhs,rhs)
        local t,l,r = typematch(e,lhs,rhs)
        if t ~= terra.types.error and not t[property](t) then
            terra.reporterror(ctx,e,"arguments of binary operators are not valid type but ",t)
            return e:copy { type = terra.types.error }
        end
        return e:copy { type = t, operands = terra.newlist {l,r} }
    end
    
    local function checkbinaryorunary(e,property)
        if #e.operands == 1 then
            return checkunary(e,property)
        end
        return meetbinary(e,property,checkrvalue(e.operands[1]),checkrvalue(e.operands[2]))
    end
    
    local function checkarith(e)
        return checkbinaryorunary(e,"isarithmetic")
    end

    local function checkarithpointer(e)
        if #e.operands == 1 then
            return checkunary(e,"isarithmetic")
        end
        
        local l = checkrvalue(e.operands[1])
        local r = checkrvalue(e.operands[2])

        -- subtracting 2 pointers
        if l.type:ispointer() and l.type == r.type and e.operator == terra.kinds["-"] then
            return e:copy { type = ptrdiff, operands = terra.newlist {l,r} }
        elseif l.type:ispointer() and r.type:isintegral() then -- adding or subtracting a int to a pointer 
            return e:copy { type = l.type, operands = terra.newlist {l,r} }
        elseif l.type:isintegral() and r.type:ispointer() then
            return e:copy { type = r.type, operands = terra.newlist {r,l} }
        else
            return meetbinary(e,"isarithmetic",l,r)
        end
    end

    local function checkintegralarith(e)
        return checkbinaryorunary(e,"isintegral")
    end
    local function checkcomparision(e)
        local t,l,r = typematch(e,checkrvalue(e.operands[1]),checkrvalue(e.operands[2]))
        return e:copy { type = bool, operands = terra.newlist {l,r} }
    end
    local function checklogicalorintegral(e)
        return checkbinaryorunary(e,"canbeord")
    end
    
    local function checklvalue(ee)
        local e = checkexp(ee)
        if not e.lvalue then
            terra.reporterror(ctx,e,"argument to operator must be an lvalue")
            e.type = terra.types.error
        end
        return e
    end
    local function checkaddressof(ee)
        local e = checklvalue(ee.operands[1])
        local ty = terra.types.pointer(e.type)
        return ee:copy { type = ty, operands = terra.newlist{e} }
    end
    
    local function insertdereference(ee)
        local e = asrvalue(ee)
        local ret = terra.newtree(e,{ kind = terra.kinds.operator, operator = terra.kinds["@"], operands = terra.newlist{e}, lvalue = true })
        if not e.type:ispointer() then
            terra.reporterror(ctx,e,"argument of dereference is not a pointer type but ",e.type)
            ret.type = terra.types.error 
        else
            ret.type = e.type.type
        end
        return ret
    end
    
    local function checkdereference(ee)
        local e = checkrvalue(ee.operands[1])
        return insertdereference(e)
    end
    
    local operator_table = {
        ["-"] = checkarithpointer;
        ["+"] = checkarithpointer;
        ["*"] = checkarith;
        ["/"] = checkarith;
        ["%"] = checkarith;
        ["<"] = checkcomparision;
        ["<="] = checkcomparision;
        [">"] = checkcomparision;
        [">="] =  checkcomparision;
        ["=="] = checkcomparision;
        ["~="] = checkcomparision;
        ["and"] = checklogicalorintegral;
        ["or"] = checklogicalorintegral;
        ["not"] = checklogicalorintegral;
        ["&"] = checkaddressof;
        ["@"] = checkdereference;
        ["^"] = checkintegralarith;
    }
    
    
    local checkparameterlist, checkcall
    function checkparameterlist(anchor,params)
        local exps = terra.newlist()
        for i = 1,#params - 1 do
            exps:insert(checkrvalue(params[i]))
        end
        local minsize = #exps
        local multiret = nil
        
        if #params ~= 0 then --handle the case where the last value returns multiple things
            minsize = minsize + 1
            local last = params[#params]
            if last.kind == terra.kinds.apply or last.kind == terra.kinds.method then
                local multifunc = checkcall(last,true) --must return at least one value
                if #multifunc.types == 1 then
                    exps:insert(multifunc) --just insert it as a normal single-return function
                else --remember the multireturn function and insert extract nodes into the expsresion list
                    multiret = multifunc
                    multiret.result = {} --table to link this result with extractors
                    for i,t in ipairs(multifunc.types) do
                        exps:insert(terra.newtree(multiret,{ kind = terra.kinds.extractreturn, index = (i-1), result = multiret.result, type = t}))
                    end
                end
            else
                local rv = checkrvalue(last)
                exps:insert(rv)
            end
        end
        
        local maxsize = #exps
        return terra.newtree(anchor, { kind = terra.kinds.parameterlist, parameters = exps, minsize = minsize, maxsize = maxsize, call = multiret })
    end
    local function insertcasts(typelist,paramlist) --typelist is a list of target types (or the value 'false'), paramlist is a parameter list that might have a multiple return value at the end
        if #typelist > paramlist.maxsize then
            terra.reporterror(ctx,paramlist,"expected at least "..#typelist.." parameters, but found only "..paramlist.maxsize)
        elseif #typelist < paramlist.minsize then
            terra.reporterror(ctx,paramlist,"expected no more than "..#typelist.." parameters, but found at least "..paramlist.minsize)
        end
        for i,typ in ipairs(typelist) do
            if typ and i <= paramlist.maxsize then
                paramlist.parameters[i] = insertcast(paramlist.parameters[i],typ)
            end
        end
        paramlist.size = #typelist
    end
    local function insertfunctionliteral(anchor,e)
        local fntyp = e:gettype(ctx)
        local typ = fntyp and terra.types.pointer(fntyp)
        return terra.newtree(anchor, { kind = terra.kinds.literal, value = e, type = typ })
    end
    
    function checkcall(exp, mustreturnatleast1)
        local function resolvefn(fn)
            if terra.isfunction(fn) then
                local tree = insertfunctionliteral(exp,fn)
                return tree,tree.type.type
            elseif terra.istree(fn) then
                if fn.type:ispointer() and fn.type.type:isfunction() then
                    return asrvalue(fn),fn.type.type
                else
                    terra.reporterror(ctx,exp,"expected a function but found ",fn.type)
                    return asrvalue(fn),terra.types.error
                end
            elseif fn == nil then
                terra.reporterror(ctx,exp,"call to undefined function")
                return nil,terra.types.error
            else
                error("NYI - check call on non-literal function calls")
            end
        end
        
        local fn,fntyp, paramlist
        if exp:is "method" then --desugar method a:b(c,d) call by first adding a to the arglist (a,c,d) and typechecking it
                                --then extract a's type from the parameter list and look in the method table for "b" 
            
            local reciever = checkexp(exp.value)
            local rawfn = reciever.type.methods[exp.name]
            fn,fntyp = resolvefn(rawfn)
            
            if fntyp ~= terra.types.error and fntyp.parameters[1] ~= nil then
            
                local rtyp = fntyp.parameters[1]
                local rexp = exp.value
                --TODO: should we also consider implicit conversions after the implicit address/dereference? or does it have to match exactly to work?
                local function mkunary(op) 
                    return terra.newtree(rexp, { kind = terra.kinds.operator, operator = terra.kinds[op], operands = terra.newlist{rexp} } )
                end
                if rtyp:ispointer() and rtyp.type == reciever.type then
                    --implicit address of
                    rexp = mkunary("&")
                elseif reciever.type:ispointer() and reciever.type.type == rtyp then
                    --implicit dereference
                    rexp = mkunary("@")
                end     
                                
                local arguments = terra.newlist()
                arguments:insert(rexp)
                for _,v in ipairs(exp.arguments) do
                    arguments:insert(v)
                end
                
                paramlist = checkparameterlist(exp,arguments)
            end
            
        else
            fn,fntyp = resolvefn(checkexpraw(exp.value))
            paramlist = checkparameterlist(exp,exp.arguments)
        end
    
        local typ = terra.types.error
        if fntyp ~= terra.types.error and paramlist ~= nil then
            insertcasts(fntyp.parameters,paramlist)
            if #fntyp.returns >= 1 then
                typ = fntyp.returns[1]
            elseif mustreturnatleast1 then
                terra.reporterror(ctx,exp,"expected call to return at least 1 value")
            end --otherwise this is used in statement context and does not require a type
        end
        return exp:copy { kind = terra.kinds.apply, arguments = paramlist,  value = fn, type = typ, types = fntyp.returns or terra.newlist() }
        
    end
    function asrvalue(ee)
        if ee.lvalue then
            return terra.newtree(ee,{ kind = terra.kinds.ltor, type = ee.type, expression = ee })
        else
            return ee
        end
    end
    function checkrvalue(e)
        local ee = checkexp(e)
        return asrvalue(ee)
    end
    
    function insertselect(v,field)
        local tree = terra.newtree(v, { type = terra.types.error, kind = terra.kinds.select, field = field, value = v, lvalue = v.lvalue })
        if v.type:isstruct() then
            local index = v.type.keytoindex[field]
            if index == nil then
                terra.reporterror(ctx,v,"no field ",field," in object")
            else
                tree.index = index
                tree.type = v.type.entries[index+1].type
            end
        else
            terra.reporterror(ctx,v,"expected a structural type")
        end
        return tree
    end
    
    function insertvar(anchor, typ, name, definition)
        return terra.newtree(anchor, { kind = terra.kinds["var"], type = typ, name = name, definition = definition, lvalue = true }) 
    end
    
    function checkexpraw(e) --can return raw lua objects, call checkexp to evaluate the expression and convert to terra literals
        
        local function resolveglobal(v) --attempt to treat the value as a terra global variable and return it as one if it is. Otherwise just pass the lua object through
            if terra.isglobalvar(v) then
                local typ = v:gettype(ctx) -- this will initialize the variable if it is not already
                return insertvar(e,typ,v.tree.name,v.tree)
            else
                return v
            end
        end
        if e:is "literal" then
            if e.type == "string" then --TODO: support string literals as terra type, rather than just return the string as a lua object
                return e.value
            else
                return e:copy { type = terra.types.primitive(e.type) }
            end
        elseif e:is "var" then
            local v = env[e.name]
            if v ~= nil then
                return e:copy { type = v.type, definition = v, lvalue = true }
            end
            v = self:env()[e.name]  
            if v ~= nil then
                return resolveglobal(v)
            else
                terra.reporterror(ctx,e,"variable '"..e.name.."' not found")
                return e:copy { type = terra.types.error }
            end
        elseif e:is "select" then
            local v = checkexpraw(e.value)
            if terra.istree(v) then
                
                if v.type:ispointer() then --allow 1 implicit dereference
                    v = insertdereference(v)
                end
                return insertselect(v,e.field)
            else
                local v = type(v) == "table" and v[e.field]
                if v ~= nil then
                    return resolveglobal(v)
                else
                    terra.reporterror(ctx,e,"no field ",e.field," in object")
                    return e:copy { type = terra.types.error }
                end
            end
        elseif e:is "operator" then
            local op_string = terra.kinds[e.operator]
            local op = operator_table[op_string]
            if op == nil then
                terra.reporterror(ctx,e,"operator ",op_string," not defined in terra code.")
                return e:copy { type = terra.types.error }
            else
                return op(e)
            end
        elseif e:is "identity" then --simply a passthrough
            local ee = checkexpraw(e.value)
            if terra.istree(ee) then
                return e:copy { type = ee.type, value = ee }
            else
                return ee
            end
        elseif e:is "apply" or e:is "method" then
            return checkcall(e,true)
        elseif e:is "constructor" then
            local typ = terra.types.newemptystruct {}
            local entries = terra.newlist()
            for i,f in ipairs(e.records) do
                local k = nil
                if f.key then
                    k = checkexpraw(f.key)
                    if type(k) ~= "string" then
                        terra.reporterror(ctx,e,"expected string but found ",type(k))
                        k = "<error>"
                    end
                end
                local v = checkrvalue(f.value)
                if not typ:addentry(k,v.type) then
                    terra.reporterror(ctx,e," duplicate key ",k," in struct constructor")
                end
                
                entries:insert( f:copy { key = k, value = v } )
            end
            return e:copy { records = entries, type = terra.types.canonicalanonstruct(typ) }
        end
        error("NYI - expression "..terra.kinds[e.kind],2)
    end
    function checkexp(ee)
        local e = checkexpraw(ee)
        if terra.istree(e) then
            return e
        elseif type(e) == "number" then
            return terra.newtree(ee, { kind = terra.kinds.literal, value = e, type = double })
        elseif type(e) == "boolean" then
            return terra.newtree(ee, { kind = terra.kinds.literal, value = e, type = bool })
        elseif terra.isfunction(e) then
            return insertfunctionliteral(ee,e)
        else
            terra.reporterror(ctx,ee, "expected a terra expression but found "..type(e))
            return ee:copy { type = terra.types.error }
        end
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


    function checkstmt(s)
        if s:is "block" then
            enterblock()
            local r = s.statements:map(checkstmt)
            leaveblock()
            return s:copy {statements = r}
        elseif s:is "return" then
            local rstmt = s:copy { expressions = checkparameterlist(s,s.expressions) }
            return_stmts:insert( rstmt )
            return rstmt
        elseif s:is "label" then
            local lbls = labels[s.value] or terra.newlist()
            if terra.istree(lbls) then
                terra.reporterror(ctx,s,"label defined twice")
                terra.reporterror(ctx,lbls,"previous definition here")
            else
                for _,v in ipairs(lbls) do
                    v.definition = s
                end
            end
            labels[s.value] = s
            return s
        elseif s:is "goto" then
            local lbls = labels[s.label] or terra.newlist()
            if terra.istree(lbls) then
                s.definition = lbls
            else
                lbls:insert(s)
            end
            labels[s.label] = lbls
            return s 
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
            enterblock() --we don't use block here because, unlike while loops, the condition needs to be checked in the scope of the loop
            local new_blk = s.body:copy { statements = s.body.statements:map(checkstmt) }
            local e = checkexptyp(s.condition,bool)
            leaveblock()
            leaveloop()
            return s:copy { body = new_blk, condition = e, breaktable = breaktable }
        elseif s:is "defvar" then
            local lhs = terra.newlist()
            local res
            if s.initializers then
                local params = checkparameterlist(s,s.initializers)
                
                local vtypes = terra.newlist()
                for i,v in ipairs(s.variables) do
                    local typ = false
                    if v.type then
                        typ = resolvetype(v.type)
                    end
                    vtypes:insert(typ)
                end
                
                insertcasts(vtypes,params)
                
                for i,v in ipairs(s.variables) do
                    lhs:insert(v:copy { type = (params.parameters[i] and params.parameters[i].type) or terra.types.error }) 
                end
                
                res = s:copy { variables = lhs, initializers = params }
            else
                for i,v in ipairs(s.variables) do
                    local typ = terra.types.error
                    if not v.type then
                        terra.reporterror(ctx,v,"type must be specified for unitialized variables")
                    else
                        typ = resolvetype(v.type)
                    end
                    lhs:insert(v:copy { type = typ })
                end
                res = s:copy { variables = lhs }
            end     
            --add the variables to current environment 
            --unless they are global variables (which are resolved through lua's env)
            if not s.isglobal then
                for i,v in ipairs(lhs) do
                    env[v.name] = v
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
                    lst:insert( terra.newtree(s,{ kind = terra.kinds.entry, name = v }) )
                end
                return lst
            end
            
            function mkvar(a)
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
                variables = mkdefs(s.varname,"<limit>","<step>");
                initializers = terra.newlist({s.initial,s.limit,s.step})
            })
            
            local lt = mkop("<",s.varname,"<limit>")
            
            local newstmts = terra.newlist()
            for _,v in pairs(s.body.statements) do
                newstmts:insert(v)
            end
            
            local p1 = mkop("+",s.varname,"<step>")
            local as = terra.newtree(s, {
                kind = terra.kinds.assignment;
                lhs = terra.newlist({mkvar(s.varname)});
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
            desugared:printraw()
            return checkstmt(desugared)
        elseif s:is "apply" or s:is "method" then
            return checkcall(s,false) --allowed to be void
        else 
            return checkrvalue(s)
        end
        error("NYI - "..terra.kinds[s.kind],2)
    end
    
    local result = checkstmt(ftree.body)
    for _,v in pairs(labels) do
        if not terra.istree(v) then
            terra.reporterror(ctx,v[1],"goto to undefined label")
        end
    end
    
    
    print("Return Stmts:")
    
    
    local return_types
    if ftree.return_types then --take the return types to be as specified
        return_types = ftree.return_types:map(resolvetype)
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
    
    print("TypedTree")
    typedtree:printraw()
    
    ctx:pop()
    
    self.iscompiling = nil
    return typedtree
    
    --[[
    
    2. register the parameter list as a variant of this function (ensure it is unique) and create table to hold the result of type checking
    5. typecheck statement list, start with (done)
       -- arithmetic and logical operators on simple number types (no casting)
       -- if and while statements
       -- var statements (multiple cases)
       -- assignment statements  (multiple cases)
       -- return statements
       -- literals
       -- lua partial evaluation + lua numeric literals
       next:
       -- function calls (and recursive function compilation)
       -- correct multiple return value in assignments
       -- implicit arithmetic conversions
       -- pointer types 
       -- structured types
       -- macros (no hygiene)
       -- numeric for loop
       -- iterator loop
       make sure to track lvalues for all typed expressions
       
handling multi-returns:
checkparameterlist function:
         checks a list of expressions where the last one may be a function call with multiple returns
         generates an object that has the list of typed (single value) expressions, and
         an optional multi-valued (2+ values) return function (single value returns can go in expression list)
         the return values from the multi-function are placed in a (seperate?) list with a type, a reference to the
         function call that generated them and then their index into the argument list
         
         function calls found during a checkexp will just return their first (if any) value, or a special void type that cannot
         be cast/operated on by anything else
         
         codegen will need to handle two cases:
         1. function truncated to 0 or 1 and return value (NULL if 0)
         2. multi-return function (2+ arguments) return pointer to structure holding the return values
    ]]
end
io.write("done\n")
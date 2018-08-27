-- See Copyright Notice in ../LICENSE.txt
local ffi = require("ffi")
local asdl = require("asdl")
local List = asdl.List

-- LINE COVERAGE INFORMATION, must run test script with luajit and not terra to avoid overwriting coverage with old version
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
        if info.short_src:match("terralib%.lua") then
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

setmetatable(terra.kinds, { __index = function(self,idx)
    error("unknown kind accessed: "..tostring(idx))
end })

local T = asdl.NewContext()

T:Extern("TypeOrLuaExpression", function(t) return T.Type:isclassof(t) or T.luaexpression:isclassof(t) end)
T:Define [[
ident =     escapedident(luaexpression expression) # removed during specialization
          | namedident(string value)
          | labelident(Label value)

field = recfield(ident key, tree value)
      | listfield(tree value)
      
structbody = structentry(string key, luaexpression type)
           | structlist(structbody* entries)

param = unevaluatedparam(ident name, luaexpression? type)
      | concreteparam(Type? type, string name, Symbol symbol,boolean isnamed)

structdef = (luaexpression? metatype, structlist records)

attr = (boolean nontemporal, number? alignment, boolean isvolatile)
Symbol = (Type type, string displayname, number id)
Label = (string displayname, number id)
tree = 
     # trees that are introduced in parsing and are ...
     # removed during specialization
       luaexpression(function expression, boolean isexpression)
     # removed during typechecking
     | constructoru(field* records) #untyped version
     | selectu(tree value, ident field) #untyped version
     | method(tree value,ident name,tree* arguments) 
     | statlist(tree* statements)
     | fornumu(param variable, tree initial, tree limit, tree? step,block body) #untyped version
     | defvar(param* variables,  boolean hasinit, tree* initializers)
     | forlist(param* variables, tree iterator, block body)
     | functiondefu(param* parameters, boolean is_varargs, TypeOrLuaExpression? returntype, block body)
     
     # introduced temporarily during specialization/typing, but removed after typing
     | luaobject(any value)
     | setteru(function setter) # temporary node introduced and removed during typechecking to handle __update and __setfield
     | quote(tree tree)
     # trees that exist after typechecking and handled by the backend:
     | var(string name, Symbol? symbol) #symbol is added during specialization
     | literal(any? value, Type type)
     | index(tree value,tree index)
     | apply(tree value, tree* arguments)
     | letin(tree* statements, tree* expressions, boolean hasstatements)
     | operator(string operator, tree* operands)
     | block(tree* statements)
     | assignment(tree* lhs,tree* rhs)
     | gotostat(ident label)
     | breakstat()
     | label(ident label)
     | whilestat(tree condition, block body)
     | repeatstat(tree* statements, tree condition)
     | fornum(allocvar variable, tree initial, tree limit, tree? step, block body)
     | ifstat(ifbranch* branches, block? orelse)
     | defer(tree expression)
     | select(tree value, number index, string fieldname) # typed version, fieldname for debugging
     | globalvalueref(string name, globalvalue value)
     | constant(cdata value, Type type)
     | attrstore(tree address, tree value, attr attrs)
     | attrload(tree address, attr attrs)
     | debuginfo(string customfilename, number customlinenumber)
     | arrayconstructor(Type? oftype,tree* expressions)
     | vectorconstructor(Type? oftype,tree* expressions)
     | sizeof(Type oftype)
     | inlineasm(Type type, string asm, boolean volatile, string constraints, tree* arguments)
     | cast(Type to, tree expression)
     | allocvar(string name, Symbol symbol)
     | structcast(allocvar structvariable, tree expression, storelocation* entries)
     | constructor(tree* expressions)
     | returnstat(tree expression)
     | setter(allocvar rhs, tree setter) # handles custom assignment behavior, real rhs is first stored in 'rhs' and then the 'setter' expression uses it
     
     # special purpose nodes, they only occur in specific locations, but are considered trees because they can contain typed trees
     | ifbranch(tree condition, block body)
     | storelocation(number index, tree value) # for struct cast, value uses structvariable

Type = primitive(string type, number bytes, boolean signed)
     | pointer(Type type, number addressspace) unique
     | vector(Type type, number N) unique
     | array(Type type, number N) unique
     | functype(Type* parameters, Type returntype, boolean isvararg) unique
     | struct(string name)
     | niltype #the type of the singleton nil (implicitly convertable to any pointer type)
     | opaque #an type of unknown layout used with a pointer (&opaque) to point to data of an unknown type (i.e. void*)
     | error #used in compiler to squelch errors
     | luaobjecttype #type of expressions that hold temporary luaobjects in the compiler, removed during typechecking

labelstate = undefinedlabel(gotostat * gotos, table* positions) #undefined label with gotos pointing to it
           | definedlabel(table position, label label) #defined label with position and label object defining it

definition = functiondef(string? name, functype type, allocvar* parameters, boolean is_varargs, block body, table labeldepths, globalvalue* globalsused)
           | functionextern(string? name, functype type)
     
globalvalue = terrafunction(definition? definition)
            | globalvariable(tree? initializer, number addressspace, boolean extern, boolean constant)
            attributes(string name, Type type, table anchor)
            
overloadedterrafunction = (string name, terrafunction* definitions)
]]
terra.irtypes = T

T.var.lvalue = true

function T.allocvar:settype(typ)
    assert(T.Type:isclassof(typ))
    self.type, self.symbol.type = typ,typ
end

-- temporary until we replace with asdl
local tokens = setmetatable({},{__index = function(self,idx) return idx end })

terra.isverbose = 0 --set by C api

local function dbprint(level,...) 
    if terra.isverbose >= level then
        print(...)
    end
end
local function dbprintraw(level,obj)
    if terra.isverbose >= level then
        terra.printraw(obj)
    end
end

--debug wrapper around cdef function to print out all the things being defined
local oldcdef = ffi.cdef
ffi.cdef = function(...)
    dbprint(2,...)
    return oldcdef(...)
end

-- TREE
function T.tree:is(value)
    return self.kind == value
end
 
function terra.printraw(self)
    local function header(t)
        local mt = getmetatable(t)
        if type(t) == "table" and mt and type(mt.__fields) == "table" then
            return t.kind or tostring(mt)
        else return tostring(t) end
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
                local prefix
                if type(k) == "table" and not terra.issymbol(k) then
                    prefix = ("<table (mt = %s)>"):format(tostring(getmetatable(k)))
                else
                    prefix = tostring(k)
                end
                if k ~= "kind" and k ~= "offset" then
                    prefix = spacing..prefix..": "
                    if terra.types.istype(v) then --dont print the raw form of types unless printraw was called directly on the type
                        print(prefix..tostring(v))
                    else
                        print(prefix..header(v))
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
    print(header(self))
    if type(self) == "table" then
        printElem(self,"  ")
    end
end
local prettystring --like printraw, but with syntax formatting rather than as raw lsits

local function newobject(ref,ctor,...) -- create a new object, copying the line/file info from the reference
    assert(ref.linenumber and ref.filename, "not a anchored object?")
    local r = ctor(...)
    r.linenumber,r.filename,r.offset = ref.linenumber,ref.filename,ref.offset
    return r
end

local function copyobject(ref,newfields) -- copy an object, extracting any new replacement fields from newfields table
    local class = getmetatable(ref)
    local fields = class.__fields
    assert(fields,"not a asdl object?")
    local function handlefield(i,...) -- need to do this with tail recursion rather than a loop to handle nil values
        if i == 0 then
            return newobject(ref,class,...)
        else
            local f = fields[i]
            local a = newfields[f.name] or ref[f.name]
            newfields[f.name] = nil
            return handlefield(i-1,a,...)
        end
    end
    local r = handlefield(#fields)
    for k,v in pairs(newfields) do
        error("unused field in copy: "..tostring(k))
    end
    return r
end
T.tree.copy = copyobject --support :copy directly on objects
function T.tree:aserror() -- a copy of this tree with an error type, used when unable to return a real value
    return self:copy{}:withtype(terra.types.error)
end

function terra.newanchor(depth)
    local info = debug.getinfo(1 + depth,"Sl")
    local body = { linenumber = info and info.currentline or 0, filename = info and info.short_src or "unknown" }
    return setmetatable(body,terra.tree)
end

function terra.istree(v) 
    return T.tree:isclassof(v)
end

-- END TREE

local function mkstring(self,begin,sep,finish)
    return begin..table.concat(self:map(tostring),sep)..finish
end
terra.newlist = List
function terra.islist(l) return List:isclassof(l) end


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

local diagcache = setmetatable({},{ __mode = "v" })
local function formaterror(anchor,...)
    if not anchor or not anchor.filename or not anchor.linenumber then
        error("nil anchor")
    end
    local errlist = List()
    errlist:insert(anchor.filename..":"..anchor.linenumber..": ")
    for i = 1,select("#",...) do errlist:insert(tostring(select(i,...))) end
    errlist:insert("\n")
    if not anchor.offset then 
        return errlist:concat()
    end
    
    local filename = anchor.filename
    local filetext = diagcache[filename] 
    if not filetext then
        local file = io.open(filename,"r")
        if file then
            filetext = file:read("*all")
            diagcache[filename] = filetext
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
        local line = filetext:sub(begin,finish) 
        errlist:insert(line)
        errlist:insert("\n")
        for i = begin,anchor.offset do
            errlist:insert((filetext:byte(i) == TAB and "\t") or " ")
        end
        errlist:insert("^\n")
    end
    return errlist:concat()
end
local function erroratlocation(anchor,...)
    error(formaterror(anchor,...),0)
end

terra.diagnostics.source = {}
function terra.diagnostics:reporterror(anchor,...)
    --erroratlocation(anchor,...) -- early error for debugging
    self.errors:insert(formaterror(anchor,...))
end

function terra.diagnostics:haserrors()
    return #self.errors > 0
end

function terra.diagnostics:finishandabortiferrors(msg,depth)
    if #self.errors > 0 then
        error(msg.."\n"..self.errors:concat(),depth+1)
    end
end

function terra.newdiagnostics()
    return setmetatable({ errors = List() },terra.diagnostics)
end

-- END DIAGNOSTICS

-- CUSTOM TRACEBACK

local TRACEBACK_LEVELS1 = 12
local TRACEBACK_LEVELS2 = 10
local function findfirstnilstackframe() --because stack size is not exposed we binary search for it
    local low,high = 1,1
    while debug.getinfo(high,"") ~= nil do
        low,high = high,high*2
    end --invariant: low is non-nil frame, high is nil frame, range gets smaller each iteration
    while low + 1 ~= high do
        local m = math.floor((low+high)/2)
        if debug.getinfo(m,"") ~= nil then
            low = m
        else
            high = m
        end
    end
    return high - 1 --don't count ourselves
end

--all calls to user-defined functions from the compiler go through this wrapper
local function invokeuserfunction(anchor, what, speculate, userfn,  ...)
    if not speculate then
        local result = userfn(...)
        -- invokeuserfunction is recognized by a customtraceback and we need to prevent the tail call
        return result
    end
    local success,result = xpcall(userfn,debug.traceback,...)
    -- same here
    return success, result
end
terra.fulltrace = false
-- override the lua traceback function to be aware of Terra compilation contexts
function debug.traceback(msg,level)
    level = level or 1
    level = level + 1 -- don't count ourselves
    local lim = terra.fulltrace and math.huge or TRACEBACK_LEVELS1 + 1
    local lines = List()
    if msg then
        local file,outsideline,insideline,rest = msg:match "^$terra$(.*)$terra$(%d+):(%d+):(.*)"
        if file then
            msg = ("%s:%d:%s"):format(file,outsideline+insideline-1,rest)
        end
        lines:insert(("%s\n"):format(msg))
    end
    lines:insert("stack traceback:")
    while true do
        local di = debug.getinfo(level,"Snlf")
        if not di then break end
        if di.func == invokeuserfunction then
            local anchorname,anchor = debug.getlocal(level,1)
            local whatname,what = debug.getlocal(level,2)
            assert(anchorname == "anchor" and whatname == "what")
            lines:insert("\n\t")
            lines:insert(formaterror(anchor,"Errors reported during "..what):sub(1,-2)) 
        else
            local short_src,currentline,linedefined = di.short_src,di.currentline,di.linedefined
            local file,outsideline = di.source:match("^@$terra$(.*)$terra$(%d+)$")
            if file then
                short_src = file
                currentline = currentline and (currentline + outsideline - 1)
                linedefined = linedefined and (linedefined + outsideline - 1)
            end
            lines:insert(("\n\t%s:"):format(short_src))
            if di.currentline and di.currentline >= 0 then
                lines:insert(("%d:"):format(currentline))
            end
            if di.namewhat ~= "" then
                lines:insert((" in function '%s'"):format(di.name))
            elseif di.what == "main" then
                lines:insert(" in main chunk")
            elseif di.what == "C" then
                lines:insert( (" at %s"):format(tostring(di.func)))    
            else
                lines:insert((" in function <%s:%d>"):format(short_src,linedefined))
            end
        end
        level = level + 1
        if level == lim then
            if debug.getinfo(level + TRACEBACK_LEVELS2,"") ~= nil then
                lines:insert("\n\t...")
                level = findfirstnilstackframe() - TRACEBACK_LEVELS2
            end
            lim = math.huge
        end
    end
    return table.concat(lines)
end

-- GLOBALVALUE

function T.globalvalue:gettype() return self.type end
function T.globalvalue:getname() return self.name end
function T.globalvalue:setname(name) self.name = tostring(name) return self end

local function readytocompile(root)
    local visited = {}
    local function visit(gv)
        if visited[gv] or gv.readytocompile then return end
        visited[gv] = true
        if gv.kind == "terrafunction" then
            if not gv:isdefined() then
                erroratlocation(gv.anchor,"function "..gv:getname().." is not defined.")
            end
            gv.type:completefunction()
            if gv.definition.kind == "functiondef" then
                for i,g in ipairs(gv.definition.globalsused) do
                    visit(g)
                end
            end
        elseif gv.kind == "globalvariable" then
            gv.type:complete()
        else error("unknown gv:"..tostring(gv)) end
    end
    visit(root)
    -- if we succeeded, we can mark all the globals we visited ready, so they don't have to recompute this
    for g,_ in pairs(visited) do
        g.readytocompile = true
    end
end
function T.globalvalue:checkreadytocompile()
    if not self.readytocompile then
        readytocompile(self)
    end
end
function T.globalvalue:compile()
    if not self.rawjitptr then
        self.stats = self.stats or {}
        self.rawjitptr,self.stats.jit = terra.jitcompilationunit:jitvalue(self)
    end
    return self.rawjitptr
end
function T.globalvalue:getpointer()
    if not self.ffiwrapper then
        local rawptr = self:compile()
        self.ffiwrapper = ffi.cast(terra.types.pointer(self.type):cstring(),rawptr)
    end
    return self.ffiwrapper
end

-- TERRAFUNCTION
function T.terrafunction:__call(...)
    local ffiwrapper = self:getpointer()
    return ffiwrapper(...)
end
function T.terrafunction:setinlined(v)
    assert(self:isdefined(), "attempting to set the inlining state of an undefined function")
    self.definition.alwaysinline = not not v
    assert(not (self.definition.alwaysinline and self.definition.dontoptimize),
           "setinlined(true) and setoptimized(false) are incompatible")
end
function T.terrafunction:setoptimized(v)
    assert(self:isdefined(), "attempting to set the optimization state of an undefined function")
    self.definition.dontoptimize = not v
    assert(not (self.definition.alwaysinline and self.definition.dontoptimize),
           "setinlined(true) and setoptimized(false) are incompatible")
end
function T.terrafunction:disas()
    print("definition ", self:gettype())
    terra.disassemble(terra.jitcompilationunit:addvalue(self),self:compile())
end
function T.terrafunction:printstats()
    print("definition ", self:gettype())
    for k,v in pairs(self.stats) do
        print("",k,v)
    end
end
function T.terrafunction:isextern() return self.definition and self.definition.kind == "functionextern" end
function T.terrafunction:isdefined() return self.definition ~= nil end
function T.terrafunction:setname(name) 
    self.name = tostring(name) 
    if self.definition then self.definition.name = name end
    return self
end

function T.terrafunction:adddefinition(functiondef)
    if self.definition then error("terra function "..self.name.." already defined") end
    self:resetdefinition(functiondef)
end
function T.terrafunction:resetdefinition(functiondef)
    if T.terrafunction:isclassof(functiondef) and functiondef:isdefined() then 
        functiondef = functiondef.definition
    end
    assert(T.definition:isclassof(functiondef), "expected a defined terra function")
    if self.readytocompile then error("cannot reset a definition of function that has already been compiled",2) end
    if self.type ~= functiondef.type and self.type ~= terra.types.placeholderfunction then 
        error(("attempting to define terra function declaration with type %s with a terra function definition of type %s"):format(tostring(self.type),tostring(functiondef.type)))
    end
    self.definition,self.type,functiondef.name = functiondef,functiondef.type,assert(self.name)
end
function T.terrafunction:gettype(nop)
    assert(nop == nil, ":gettype no longer takes any callbacks for when a function is complete")
    if self.type == terra.types.placeholderfunction then 
        error("function being recursively referenced needs an explicit return type, function defintion at: "..formaterror(self.anchor,""),2)
    end
    return self.type
end

function terra.isfunction(obj)
    return T.terrafunction:isclassof(obj)
end
-- END FUNCTION

function terra.isoverloadedfunction(obj) return T.overloadedterrafunction:isclassof(obj) end
function T.overloadedterrafunction:adddefinition(d)
    assert(T.terrafunction:isclassof(d),"expected a terra function")
    d:setname(self.name)
    self.definitions:insert(d)
    return self
end
function T.overloadedterrafunction:getdefinitions() return self.definitions end
function terra.overloadedfunction(name, init)
    init = init or {}
    return T.overloadedterrafunction(name,List{unpack(init)})
end

-- GLOBALVAR

function terra.isglobalvar(obj)
    return T.globalvariable:isclassof(obj)
end
function T.globalvariable:init()
    self.symbol = terra.newsymbol(self.type,self.name)
end
function T.globalvariable:isextern() return self.extern end
function T.globalvariable:isconstant() return self.constant end

local typecheck
local function constantcheck(e,checklvalue)
    local kind = e.kind
    if "literal" == kind or "constant" == kind or "sizeof" == kind then -- trivially ok
    elseif "index" == kind and checklvalue then
        constantcheck(e.value,true)
        constantcheck(e.index)
    elseif "operator" == kind then
        local op = e.operator
        if "@" == op then
            constantcheck(e.operands[1])
            if not checklvalue then
                erroratlocation(e,"non-constant result of dereference used as a constant initializer")
            end
        elseif "&" == op then
            constantcheck(e.operands[1],true)
        else
            for _,ee in ipairs(e.operands) do constantcheck(ee) end
        end
    elseif "select" == kind then
        constantcheck(e.value,checklvalue)
    elseif "globalvalueref" == kind then
        if e.value.kind == "globalvariable" and not (e.value:isconstant() or checklvalue) then
            erroratlocation(e,"non-constant use of global variable used as a constant initializer")
        end
    elseif "arrayconstructor" == kind or "vectorconstructor" == kind then
        for _,ee in ipairs(e.expressions) do constantcheck(ee) end
    elseif "cast" == kind then
        if e.expression.type:isarray() then
            if checklvalue then
                constantcheck(e.expression,true)
            else 
                erroratlocation(e,"non-constant cast of array to pointer used as a constant initializer")
            end
        else constantcheck(e.expression) end
    elseif "structcast" == kind then
        constantcheck(e.expression)
    elseif "constructor" == kind then
        for _,ee in ipairs(e.expressions) do constantcheck(ee) end
    else
        erroratlocation(e,"non-constant expression being used as a constant initializer")
    end
    return e 
end

local function createglobalinitializer(anchor, typ, c)
    if not c then return nil end
    if not T.quote:isclassof(c) then
        local c_ = c
        c = newobject(anchor,T.luaexpression,function() return c_ end,true)
    end
    if typ then
        c = newobject(anchor, T.cast, typ, c)
    end
    return constantcheck(typecheck(c))
end
function terra.global(...)
    local typ = select(1,...)
    typ = terra.types.istype(typ) and typ or nil
    local c,name,isextern,isconstant,addressspace = select(typ and 2 or 1,...)
    local anchor = terra.newanchor(2)
    c = createglobalinitializer(anchor,typ,c)
    if not typ then --set type if not set
        if not c then
            error("type must be specified for globals without an initializer",2)
        end
        typ = c.type
    end
    return T.globalvariable(c,tonumber(addressspace) or 0, isextern or false, isconstant or false, name or "<global>", typ, anchor)
end
function T.globalvariable:setinitializer(init)
    if self.readytocompile then error("cannot change global variable initializer after it has been compiled.",2) end
    self.initializer = createglobalinitializer(self.anchor,self.type,init)
end
function T.globalvariable:get()
    local ptr = self:getpointer()
    return ptr[0]
end
function T.globalvariable:set(v)
    local ptr = self:getpointer()
    ptr[0] = v
end
function T.globalvariable:__tostring()
    local kind = self:isconstant() and "constant" or "global"
    local extern = self:isextern() and "extern " or ""
    local r = ("%s%s %s : %s"):format(extern,kind,self.name,tostring(self.type))
    if self.initializer then
        r = ("%s = %s"):format(r,prettystring(self.initializer,false))
    end
    return r
end
-- END GLOBALVAR

-- TARGET
local weakkeys = { __mode = "k" }
local function newweakkeytable()
    return setmetatable({},weakkeys)
end

local function cdatawithdestructor(ud,dest)
    local cd = ffi.cast("void*",ud)
    ffi.gc(cd,dest)
    return cd
end

terra.target = {}
terra.target.__index = terra.target
function terra.istarget(a) return getmetatable(a) == terra.target end
function terra.newtarget(tbl)
    if not type(tbl) == "table" then error("expected a table",2) end
    local Triple,CPU,Features,FloatABIHard = tbl.Triple,tbl.CPU,tbl.Features,tbl.FloatABIHard
    if Triple then
        CPU = CPU or ""
        Features = Features or ""
    end
    return setmetatable({ llvm_target = cdatawithdestructor(terra.inittarget(Triple,CPU,Features,FloatABIHard),terra.freetarget),
                          Triple = Triple,
                          cnametostruct = { general = {}, tagged = {}}  --map from llvm_name -> terra type used to make c structs unique per llvm_name
                        },terra.target)
end
function terra.target:getorcreatecstruct(displayname,tagged)
    local namespace
    if displayname ~= "" then
        namespace = tagged and self.cnametostruct.tagged or self.cnametostruct.general
    end
    local typ = namespace and namespace[displayname]
    if not typ then
        typ = terra.types.newstruct(displayname == "" and "anon" or displayname)
        typ.undefined = true
        if namespace then namespace[displayname] = typ end
    end
    return typ
end

-- COMPILATION UNIT
local compilationunit = {}
compilationunit.__index = compilationunit
function terra.newcompilationunit(target,opt)
    assert(terra.istarget(target),"expected a target object")
    return setmetatable({ symbols = newweakkeytable(), 
                          collectfunctions = opt,
                          llvm_cu = cdatawithdestructor(terra.initcompilationunit(target.llvm_target,opt),terra.freecompilationunit) },compilationunit) -- mapping from Types,Functions,Globals,Constants -> llvm value associated with them for this compilation
end
function compilationunit:addvalue(k,v)
    if type(k) ~= "string" then k,v = nil,k end
    v:checkreadytocompile()
    return terra.compilationunitaddvalue(self,k,v)
end
function compilationunit:jitvalue(v)
    local gv = self:addvalue(v)
    return terra.jit(self.llvm_cu,gv)
end
function compilationunit:free()
    assert(not self.collectfunctions, "cannot explicitly release a compilation unit with auto-delete functions")
    ffi.gc(self.llvm_cu,nil) --unregister normal destructor object
    terra.freecompilationunit(self.llvm_cu)
end
function compilationunit:dump() terra.dumpmodule(self.llvm_cu) end

terra.nativetarget = terra.newtarget {}
terra.cudatarget = terra.newtarget {Triple = 'nvptx64-nvidia-cuda', FloatABIHard = true}
terra.jitcompilationunit = terra.newcompilationunit(terra.nativetarget,true) -- compilation unit used for JIT compilation, will eventually specify the native architecture

terra.llvm_gcdebugmetatable = { __gc = function(obj)
    print("GC IS CALLED")
end }



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
function terra.isquote(t)
    return T.quote:isclassof(t)
end
function T.quote:astype()
    if not self.tree:is "luaobject" or not T.Type:isclassof(self.tree.value) then
        error("quoted value is not a type")
    end
    return self.tree.value
end
function T.quote:isluaobject() return self.tree.type == T.luaobjecttype end
function T.quote:gettype() return self.tree.type end
function T.quote:islvalue() return not not self.tree.lvalue end
function T.quote:asvalue()
    local function getvalue(e)
        if e:is "literal" then
            if type(e.value) == "userdata" then
                return tonumber(ffi.cast("uint64_t *",e.value)[0])
            else
                return e.value
            end
        elseif e:is "globalvalueref" then return e.value
        elseif e:is "constant" then
            return tonumber(e.value) or e.value or error("no value?")
        elseif e:is "constructor" then
            local t,typ = {},e.type
            for i,r in ipairs(typ:getentries()) do
                local v,e = getvalue(e.expressions[i]) 
                if e then return nil,e end
                local key = typ.convertible == "tuple" and i or r.field
                t[key] = v
            end
            return t
        elseif e:is "var" then return e.symbol
        elseif e:is "luaobject" then
             return e.value
        else
            local runconstantprop = function()
                return terra.constant(self):get()
            end
            local status,value  = pcall(runconstantprop)
            if not status then
                return nil, "not a constant value (note: :asvalue() isn't implement for all constants yet), error propagating constant was: "..tostring(value)
            end
            return value
        end
    end
    return getvalue(self.tree)
end
function T.quote:init()
    assert(T.Type:isclassof(self.tree.type), "quote tree must have a type")
end
function terra.newquote(tree) return newobject(tree,T.quote,tree) end
-- END QUOTE


local identcount = 0
-- SYMBOL
function terra.issymbol(s)
    return T.Symbol:isclassof(s)
end

function terra.newsymbol(typ,displayname)
    if not terra.types.istype(typ) then error("symbol requires a Terra type but found "..terra.type(typ).." (use label() for goto labels,method names, and field names)") end
    displayname = displayname or tostring(identcount)
    local r = T.Symbol(typ,displayname,identcount)
    identcount = identcount + 1
    return r
end

function T.Symbol:__tostring()
    return "$"..self.displayname
end
function T.Symbol:tocname() return "__symbol"..tostring(self.id) end

_G["symbol"] = terra.newsymbol 

-- LABEL
function terra.islabel(l) return T.Label:isclassof(l) end
function T.Label:__tostring() return "$"..self.displayname end
function terra.newlabel(displayname)
    displayname = displayname or tostring(identcount)
    local r = T.Label(displayname,identcount)
    identcount = identcount + 1
    return r
end
function T.Label:tocname() return "__label_"..tostring(self.id) end
_G["label"] = terra.newlabel

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
    local function intrinsiccall(diag,e,...)
        local args = terra.newlist {...}
        local types = args:map("gettype")
        local name,intrinsictype = typefn(types)
        if type(name) ~= "string" then
            diag:reporterror(e,"expected an intrinsic name but found ",terra.type(name))
            name = "<unknownintrinsic>"
        elseif intrinsictype == terra.types.error then
            diag:reporterror(e,"intrinsic ",name," does not support arguments: ",unpack(types))
            intrinsictype = terra.types.funcpointer(types,{})
        elseif not terra.types.istype(intrinsictype) or not intrinsictype:ispointertofunction() then
            diag:reporterror(e,"expected intrinsic to resolve to a function type but found ",terra.type(intrinsictype))
            intrinsictype = terra.types.funcpointer(types,{})
        end
        local fn = terralib.externfunction(name,intrinsictype,e)
        local fnref = newobject(e,T.luaexpression,function() return fn end,true)
        return typecheck(newobject(e,T.apply,fnref,args))
    end
    return terra.internalmacro(intrinsiccall)
end

terra.asm = terra.internalmacro(function(diag,tree,returntype, asm, constraints,volatile,...)
    local args = List{...}
    return typecheck(newobject(tree, T.inlineasm,returntype:astype(), tostring(asm:asvalue()), not not volatile:asvalue(), tostring(constraints:asvalue()), args))
end)
    

local evalluaexpression
-- CONSTRUCTORS
local function layoutstruct(st,tree,env)
    if st.tree then
        local msg = formaterror(tree,"attempting to redefine struct")..formaterror(st.tree,"previous definition was here")
        error(msg,0)
    end
    st.undefined = nil

    local function getstructentry(v) assert(v.kind == "structentry")
        local resolvedtype = evalluaexpression(env,v.type)
        if not terra.types.istype(resolvedtype) then
            erroratlocation(v,"lua expression is not a terra type but ", terra.type(resolvedtype))
        end
        return { field = v.key, type = resolvedtype }
    end
    
    local function getrecords(records)
        return records:map(function(v)
            if v.kind == "structlist" then
                return getrecords(v.entries)
            else
                return getstructentry(v)
            end
        end)
    end
    local metatype = tree.metatype and evalluaexpression(env,tree.metatype)
    st.entries = getrecords(tree.records.entries)
    st.tree = tree --to track whether the struct has already beend defined
                   --we keep the tree to improve error reporting
    st.anchor = tree --replace the anchor generated by newstruct with this struct definition
                     --this will cause errors on the type to be reported at the definition
    if metatype then
        invokeuserfunction(tree,"invoking metatype function",false,metatype,st)
    end
end
local function desugarmethoddefinition(newtree,receiver)
    local pointerto = terra.types.pointer
    local addressof = newobject(newtree,T.luaexpression,function() return pointerto(receiver) end,true)
    local sym = newobject(newtree,T.namedident,"self")
    local implicitparam = newobject(newtree,T.unevaluatedparam,sym,addressof)
    --add the implicit parameter to the parameter list
    local newparameters = List{implicitparam}
    newparameters:insertall(newtree.parameters)
    return copyobject(newtree,{ parameters = newparameters})
end

local evaluateparameterlist,evaltype

local function evalformalparameters(diag,env,tree)
    return copyobject(tree, { parameters = evaluateparameterlist(diag,env,tree.parameters,true),
                              returntype = tree.returntype and evaltype(diag,env,tree.returntype) })
end

function terra.defineobjects(fmt,envfn,...)
    local cmds = terralib.newlist()
    local nargs = 2
    for i = 1, #fmt do --collect declaration/definition commands
        local c = fmt:sub(i,i)
        local name,tree = select(2*i - 1,...)
        cmds:insert { c = c, name = name, tree = tree }
    end
    local env = setmetatable({},{__index = envfn()})
    local function paccess(name,d,t,k,v)
        local s,r = pcall(function()
            if v then t[k] = v
            else return t[k] end
        end)
        if not s then
            error("failed attempting to index field '"..k.."' in name '"..name.."' (expected a table but found "..terra.type(t)..")" ,d)
        end
        return r
    end
    local function enclosing(name)
        local t = env
        for m in name:gmatch("([^.]*)%.") do
            t = paccess(name,4,t,m)
        end
        return t,name:match("[^.]*$")
    end
    
    local decls = terralib.newlist()
    for i,c in ipairs(cmds) do --pass: declare all structs
        if "s" == c.c then
            local tbl,lastname = enclosing(c.name)
            local v = paccess(c.name,3,tbl,lastname)
            if not T.struct:isclassof(v) or v.tree then
                v = terra.types.newstruct(c.name,1)
                v.undefined = true
            end
            decls[i] = v
            paccess(c.name,3,tbl,lastname,v)
        end
    end
    local r = terralib.newlist()
    local simultaneousdefinitions,definedfunctions = {},{}
    local diag = terra.newdiagnostics()
    local function checkduplicate(tbl,name,tree)
        local fntbl = definedfunctions[tbl] or {}
        if fntbl[name] then
            diag:reporterror(tree,"duplicate definition of function")
            diag:reporterror(fntbl[name],"previous definition is here")
        end
        fntbl[name] = tree
        definedfunctions[tbl] = fntbl
    end
    for i,c in ipairs(cmds) do -- pass: declare all functions, create return list
        local tbl,lastname = enclosing(c.name)
        if "s" ~= c.c then
            if "m" == c.c then
                if not terra.types.istype(tbl) or not tbl:isstruct() then
                    erroratlocation(c.tree,"expected a struct but found ",terra.type(tbl)," when attempting to add method ",c.name)
                end
                c.tree = desugarmethoddefinition(c.tree,tbl)
                tbl = tbl.methods
            end
            local v = paccess(c.name,3,tbl,lastname)
            if c.tree.kind == "luaexpression" then -- declaration with type
                local typ = evaltype(diag,env,c.tree)
                if not typ:ispointertofunction() then
                    diag:reporterror(c.tree,"expected a function pointer but found ",typ)
                else
                    v = T.terrafunction(nil,c.name,typ.type,c.tree)
                end
            else -- definition, evaluate the parameters to try to determine its type, create a placeholder declaration if a return type is not present
                c.tree = evalformalparameters(diag,env,c.tree)
                checkduplicate(tbl,lastname,c.tree)
                if not terra.isfunction(v) or v:isdefined() then
                    local typ = terra.types.placeholderfunction
                    if c.tree.returntype then
                        typ = terra.types.functype(c.tree.parameters:map("type"),c.tree.returntype,false)
                    end
                    v = T.terrafunction(nil,c.name,typ,c.tree)
                end
                simultaneousdefinitions[v] = c.tree
            end
            decls[i] = v
            paccess(c.name,3,tbl,lastname,v)
        end
        if lastname == c.name then
            r:insert(decls[i])
        end
    end
    diag:finishandabortiferrors("Errors reported during function declaration.",2)
    
    for i,c in ipairs(cmds) do -- pass: define structs
        if "s" == c.c and c.tree then
            layoutstruct(decls[i],c.tree,env)
        end
    end
    for i,c in ipairs(cmds) do -- pass: define functions
        local decl = decls[i]
        if "s" ~= c.c and not decl:isdefined() and c.tree.kind ~= "luaexpression" then -- may have already been defined as part of a previous call to typecheck in this loop
            simultaneousdefinitions[decl] = nil -- so that a recursive check of this fails if there is no return type
            decl:adddefinition(typecheck(c.tree,env,simultaneousdefinitions))
        end
    end
    return unpack(r)
end

function terra.anonstruct(tree,envfn)
    local st = terra.types.newstruct("anon",2)
    layoutstruct(st,tree,envfn())
    return st
end

function terra.anonfunction(tree,envfn)
    local env = envfn()
    local diag = terra.newdiagnostics()
    tree = evalformalparameters(diag,env,tree)
    diag:finishandabortiferrors("Errors during function declaration.",2)
    tree = typecheck(tree,env)
    tree.name = "anon ("..tree.filename..":"..tree.linenumber..")"
    return T.terrafunction(tree,tree.name,tree.type,tree)
end

function terra.externfunction(name,typ,anchor)
    assert(T.Type:isclassof(typ) and typ:isfunction() or typ:ispointertofunction(),"expected a pointer to a function")
    if typ:ispointertofunction() then typ = typ.type end
    anchor = anchor or terra.newanchor(2)
    return T.terrafunction(newobject(anchor,T.functionextern,name,typ),name,typ,anchor)
end

function terra.definequote(tree,envfn)
    return terra.newquote(typecheck(tree,envfn()))
end

-- END CONSTRUCTORS

-- TYPE

do 

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
    local defaultproperties = { "name", "tree", "undefined", "incomplete", "convertible", "cachedcstring", "llvm_definingfunction" }
    for i,dp in ipairs(defaultproperties) do
        T.Type[dp] = false
    end
    T.Type.__index = nil -- force overrides
    function T.Type:__index(key)
        local N = tonumber(key)
        if N then
            return T.array(self,N) -- int[3] should create an array
        else
            return getmetatable(self)[key]
        end
    end
    T.Type.__tostring = nil --force override to occur
    T.Type.__tostring = memoizefunction(function(self)
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
        elseif self:isfunction() then return mkstring(self.parameters,"{",",",self.isvararg and " ...}" or "}").." -> "..tostring(self.returntype)
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
    
    T.Type.printraw = terra.printraw
    function T.Type:isprimitive() return self.kind == "primitive" end
    function T.Type:isintegral() return self.kind == "primitive" and self.type == "integer" end
    function T.Type:isfloat() return self.kind == "primitive" and self.type == "float" end
    function T.Type:isarithmetic() return self.kind == "primitive" and (self.type == "integer" or self.type == "float") end
    function T.Type:islogical() return self.kind == "primitive" and self.type == "logical" end
    function T.Type:canbeord() return self:isintegral() or self:islogical() end
    function T.Type:ispointer() return self.kind == "pointer" end
    function T.Type:isarray() return self.kind == "array" end
    function T.Type:isfunction() return self.kind == "functype" end
    function T.Type:isstruct() return self.kind == "struct" end
    function T.Type:ispointertostruct() return self:ispointer() and self.type:isstruct() end
    function T.Type:ispointertofunction() return self:ispointer() and self.type:isfunction() end
    function T.Type:isaggregate() return self:isstruct() or self:isarray() end
    
    function T.Type:iscomplete() return not self.incomplete end
    
    function T.Type:isvector() return self.kind == "vector" end
    
    function T.Type:isunit() return types.unit == self end
    
    local applies_to_vectors = {"isprimitive","isintegral","isarithmetic","islogical", "canbeord"}
    for i,n in ipairs(applies_to_vectors) do
        T.Type[n.."orvector"] = function(self)
            return self[n](self) or (self:isvector() and self.type[n](self.type))  
        end
    end
    
    --pretty print of layout of type
    function T.Type:layoutstring()
        local seen = {}
        local parts = List()
        local function print(self,d)
            local function indent(l)
                parts:insert("\n")
                parts:insert(string.rep("  ",d+1+(l or 0)))
            end
            parts:insert(tostring(self))
            if seen[self] then return end
            seen[self] = true
            if self:isstruct() then
                parts:insert(":")
                local layout = self:getlayout()
                for i,e in ipairs(layout.entries) do
                    indent()
                    parts:insert(tostring(e.key)..": ")
                    print(e.type,d+1)
                end
            elseif self:isarray() or self:ispointer() then
                parts:insert(" ->")
                indent()
                print(self.type,d+1)
            elseif self:isfunction() then
                parts:insert(": ")
                indent() parts:insert("parameters: ")
                print(types.tuple(unpack(self.parameters)),d+1)
                indent() parts:insert("returntype:")
                print(self.returntype,d+1)
            end
        end
        print(self,0)
        parts:insert("\n")
        return parts:concat()
    end
    function T.Type:printpretty() io.write(self:layoutstring()) end
    local function memoizeproperty(data)
        local name = data.name
        local erroronrecursion = data.erroronrecursion
        local getvalue = data.getvalue

        local key = "cached"..name
        local inside = "inget"..name
        T.struct[key],T.struct[inside] = false,false
        return function(self)
            if not self[key] then
                if self[inside] then
                    erroratlocation(self.anchor,erroronrecursion)
                else 
                    self[inside] = true
                    self[key] = getvalue(self)
                    self[inside] = nil
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
            
            local keystr = terra.islabel(v.key) and v.key:tocname() or v.key
            str = str..v.type:cstring().." "..keystr.."; "
            
            if v.inunion and nextalloc ~= v.allocation then
                str = str .. " }; "
            end
            
        end
        str = str .. "};"
        local status,err = pcall(ffi.cdef,str)
        if not status then 
            if err:match("attempt to redefine") then
                print(("warning: attempting to define a C struct %s that has already been defined by the luajit ffi, assuming the Terra type matches it."):format(nm))
            else error(err) end
        end
    end
    local uniquetypenameset = uniquenameset("_")
    local function uniquecname(name) --used to generate unique typedefs for C
        return uniquetypenameset(tovalididentifier(name))
    end
    function T.Type:cstring()
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
                    pa = mkstring(pa,"(",",","")
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
                    if terra.ismacro(method) then
                        error("calling a terra macro directly from Lua is not supported",2)
                    end
                    return method
                end
                ffi.metatype(ctype, self.metamethods.__luametatable or { __index = index })
            end
        end
        return self.cachedcstring
    end

    

    T.struct.getentries = memoizeproperty{
        name = "entries";
        erroronrecursion = "recursively calling getentries on type, or using a type whose getentries failed";
        getvalue = function(self)
            local entries = self.entries
            if type(self.metamethods.__getentries) == "function" then
                entries = invokeuserfunction(self.anchor,"invoking __getentries for struct",false,self.metamethods.__getentries,self)
            elseif self.undefined then
                erroratlocation(self.anchor,"attempting to use type ",self," before it is defined.")
            end
            if type(entries) ~= "table" then
                erroratlocation(self.anchor,"computed entries are not a table")
            end
            local function checkentry(e,results)
                if type(e) == "table" then
                    local f = e.field or e[1] 
                    local t = e.type or e[2]
                    if terra.types.istype(t) and (type(f) == "string" or terra.islabel(f)) then
                        results:insert { type = t, field = f}
                        return
                    elseif terra.israwlist(e) then
                        local union = terra.newlist()
                        for i,se in ipairs(e) do checkentry(se,union) end
                        results:insert(union)
                        return
                    end
                end
               erroratlocation(self.anchor,"expected either a field type pair (e.g. { field = <string>, type = <type> } or {<string>,<type>} ), or a list of valid entries representing a union")
            end
            local checkedentries = terra.newlist()
            for i,e in ipairs(entries) do checkentry(e,checkedentries) end
            return checkedentries
        end
    }
    local function reportopaque(type)
        local msg = "attempting to use an opaque type "..tostring(type).." where the layout of the type is needed"
        if type.anchor then
            erroratlocation(type.anchor,msg)
        else
            error(msg,4)
        end
    end
    T.struct.getlayout = memoizeproperty {
        name = "layout"; 
        erroronrecursion = "type recursively contains itself, or using a type whose layout failed";
        getvalue = function(self)
            local tree = self.anchor
            local entries = self:getentries()
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
                        t:getlayout()
                    elseif t:isarray() then
                        ensurelayout(t.type)
                    elseif t == types.opaque then
                        reportopaque(self)    
                    end
                end
                ensurelayout(t)
                local entry = { type = t, key = k, allocation = nextallocation, inunion = uniondepth > 0 }
                
                if layout.keytoindex[entry.key] ~= nil then
                    erroratlocation(tree,"duplicate field ",tostring(entry.key))
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
            if self.cachedcstring then
                definecstruct(self.cachedcstring,layout)
            end
            return layout
        end;
    }
    function T.functype:completefunction()
        for i,p in ipairs(self.parameters) do p:complete() end
        self.returntype:complete()
        return self
    end
    function T.Type:complete() 
        if self.incomplete then
            if self:isarray() then
                self.type:complete()
                self.incomplete = self.type.incomplete
            elseif self == types.opaque or self:isfunction() then
                reportopaque(self)
            else
                assert(self:isstruct())
                local layout = self:getlayout()
                if not layout.invalid then
                    self.incomplete = nil --static initializers run only once
                                          --if one of the members of this struct recursively
                                          --calls complete on this type, then it will return before the static initializer has run
                    for i,e in ipairs(layout.entries) do
                        e.type:complete()
                    end
                    if type(self.metamethods.__staticinitialize) == "function" then
                        invokeuserfunction(self.anchor,"invoking __staticinitialize",false,self.metamethods.__staticinitialize,self)
                    end
                end
            end
        end
        return self
    end
    function T.functype:tcompletefunction(anchor)
        return invokeuserfunction(anchor,"finalizing type",false,self.completefunction,self)
    end
    function T.Type:tcomplete(anchor)
        return invokeuserfunction(anchor,"finalizing type",false,self.complete,self)
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
    function T.struct:getmethod(methodname)
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
    function T.struct:getfield(fieldname)
        local l = self:getlayout()
        local i = l.keytoindex[fieldname]
        if not i then return nil, ("field name '%s' is not a raw field of type %s"):format(tostring(self),tostring(fieldname)) end
        return l.entries[i+1]
    end
    function T.struct:getfields()
        return self:getlayout().entries
    end
        
    function types.istype(t)
        return T.Type:isclassof(t)
    end
    
    --map from luajit ffi ctype objects to corresponding terra type
    types.ctypetoterra = {}
    
    local function globaltype(name, typ, min_v, max_v)
        typ.name = typ.name or name
        rawset(_G,name,typ)
        types[name] = typ
        if min_v then function typ:min() return terra.cast(self, min_v) end end
        if max_v then function typ:max() return terra.cast(self, max_v) end end
    end
    
    --initialize integral types
    local integer_sizes = {1,2,4,8}
    for _,size in ipairs(integer_sizes) do
        for _,s in ipairs{true,false} do
            local bits = size * 8
            local name = "int"..tostring(bits)
            if not s then
                name = "u"..name
            end
            local min,max
            if not s then
                min = 0ULL
                max = -1ULL
            else
                min = 2LL ^ (bits - 1)
                max = min - 1
            end
            local typ = T.primitive("integer",size,s)
            globaltype(name,typ,min,max)
        end
    end  
    
    globaltype("float", T.primitive("float",4,true), -math.huge, math.huge)
    globaltype("double",T.primitive("float",8,true), -math.huge, math.huge)
    globaltype("bool", T.primitive("logical",1,false))
    
    types.error,T.error.name = T.error,"<error>"
    T.luaobjecttype.name = "luaobjecttype"
    
    types.niltype = T.niltype
    globaltype("niltype",T.niltype)
    
    types.opaque,T.opaque.incomplete = T.opaque,true
    globaltype("opaque", T.opaque)
    
    types.array,types.vector,types.functype = T.array,T.vector,T.functype
    
    T.functype.incomplete = true
    function T.functype:init()
        if self.isvararg and #self.parameters == 0 then error("vararg functions must have at least one concrete parameter") end
    end
    function types.pointer(t,as) return T.pointer(t,as or 0) end
    function T.array:init()
        self.incomplete = true
    end
    
    function T.vector:init()
        if not self.type:isprimitive() and self.type ~= T.error then
            error("vectors must be composed of primitive types (for now...) but found type "..tostring(self.type))
        end
    end
    
    types.tuple = memoizefunction(function(...)
        local args = terra.newlist {...}
        local t = types.newstruct()
        for i,e in ipairs(args) do
            if not types.istype(e) then 
                error("expected a type but found "..type(e))
            end
            t.entries:insert {"_"..(i-1),e}
        end
        t.metamethods.__typename = function(self)
            return mkstring(args,"{",",","}")
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
    function T.struct:setconvertible(b)
        assert(self.incomplete)
        self.convertible = b
    end
    function types.newstructwithanchor(displayname,anchor)
        assert(displayname ~= "")
        local name = getuniquestructname(displayname)
        local tbl = T.struct(name) 
        tbl.entries = List()
        tbl.methods = {}
        tbl.metamethods = {}
        tbl.anchor = anchor
        tbl.incomplete = true
        return tbl
    end
   
    function types.funcpointer(parameters,ret,isvararg)
        if types.istype(parameters) then
            parameters = {parameters}
        end
        if not types.istype(ret) and terra.israwlist(ret) then
            ret = #ret == 1 and ret[1] or types.tuple(unpack(ret))
        end
        return types.pointer(types.functype(List{unpack(parameters)},ret,not not isvararg))
    end
    types.unit = types.tuple():complete()
    types.placeholderfunction = types.functype(List(),types.error,false) --used as a placeholder during group definitions indicating the definition has not been processed yet
    globaltype("int",types.int32)
    globaltype("uint",types.uint32)
    globaltype("long",types.int64)
    globaltype("intptr",types.uint64)
    globaltype("ptrdiff",types.int64)
    globaltype("rawstring",types.pointer(types.int8))
    terra.types = types
    terra.memoize = memoizefunction
end

function T.tree:setlvalue(v)
    if v then
        self.lvalue = true
    end
    return self
end
function T.tree:withtype(type) -- for typed tree
    assert(terra.types.istype(type))
    self.type = type
    return self
end
-- END TYPE


-- TYPECHECKER
function evalluaexpression(env, e)
    if not T.luaexpression:isclassof(e) then
       error("not a lua expression?") 
    end
    assert(type(e.expression) == "function")
    local fn = e.expression
    local oldenv = getfenv(fn)
    setfenv(fn,env)
    local v = invokeuserfunction(e,"evaluating Lua code from Terra",false,fn)
    setfenv(fn,oldenv) --otherwise, we hold false reference to env, -- in the case of an error, this function will still hold a reference
                       -- but without a good way of doing 'finally' without messing with the error trace there is no way around this
    return v
end

function evaltype(diag,env,typ)
    local v = evalluaexpression(env,typ)
    if terra.types.istype(v) then return v end
    if terra.israwlist(v) then
        for i,t in ipairs(v) do
            if not terra.types.istype(t) then
                diag:reporterror(typ,"expected a type but found ",terra.type(v))
                return terra.types.error
            end
        end
        return #v == 1 and v[1] or terra.types.tuple(unpack(v))
    end
    diag:reporterror(typ,"expected a type but found ",terra.type(v))
    return terra.types.error
end
    
function evaluateparameterlist(diag, env, paramlist, requiretypes)
    local result = List()
    for i,p in ipairs(paramlist) do
        if p.kind == "unevaluatedparam" then
            if p.name.kind == "namedident" then
                local typ = p.type and evaltype(diag,env,p.type)
                local sym = terra.newsymbol(typ or T.error,p.name.value)
                result:insert(newobject(p,T.concreteparam,typ,p.name.value,sym,true))
            else assert(p.name.kind == "escapedident")
                local value = evalluaexpression(env,p.name.expression)
                if not value then
                    diag:reporterror(p,"expected a symbol or string but found nil")
                end
                local symlist = (terra.israwlist(value) and value) or List { value }
                for i,entry in ipairs(symlist) do
                    if terra.issymbol(entry) then
                        result:insert(newobject(p,T.concreteparam, entry.type, tostring(entry),entry,false))
                    else
                        diag:reporterror(p,"expected a symbol but found ",terra.type(entry))
                    end
                end
            end
        else
            result:insert(p)
        end
    end
    for i,entry in ipairs(result) do
        assert(entry.type == nil or terra.types.istype(entry.type))
        if requiretypes and not entry.type then
            diag:reporterror(entry,"type must be specified for parameters and uninitialized variables")
        end
    
    end
    return result
end
    
local function semanticcheck(diag,parameters,block)
    local symbolenv = terra.newenvironment()
    
    local labelstates = {} -- map from label value to labelstate object, either representing a defined or undefined label
    local globalsused = List() 
    
    local loopdepth = 0
    local function enterloop() loopdepth = loopdepth + 1 end
    local function leaveloop() loopdepth = loopdepth - 1 end
    
    local scopeposition = List()
    local function getscopeposition() return List { unpack(scopeposition) } end
    local function getscopedepth(position)
        local c = 0
        for _,d in ipairs(position) do
            c = c + d
        end
        return c
    end
    local function defersinlocalscope()
        return scopeposition[#scopeposition]
    end
    local function checklocaldefers(anchor,c)
        if defersinlocalscope() ~= c then
            diag:reporterror(anchor, "defer statements are not allowed in conditional expressions")
        end
    end
    --calculate the number of deferred statements that will fire when jumping from stack position 'from' to 'to'
    --if a goto crosses a deferred statement, we detect that and report an error
    local function checkdeferredpassed(anchor,from,to)
        local N = math.max(#from,#to)
        for i = 1,N do
            local t,f = to[i] or 0, from[i] or 0
            if t < f then
                for j = i+1,N do
                    if (to[j] or 0) ~= 0 then
                        diag:reporterror(anchor,"goto crosses the scope of a deferred statement")
                    end
                end
            elseif t > f then
                diag:reporterror(anchor,"goto crosses the scope of a deferred statement")
            end
        end
    end
    local visit
    local function visitnolocaldefers(anchor,e)
        local ndefers = defersinlocalscope()
        visit(e)
        checklocaldefers(anchor,ndefers)
    end
    function visit(e)
        if List:isclassof(e) then
            for _,ee in ipairs(e) do visit(ee) end
        elseif T.tree:isclassof(e) then
            if e:is "var" then
                local definition = symbolenv:localenv()[e.symbol]
                if not definition then
                    diag:reporterror(e, "definition of variable with symbol ",e.symbol, " is not in scope in this context")
                end
            elseif e:is "globalvalueref" then
                globalsused:insert(e.value)
            elseif e:is "allocvar" then
                symbolenv:localenv()[e.symbol] = e
            elseif e:is "letin" then
                symbolenv:enterblock()
                visit(e.statements)
                visit(e.expressions)
                symbolenv:leaveblock()
            elseif e:is "block" then
                symbolenv:enterblock()
                scopeposition:insert(0)
                visit(e.statements)
                scopeposition:remove()
                symbolenv:leaveblock()
            elseif e:is "label" then
                local label = e.label.value
                local state = labelstates[label]
                local position = getscopeposition()
                if state and state.kind == "definedlabel" then
                    diag:reporterror(e,"label defined twice")
                    diag:reporterror(state.label,"previous definition here")
                elseif state then assert(state.kind == "undefinedlabel")
                    for i,g in ipairs(state.gotos) do
                        checkdeferredpassed(g,state.positions[i],position)
                    end
                end
                labelstates[label] = T.definedlabel(position,e)
            elseif e:is "gotostat" then
                local label = e.label.value
                local state = labelstates[label] or T.undefinedlabel(List(),List())
                local position = getscopeposition()
                if state.kind == "definedlabel" then
                    checkdeferredpassed(e,scopeposition,state.position)
                else assert(state.kind == "undefinedlabel")
                    state.gotos:insert(e)
                    state.positions:insert(getscopeposition())
                end
                labelstates[label] = state
            elseif e:is "breakstat" then
                if loopdepth == 0 then
                    diag:reporterror(e,"break found outside a loop")
                end
            elseif e:is "whilestat" then
                enterloop()
                visitnolocaldefers(e.condition,e.condition)
                visit(e.body)
                leaveloop()
            elseif e:is "repeatstat" then
                enterloop()
                visit(e.statements)
                visitnolocaldefers(e.condition,e.condition)
            elseif e:is "ifbranch" then
                visitnolocaldefers(e.condition,e.condition)
                visit(e.body)
            elseif e:is "fornum" then
                visit(e.initial); visit(e.limit); visit(e.step)
                visit(e.variable)
                enterloop()
                visit(e.body)
                leaveloop()
            elseif e:is "defer" then
                visit(e.expression)
                scopeposition[#scopeposition] = scopeposition[#scopeposition] + 1
            elseif e:is "operator" and (e.operator == "and" or e.operator == "or") and e.operands[1].type:islogical() then
                visitnolocaldefers(e,e.operands)
            else --generic traversal
                for _,field in ipairs(e.__fields) do
                    visit(e[field.name])
                end
            end
        end
    end
    visit(parameters)
    visit(block)
    
    --check the label table for any labels that have been referenced but not defined
    local labeldepths = {}
    for k,state in pairs(labelstates) do
        if state.kind == "undefinedlabel" then
            diag:reporterror(state.gotos[1],"goto to undefined label")
        else
            labeldepths[k] = getscopedepth(state.position)
        end
    end
    
    return labeldepths, globalsused
end

function typecheck(topexp,luaenv,simultaneousdefinitions)
    local env = terra.newenvironment(luaenv or {})
    local diag = terra.newdiagnostics()
    simultaneousdefinitions = simultaneousdefinitions or {}
    
    local invokeuserfunction = function(...)
        diag:finishandabortiferrors("Errors reported during typechecking.",2)
        return invokeuserfunction(...)
    end
    local evalluaexpression = function(...)
        diag:finishandabortiferrors("Errors reported during typechecking.",2)
        return evalluaexpression(...)
    end
    
    local function checklabel(e,stringok)
        if e.kind == "namedident" then return e end
        local r = evalluaexpression(env:combinedenv(),e.expression)
        if type(r) == "string" then
            if not stringok then
                diag:reporterror(e,"expected a label but found string")
                return newobject(e,T.labelident,terra.newlabel(r))
            end
            return newobject(e,T.namedident,r)
        elseif not terra.islabel(r) then
            diag:reporterror(e,"expected a string or label but found ",terra.type(r))
            r = terra.newlabel("error")
        end
        return newobject(e,T.labelident,r)
    end


    -- TYPECHECKING FUNCTION DECLARATIONS
    --declarations major driver functions for typechecker
    local checkexp -- (e.g. 3 + 4)
    local checkstmts,checkblock -- (e.g. var a = 3)
    local checkcall -- any invocation (method, function call, macro, overloaded operator) gets translated into a call to checkcall (e.g. sizeof(int), foobar(3), obj:method(arg))

    --tree constructors for trees created in the typechecking process
    local function createcast(exp,typ)
        return newobject(exp,T.cast,typ,exp):withtype(typ:tcomplete(exp))
    end

    local function createfunctionreference(anchor,e)
        local fntyp = e.type
        if fntyp == terra.types.placeholderfunction then
            local functiondef = simultaneousdefinitions[e]
            if functiondef == nil then
                diag:reporterror(anchor,"referenced function needs an explicit return type (it is recursively referenced or used before its own defintion).")
                diag:reporterror(e.anchor,"definition of function is here.")
            else
                simultaneousdefinitions[e] = nil
                local body = typecheck(functiondef,luaenv,simultaneousdefinitions) -- can throw, but we just want to pass the error through
                e:adddefinition(body)
                fntyp = e.type
            end
        end
        return newobject(anchor,T.globalvalueref,e.name,e):withtype(terra.types.pointer(fntyp))
    end

    local function insertaddressof(ee)
        return newobject(ee,T.operator,"&",List {ee}):withtype(terra.types.pointer(ee.type))
    end

    local function insertdereference(e)
        local ret = newobject(e,T.operator,"@",List{e}):setlvalue(true)
        if not e.type:ispointer() then
            diag:reporterror(e,"argument of dereference is not a pointer type but ",e.type)
            ret:withtype(terra.types.error)
        else
            ret:withtype(e.type.type:tcomplete(e))
        end
        return ret
    end

    local function insertselect(v, field)
        assert(v.type:isstruct())

        local layout = v.type:getlayout(v)
        local index = layout.keytoindex[field]
    
        if index == nil then
            return nil,false
        end

        local type = layout.entries[index+1].type:tcomplete(v)
        local tree = newobject(v,T.select,v,index,tostring(field)):setlvalue(v.lvalue):withtype(type)
        return tree,true
    end

    local function ensurelvalue(e)
        if not e.lvalue then
            diag:reporterror(e,"argument to operator must be an lvalue")
        end
        return e
    end
    local createlet
    --convert a lua value 'v' into the terra tree representing that value
    local function asterraexpression(anchor,v,location)
        location = location or "expression"
        local function createsingle(v)
            if terra.isglobalvar(v) or terra.issymbol(v) then
                local name = T.var:isclassof(anchor) and anchor.name --propage original variable name for debugging purposes
                return newobject(anchor,terra.isglobalvar(v) and T.globalvalueref or T.var,name or tostring(v),v):setlvalue(true):withtype(v.type)
            elseif terra.isquote(v) then
                return v.tree
            elseif terra.istree(v) then
                --if this is a raw tree, we just drop it in place and hope the user knew what they were doing
                return v
            elseif type(v) == "cdata" then
                local typ = terra.typeof(v)
                if typ:isaggregate() then --when an aggregate is directly referenced from Terra we get its pointer
                                          --a constant would make an entire copy of the object
                    local ptrobj = createsingle(terra.constant(terra.types.pointer(typ),v))
                    return insertdereference(ptrobj)
                end
                return createsingle(terra.constant(typ,v))
            elseif type(v) == "number" or type(v) == "boolean" or type(v) == "string" then
                return createsingle(terra.constant(v))
            elseif terra.isfunction(v) then
                return createfunctionreference(anchor,v)
            end
            local mt = getmetatable(v)
            if type(mt) == "table" and mt.__toterraexpression then
                return asterraexpression(anchor,mt.__toterraexpression(v),location)
            end
            if not (terra.isoverloadedfunction(v) or terra.ismacro(v) or terra.types.istype(v) or type(v) == "table") then
                diag:reporterror(anchor,"lua object of type ", terra.type(v), " not understood by terra code.")
                if type(v) == "function" then
                    diag:reporterror(anchor, "to call a lua function from terra first use terralib.cast to cast it to a terra function type.")
                end
            end
            return newobject(anchor,T.luaobject,v):withtype(T.luaobjecttype)
        end
        if not terra.israwlist(v) then
            return createsingle(v)
        end
        local values = List()
        for _,v in ipairs(v) do
            local r = createsingle(v)
            if r:is "letin"  and not r.hasstatements then
                values:insertall(r.expressions)
            else
                values:insert(r)
            end
        end
        if location == "statement" then
            return newobject(anchor,T.statlist,values):withtype(terra.types.unit)
        end
        return createlet(anchor, List(), values, false)
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
        local av = newobject(anchor,T.allocvar,name,terra.newsymbol(typ,name)):setlvalue(true):withtype(typ:tcomplete(anchor))
        local v = newobject(anchor,T.var,name,av.symbol):setlvalue(true):withtype(typ)
        return av,v
    end

    function structcast(explicit,exp,typ, speculative)
        local from = exp.type:getlayout(exp)
        local to = typ:getlayout(exp)

        local valid = true
        local function err(...)
            valid = false
            if not speculative then
                diag:reporterror(exp,...)
            end
        end
        local structvariable, var_ref = allocvar(exp,exp.type,"<structcast>")
    
        local entries = List()
        if #from.entries > #to.entries or (not explicit and #from.entries ~= #to.entries) then
            err("structural cast invalid, source has ",#from.entries," fields but target has only ",#to.entries)
            return exp:copy{}:withtype(typ), valid
        end
        for i,entry in ipairs(from.entries) do
            local selected = insertselect(var_ref,entry.key)
            local offset = exp.type.convertible == "tuple" and i - 1 or to.keytoindex[entry.key]
            if not offset then
                err("structural cast invalid, result structure has no key ", entry.key)
            else
                local v = insertcast(selected,to.entries[offset+1].type)
                entries:insert(newobject(exp,T.storelocation,offset,v))
            end
        end
        return newobject(exp,T.structcast,structvariable,exp,entries):withtype(typ)
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
                return structcast(false,exp,typ,speculative), true
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
                local quotedexp = terra.newquote(exp)
                local success,result = invokeuserfunction(exp, "invoking __cast", true,__cast,exp.type,typ,quotedexp)
                if success then
                    local result = asterraexpression(exp,result)
                    if result.type ~= typ then 
                        diag:reporterror(exp,"user-defined cast returned expression with the wrong type.")
                    end
                    return result,true
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
        elseif a.kind == tokens.primitive and b.kind == tokens.primitive then
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
            return e:aserror()
        end
        return ee:copy { operands = List{e} }:withtype(e.type)
    end 


    local function meetbinary(e,property,lhs,rhs)
        local t,l,r = typematch(e,lhs,rhs)
        if t ~= terra.types.error and not t[property](t) then
            diag:reporterror(e,"arguments of binary operator are not valid type but ",t)
            return e:aserror()
        end
        return e:copy { operands = List {l,r} }:withtype(t)
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
            exp.type.type:tcomplete(exp)
            return (insertcast(exp,terra.types.pointer(exp.type.type))) --parens are to truncate to 1 argument
        end
        -- subtracting 2 pointers
        if  pointerlike(l.type) and pointerlike(r.type) and l.type.type == r.type.type and e.operator == tokens["-"] then
            return e:copy { operands = List {ascompletepointer(l),ascompletepointer(r)} }:withtype(terra.types.ptrdiff)
        elseif pointerlike(l.type) and r.type:isintegral() then -- adding or subtracting a int to a pointer
            return e:copy {operands = List {ascompletepointer(l),r} }:withtype(terra.types.pointer(l.type.type))
        elseif l.type:isintegral() and pointerlike(r.type) then
            return e:copy {operands = List {ascompletepointer(r),l} }:withtype(terra.types.pointer(r.type.type))
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
        return e:copy { operands = List {l,r} }:withtype(rt)
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
    
        return ee:copy { operands =  List{a,b} }:withtype(typ)
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
                diag:reporterror(ee,"expected a boolean or vector of booleans but found ",cond.type)   
            end
        end
        return ee:copy {operands = List {cond,l,r}}:withtype(t)
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
        local op_string = ee.operator
    
        --check non-overloadable operators first
        if op_string == "@" then
            local e = checkexp(ee.operands[1])
            return insertdereference(e)
        elseif op_string == "&" then
            local e = ensurelvalue(checkexp(ee.operands[1]))
            local ty = terra.types.pointer(e.type)
            return ee:copy { operands = List {e} }:withtype(ty)
        end
    
        local op, genericoverloadmethod, unaryoverloadmethod = unpack(operator_table[op_string] or {})
    
        if op == nil then
            diag:reporterror(ee,"operator ",op_string," not defined in terra code.")
            return ee:aserror()
        end
    
        local operands = ee.operands:map(checkexp)
    
        local overloads = terra.newlist()
        for i,e in ipairs(operands) do
            if e.type:isstruct() then
                local overloadmethod = (#operands == 1 and unaryoverloadmethod) or genericoverloadmethod
                local overload = e.type.metamethods[overloadmethod] --TODO: be more intelligent here about merging overloaded functions so that all possibilities are considered
                if overload then
                    overloads:insert(asterraexpression(ee, overload, "luaobject"))
                end
            end
        end
    
        if #overloads > 0 then
            return checkcall(ee, overloads, operands, "all", true, "expression")
        end
        return op(ee,operands)
    end

    --functions to handle typecheck invocations (functions,methods,macros,operator overloads)
    local function removeluaobject(e)
        if not e:is "luaobject" or e.type == terra.types.error then 
            return e --don't repeat error messages
        else
            if terra.types.istype(e.value) then
                diag:reporterror(e, "expected a terra expression but found terra type ", tostring(e.value), ". If this is a cast, you may have omitted the required parentheses: [T](exp)")
            else
                diag:reporterror(e, "expected a terra expression but found ",terra.type(e.value))
            end
            return e:aserror()
        end
    end

    local function checkexpressions(expressions,location)
        local nes = terra.newlist()
        for i,e in ipairs(expressions) do
            local ne = checkexp(e,location)
            if ne:is "letin"  and not ne.hasstatements then
                nes:insertall(ne.expressions)
            else
                nes:insert(ne)
            end
        end
        return nes
    end

    function createlet(anchor, ns, ne, hasstatements)
        local r = newobject(anchor,T.letin,ns,ne,hasstatements)
        if #ne == 1 then
            r:withtype(ne[1].type):setlvalue(ne[1].lvalue)
        else
            r:withtype(terra.types.tuple(unpack(ne:map("type"))))
        end
        r.type:tcomplete(anchor)
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
                    local fromt,tot = typelist:map(tostring):concat(","),paramlist:map("type"):map(tostring):concat(",")
                    diag:reporterror(anchor,"expected ",#typelist," parameters (",fromt,"), but found ",#paramlist, " (",tot,")")
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
                        diag:reporterror(anchor,"option ",i," with type ",mkstring(typelist,"(",",",")"))
                        trylist(typelist,false)
                    end
                end
                return paramlist,nil
            else
                if #results > 1 and not allowambiguous then
                    local strings = results:map(function(x) return mkstring(typelists[x.idx],"type list (",",",") ") end)
                    diag:reporterror(anchor,"call to overloaded function is ambiguous. can apply to ",unpack(strings))
                end 
                return results[1].expressions, results[1].idx
            end
        end
    end

    local function insertcasts(anchor, typelist,paramlist) --typelist is a list of target types (or the value "passthrough"), paramlist is a parameter list that might have a multiple return value at the end
        return tryinsertcasts(anchor, terra.newlist { typelist }, "none", false, false, paramlist)
    end

    local function checkmethodwithreciever(anchor, ismeta, methodname, reciever, arguments, location)
        local objtyp
        reciever.type:tcomplete(anchor)
        if reciever.type:isstruct() then
            objtyp = reciever.type
        elseif reciever.type:ispointertostruct() then
            objtyp = reciever.type.type
            reciever = insertdereference(reciever)
        else
            diag:reporterror(anchor,"attempting to call a method on a non-structural type ",reciever.type)
            return anchor:aserror()
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
            return anchor:aserror()
        end

        fnlike = asterraexpression(anchor, fnlike, "luaobject")
        local fnargs = List { reciever, unpack(arguments) }
        return checkcall(anchor, terra.newlist { fnlike }, fnargs, "first", false, location)
    end

    local function checkmethod(exp, location)
        local methodname = checklabel(exp.name,true).value
        assert(type(methodname) == "string" or terra.islabel(methodname))
        local reciever = checkexp(exp.value)
        local arguments = checkexpressions(exp.arguments,"luavalue")
        return checkmethodwithreciever(exp, false, methodname, reciever, arguments, location)
    end

    local function checkapply(exp, location)
        local fnlike = checkexp(exp.value,"luavalue")
        local arguments = checkexpressions(exp.arguments,"luavalue")
        if not fnlike:is "luaobject" then
            local typ = fnlike.type
            typ = typ:ispointer() and typ.type or typ
            if typ:isstruct() then
                if location == "lexpression" and typ.metamethods.__update then
                    local function setter(rhs)
                        arguments:insert(rhs)
                        return checkmethodwithreciever(exp, true, "__update", fnlike, arguments, "statement") 
                    end
                    return newobject(exp,T.setteru,setter)
                end
                return checkmethodwithreciever(exp, true, "__apply", fnlike, arguments, location) 
            end
        end
        return checkcall(exp, terra.newlist { fnlike } , arguments, "none", false, location)
    end
    function checkcall(anchor, fnlikelist, arguments, castbehavior, allowambiguous, location)
        --arguments are always typed trees, or a lua object
        assert(#fnlikelist > 0)
    
        --collect all the terra functions, stop collecting when we reach the first 
        --macro and record it as themacro
        local terrafunctions = terra.newlist()
        local themacro = nil
        for i,fn in ipairs(fnlikelist) do
            if fn:is "luaobject" then
                if terra.ismacro(fn.value) then
                    themacro = fn.value
                    break
                elseif terra.types.istype(fn.value) then
                    local castmacro = terra.internalmacro(function(diag,tree,arg)
                        return insertexplicitcast(arg.tree,fn.value)
                    end)
                    themacro = castmacro
                    break
                elseif terra.isoverloadedfunction(fn.value) then
                    if #fn.value:getdefinitions() == 0 then
                        diag:reporterror(anchor,"attempting to call overloaded function without definitions")
                    end
                    for i,v in ipairs(fn.value:getdefinitions()) do
                        local fnlit = createfunctionreference(anchor,v)
                        if fnlit.type ~= terra.types.error then
                            terrafunctions:insert( fnlit )
                        end
                    end
                else
                    diag:reporterror(anchor,"expected a function or macro but found lua value of type ",terra.type(fn.value))
                end
            elseif fn.type:ispointertofunction() then
                terrafunctions:insert(fn)
            else
                if fn.type ~= terra.types.error then
                    diag:reporterror(anchor,"expected a function but found ",fn.type)
                end
            end 
        end

        local function createcall(callee, paramlist)
            callee.type.type:tcompletefunction(anchor)
            return newobject(anchor,T.apply,callee,paramlist):withtype(callee.type.type.returntype)
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
            local castedarguments,valididx = tryinsertcasts(anchor,typelists,castbehavior, themacro ~= nil, allowambiguous, paramlist)
            if valididx then
                return createcall(terrafunctions[valididx],castedarguments)
            end
        end

        if themacro then
            local quotes = arguments:map(terra.newquote)
            local result = invokeuserfunction(anchor,"invoking macro",false, themacro.run, themacro, diag, anchor, unpack(quotes))
            return asterraexpression(anchor,result,location)
        end
        assert(diag:haserrors())
        return anchor:aserror()
    end

    --functions that handle the checking of expressions
    local function checkluaexpression(e,location)
        local value = {}
        if e.isexpression then
            value = evalluaexpression(env:combinedenv(),e)
        else
            env:enterblock()
            env:localenv().emit = function(arg) table.insert(value,arg) end
            evalluaexpression(env:combinedenv(),e)
            env:leaveblock()
        end
        return asterraexpression(e, value, location)
    end
    function checkexp(e_, location)
        location = location or "expression"
        assert(type(location) == "string")
        local function docheck(e)
            if not terra.istree(e) then
                print("not a tree?")
                print(debug.traceback())
                terra.printraw(e)
            end
            if e:is "literal" then
                return e
            elseif e:is "var" then
                local v = env:combinedenv()[e.name]
                if v == nil then
                    diag:reporterror(e,"variable '"..e.name.."' not found")
                    return e:aserror()
                end
                return asterraexpression(e,v, location)
            elseif e:is "quote" then
                return e.tree -- already checked tree, quotes get injected directly into some untyped trees by macros
            elseif e:is "selectu" then
                local v = checkexp(e.value,"luavalue")
                local f = checklabel(e.field,true)
                local field = f.value
            
                if v:is "luaobject" then -- handle A.B where A is a luatable or type
                    --check for and handle Type.staticmethod
                    if terra.types.istype(v.value) and v.value:isstruct() then
                        local fnlike, errmsg = v.value:getmethod(field)
                        if not fnlike then
                            diag:reporterror(e,errmsg)
                            return e:aserror()
                        end
                        return asterraexpression(e,fnlike, location)
                    elseif type(v.value) ~= "table" then
                        diag:reporterror(e,"expected a table but found ", terra.type(v.value))
                        return e:aserror()
                    else
                        local selected = invokeuserfunction(e,"extracting field "..tostring(field),false,function() return v.value[field] end)
                        if selected == nil then
                            diag:reporterror(e,"no field ", field," in lua object")
                            return e:aserror()
                        end
                        return asterraexpression(e,selected,location)
                    end
                end
            
                if v.type:ispointertostruct() then --allow 1 implicit dereference
                    v = insertdereference(v)
                end

                if v.type:isstruct() then
                    local ret, success = insertselect(v,field)
                    if not success then
                        --struct has no member field, call metamethod __entrymissing
                        local typ = v.type
                    
                        local function checkmacro(metamethod,arguments,location)
                            local named = terra.internalmacro(function(ctx,tree,...)
                                return typ.metamethods[metamethod]:run(ctx,tree,field,...)
                            end)
                            local getter = asterraexpression(e, named, "luaobject") 
                            return checkcall(v, terra.newlist{ getter }, arguments, "first", false, location)
                        end
                        if location == "lexpression" and typ.metamethods.__setentry then
                            local function setter(rhs)
                                return checkmacro("__setentry", terra.newlist { v , rhs }, "statement")
                            end
                            return newobject(v,T.setteru,setter)
                        elseif terra.ismacro(typ.metamethods.__entrymissing) then
                            return checkmacro("__entrymissing",terra.newlist { v },location)
                        else
                            diag:reporterror(v,"no field ",field," in terra object of type ",v.type)
                            return e:aserror()
                        end
                    else
                        return ret
                    end
                else
                    diag:reporterror(v,"expected a structural type")
                    return e:aserror()
                end
            elseif e:is "luaexpression" then
                return checkluaexpression(e,location)
            elseif e:is "operator" then
                return checkoperator(e)
            elseif e:is "cast" then -- inserted by global to force a cast in the initializer
                return insertcast(checkexp(e.expression), e.to)
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
                return e:copy { value = v, index = idx }:withtype(typ):setlvalue(lvalue)
            elseif e:is "sizeof" then
                e.oftype:tcomplete(e)
                return e:copy{}:withtype(terra.types.uint64)
            elseif e:is "vectorconstructor" or e:is "arrayconstructor" then
                local entries = checkexpressions(e.expressions)
                local N = #entries
                     
                local typ
                if e.oftype ~= nil then
                    typ = e.oftype:tcomplete(e)
                else
                    if N == 0 then
                        diag:reporterror(e,"cannot determine type of empty aggregate")
                        return e:aserror()
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
                        diag:reporterror(e,"vectors must be composed of primitive types (for now...) but found type ",terra.type(typ))
                        return e:aserror()
                    end
                    aggtype = terra.types.vector(typ,N)
                else
                    aggtype = terra.types.array(typ,N)
                end
            
                --insert the casts to the right type in the parameter list
                local typs = entries:map(function(x) return typ end)
                entries = insertcasts(e,typs,entries)
                return e:copy { expressions = entries }:withtype(aggtype)
            elseif e:is "attrload" then
                local addr = checkexp(e.address)
                if not addr.type:ispointer() then
                    diag:reporterror(e,"address must be a pointer but found ",addr.type)
                    return e:aserror()
                end
                return e:copy { address = addr }:withtype(addr.type.type)
            elseif e:is "attrstore" then
                local addr = checkexp(e.address)
                if not addr.type:ispointer() then
                    diag:reporterror(e,"address must be a pointer but found ",addr.type)
                    return e:aserror()
                end
                local value = insertcast(checkexp(e.value),addr.type.type)
                return e:copy { address = addr, value = value }:withtype(terra.types.unit)
            elseif e:is "apply" then
                return checkapply(e,location)
            elseif e:is "method" then
                return checkmethod(e,location)
            elseif e:is "letin" then
                local ns = checkstmts(e.statements)
                local ne = checkexpressions(e.expressions)
                return createlet(e,ns,ne,e.hasstatements)
           elseif e:is "constructoru" then
                local paramlist = terra.newlist()
                local named = 0
                for i,f in ipairs(e.records) do
                    local value = checkexp(f.value)
                    named = named + (f.key and 1 or 0)
                    if not f.key and value:is "letin" and not value.hasstatements then
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
                        typ.entries:insert({field = checklabel(e.key,true).value, type = paramlist[i].type})
                    end
                else
                    diag:reporterror(e, "some entries in constructor are named while others are not")
                end
                return newobject(e,T.constructor,paramlist):withtype(typ:tcomplete(e))
            elseif e:is "inlineasm" then
                return e:copy { arguments = checkexpressions(e.arguments) }
            elseif e:is "debuginfo" then
                return e:copy{}:withtype(terra.types.unit)
            else
                diag:reporterror(e,"statement found where an expression is expected ", e.kind)
                return e:aserror()
            end
        end
    
        local result = docheck(e_)
        --freeze all types returned by the expression (or list of expressions)
        if not result:is "luaobject" and not result:is "setteru" then
            assert(terra.types.istype(result.type))
            result.type:tcomplete(result)
        end

        --remove any lua objects if they are not allowed in this context
        if location ~= "luavalue" then
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
        return checkexptyp(c,terra.types.bool)
    end
    local function checkcondbranch(s)
        local e = checkcond(s.condition)
        local body = checkblock(s.body)
        return copyobject(s,{condition = e, body = body})
    end

    local function checkformalparameterlist(paramlist, requiretypes)
        local evalparams = evaluateparameterlist(diag,env:combinedenv(),paramlist,requiretypes)
        local result = List()
        for i,p in ipairs(evalparams) do
            if p.isnamed then
                local lenv = env:localenv()
                if rawget(lenv,p.name) then
                    diag:reporterror(p,"duplicate definition of variable ",p.name)
                end
                lenv[p.name] = p.symbol
            end
            local r = newobject(p,T.allocvar,p.name,p.symbol)
            if p.type then
                r:withtype(p.type:tcomplete(p))
            end
            result:insert(r)
        end
        return result
    end

    local function createstatementlist(anchor,stmts)
        return newobject(anchor,T.letin, stmts, List {}, true):withtype(terra.types.unit)
    end

    local function createassignment(anchor,lhs,rhs)
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
                return createstatementlist(anchor, List {a1, a2})
            end
        end
        local vtypes = lhs:map(function(v) return v.type or "passthrough" end)
        rhs = insertcasts(anchor,vtypes,rhs)
        for i,v in ipairs(lhs) do
            local rhstype = rhs[i] and rhs[i].type or terra.types.error
            if v:is "setteru" then
                local rv,r = allocvar(v,rhstype,"<rhs>")
                lhs[i] = newobject(v,T.setter, rv,v.setter(r))
            elseif v:is "allocvar" then
                v:settype(rhstype)
            else
                ensurelvalue(v)
            end
        end
        return newobject(anchor,T.assignment,lhs,rhs)
    end

    function checkblock(s)
        env:enterblock()
        local stats = checkstmts(s.statements)
        env:leaveblock()
        return s:copy {statements = stats}
    end

    function checkstmts(stmts)
        local function checksingle(s)
            if s:is "block" then
                return checkblock(s)
            elseif s:is "returnstat" then
                return s:copy { expression = checkexp(s.expression)}
            elseif s:is "label" or s:is "gotostat" then    
                local ss = checklabel(s.label)
                return copyobject(s, { label = ss })
            elseif s:is "breakstat" then
                return s
            elseif s:is "whilestat" then
                return checkcondbranch(s)
            elseif s:is "fornumu" then
                local initial, limit, step = checkexp(s.initial), checkexp(s.limit), s.step and checkexp(s.step)
                local t = typemeet(initial,initial.type,limit.type) 
                t = step and typemeet(limit,t,step.type) or t
                local variables = checkformalparameterlist(List {s.variable },false)
                if #variables ~= 1 then
                    diag:reporterror(s.variable, "expected a single iteration variable but found ",#variables)
                    return s
                end
                local variable = variables[1]
                variable:settype(variable.type or t)
                if not variable.type:isintegral() then diag:reporterror(variable,"expected an integral type for loop initialization but found ",variable.type) end
                initial,step,limit = insertcast(initial,variable.type), step and insertcast(step,variable.type), insertcast(limit,variable.type)
                local body = checkblock(s.body)
                return newobject(s,T.fornum,variable,initial,limit,step,body)
            elseif s:is "forlist" then
                local iterator = checkexp(s.iterator)
            
                local typ = iterator.type
                if typ:ispointertostruct() then
                    typ,iterator = typ.type, insertdereference(iterator)
                end
                if not typ:isstruct() or type(typ.metamethods.__for) ~= "function" then
                    diag:reporterror(iterator,"expected a struct with a __for metamethod but found ",typ)
                    return s
                end
                local generator = typ.metamethods.__for
            
                local function bodycallback(...)
                    local exps = List()
                    for i = 1,select("#",...) do
                        local v = select(i,...)
                        exps:insert(asterraexpression(s,v))
                    end
                    env:enterblock()
                    local variables = checkformalparameterlist(s.variables,false)
                    local assign = createassignment(s,variables,exps)
                    local body = checkblock(s.body)
                    env:leaveblock()
                    local stats = createstatementlist(s, List { assign, body })
                    return terra.newquote(stats)
                end
            
                local value = invokeuserfunction(s, "invoking __for", false ,generator,terra.newquote(iterator), bodycallback)
                return asterraexpression(s,value,"statement")
            elseif s:is "ifstat" then
                local br = s.branches:map(checkcondbranch)
                local els = (s.orelse and checkblock(s.orelse))
                return s:copy{ branches = br, orelse = els }
            elseif s:is "repeatstat" then
                local stmts = checkstmts(s.statements)
                local e = checkcond(s.condition)
                return s:copy { statements = stmts, condition = e }
            elseif s:is "defvar" then
                local rhs = s.hasinit and checkexpressions(s.initializers)
                local lhs = checkformalparameterlist(s.variables, not s.hasinit)
                local res = s.hasinit and createassignment(s,lhs,rhs) 
                            or createstatementlist(s,lhs)
                return res
            elseif s:is "assignment" then
                local rhs = checkexpressions(s.rhs)
                local lhs = checkexpressions(s.lhs,"lexpression")
                return createassignment(s,lhs,rhs)
            elseif s:is "apply" then
                return checkapply(s,"statement")
            elseif s:is "method" then
                return checkmethod(s,"statement")
            elseif s:is "defer" then
                local call = checkexp(s.expression)
                if not call:is "apply" then
                    diag:reporterror(s.expression,"deferred statement must resolve to a function call")
                end
                return s:copy { expression = call }
            else
                return checkexp(s,"statement")
            end
            error("NYI - "..s.kind,2)
        end
        local newstats = List()
        local function addstat(s)
            if s.kind == "letin" then --let blocks are collapsed into surrounding scope
                newstats:insertall(s.statements)
                newstats:insertall(s.expressions)
            else
                newstats:insert(s)
            end
        end 
        for _,s in ipairs(stmts) do
            local r = checksingle(s)
            if r.kind == "statlist" then -- lists of statements are spliced directly into the list
                for _,rr in ipairs(r.statements) do
                    addstat(rr)
                end
            else addstat(r) end
        end
        return newstats
    end
    local function checkreturns(body,returntype)
        local returnstats = List()
        local function copytree(tree,newfields)
            local r = copyobject(tree,newfields)
            r.type,r.lvalue = tree.type,tree.lvalue
            return r
        end
        local visitlist,visittree,visit
        function visitlist(list)
            local newlist --created when the first change is found
            for i,e in ipairs(list) do
                local ee = visittree(e)
                if not newlist and e ~= ee then
                    newlist = List()
                    for j = 1,i-1 do
                        newlist[j] = list[j]
                    end
                end
                if newlist then
                    newlist[i] = ee
                end
            end
            return newlist or list
        end
        function visittree(tree)
            if T.returnstat:isclassof(tree) then
                local rs = copyobject(tree, {expression = visit(tree.expression) }) -- copy will be mutated later to insert casts
                returnstats:insert(rs)
                return rs
            end
            local newfields
            for _,f in ipairs(tree.__fields) do
                local field = tree[f.name]
                local newfield = visit(field)
                if newfield ~= field then
                    if not newfields then
                        newfields = {}
                    end
                    newfields[f.name] = newfield
                end
            end
            return newfields and copytree(tree,newfields) or tree
        end
        function visit(tree)
            if List:isclassof(tree) then
                return visitlist(tree)
            elseif T.tree:isclassof(tree) then
                return visittree(tree)
            end
            return tree
        end
        local newbody = visit(body)
        assert(#returnstats == 0 and newbody == body or #returnstats > 0 and newbody ~= body)
        if not returntype then
            if #returnstats == 0 then
                returntype = terra.types.unit
            else
                returntype = returnstats[1].expression.type
                for i = 2,#returnstats do
                    local rs = returnstats[i]
                    returntype = typemeet(rs.expression,returntype,rs.expression.type)
                end
            end
            assert(returntype)
        end
        for _,rs in ipairs(returnstats) do
            rs.expression = insertcast(rs.expression,returntype) -- mutation is safe because we just made a unique copy of any parents
        end
        return newbody, returntype
    end

    local result
    if topexp:is "functiondefu" then
        local typed_parameters = checkformalparameterlist(topexp.parameters, true)
        local parameter_types = typed_parameters:map("type")
        local body,returntype = checkreturns(checkblock(topexp.body),topexp.returntype)
        
        local fntype = terra.types.functype(parameter_types,returntype,false):tcompletefunction(topexp)
        diag:finishandabortiferrors("Errors reported during typechecking.",2)
        local labeldepths,globalsused = semanticcheck(diag,typed_parameters,body)
        result = newobject(topexp,T.functiondef,nil,fntype,typed_parameters,topexp.is_varargs, body, labeldepths, globalsused)
    else
        result = checkexp(topexp)
    end
    diag:finishandabortiferrors("Errors reported during typechecking.",2)
    return result
end
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

local internalizedfiles = {}
local function fileparts(path)
    local fileseparators = ffi.os == "Windows" and "\\/" or "/"
    local pattern = "[%s]([^%s]*)"
    return path:gmatch(pattern:format(fileseparators,fileseparators))
end
function terra.registerinternalizedfiles(names,contents,sizes)
    names,contents,sizes = ffi.cast("const char **",names),ffi.cast("uint8_t **",contents),ffi.cast("int*",sizes)
    for i = 0,math.huge do
        if names[i] == nil then break end
        local name,content,size = ffi.string(names[i]),contents[i],sizes[i]
        local cur = internalizedfiles
        for segment in fileparts(name) do
            cur.children = cur.children or {}
            cur.kind = "directory"
            if not cur.children[segment] then
                cur.children[segment] = {} 
            end
            cur = cur.children[segment]
        end
        cur.contents,cur.size,cur.kind =  terra.pointertolightuserdata(content), size, "file"
    end
end

local function getinternalizedfile(path)
    local cur = internalizedfiles
    for segment in fileparts(path) do
        if cur.children and cur.children[segment] then
            cur = cur.children[segment]
        else return end
    end
    return cur
end

local clangresourcedirectory = "$CLANG_RESOURCE$"
local function headerprovider(path)
    if path:sub(1,#clangresourcedirectory) == clangresourcedirectory then
        return getinternalizedfile(path)
    end
end



function terra.includecstring(code,cargs,target)
    local args = terra.newlist {"-O3","-Wno-deprecated","-resource-dir",clangresourcedirectory}
    target = target or terra.nativetarget

    if (target == terra.nativetarget and ffi.os == "Linux") or (target.Triple and target.Triple:match("linux")) then
        args:insert("-internal-isystem")
        args:insert(clangresourcedirectory.."/include")
    end
    for _,path in ipairs(terra.systemincludes) do
    	args:insert("-internal-isystem")
    	args:insert(path)
    end
    
    if cargs then
        args:insertall(cargs)
    end
    for p in terra.includepath:gmatch("([^;]+);?") do
        args:insert("-I")
        args:insert(p)
    end
    assert(terra.istarget(target),"expected a target or nil to specify the native target")
    local result = terra.registercfile(target,code,args,headerprovider)
    local general,tagged,errors,macros = result.general,result.tagged,result.errors,result.macros
    local mt = { __index = includetableindex, errors = result.errors }
    local function addtogeneral(tbl)
        for k,v in pairs(tbl) do
            if not general[k] then
                general[k] = v
            end
        end
    end
    addtogeneral(tagged)
    addtogeneral(macros)
    setmetatable(general,mt)
    setmetatable(tagged,mt)
    return general,tagged,macros
end
function terra.includec(fname,cargs,target)
    return terra.includecstring("#include \""..fname.."\"\n",cargs,target)
end


-- GLOBAL MACROS
terra.sizeof = terra.internalmacro(
function(diag,tree,typ)
    return typecheck(newobject(tree,T.sizeof,typ:astype()))
end,
function (terratype,...)
    terratype:complete()
    return terra.llvmsizeof(terra.jitcompilationunit,terratype)
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
    return typecheck(newobject(tree,T.vectorconstructor,nil,List{...}))
end,
terra.types.vector
)
_G["vectorof"] = terra.internalmacro(function(diag,tree,typ,...)
    return typecheck(newobject(tree,T.vectorconstructor,typ:astype(),List{...}))
end)
_G["array"] = terra.internalmacro(function(diag,tree,...)
    return typecheck(newobject(tree,T.arrayconstructor,nil,List{...}))
end)
_G["arrayof"] = terra.internalmacro(function(diag,tree,typ,...)
    return typecheck(newobject(tree,T.arrayconstructor,typ:astype(),List{...}))
end)

local function createunpacks(tupleonly)
    local function unpackterra(diag,tree,obj,from,to)
        local typ = obj:gettype()
        if not obj or not typ:isstruct() or (tupleonly and typ.convertible ~= "tuple") then
            return obj
        end
        if not obj:islvalue() then diag:reporterror("expected an lvalue") end
        local result = terralib.newlist()
        local entries = typ:getentries()
        from = from and tonumber(from:asvalue()) or 1
        to = to and tonumber(to:asvalue()) or #entries
        for i = from,to do 
            local e= entries[i]
            if e.field then
                local ident = newobject(tree,type(e.field) == "string" and T.namedident or T.labelident,e.field)
                result:insert(typecheck(newobject(tree,T.selectu,obj,ident)))
            end
        end
        return result
    end
    local function unpacklua(cdata,from,to)
        local t = type(cdata) == "cdata" and terra.typeof(cdata)
        if not t or not t:isstruct() or (tupleonly and t.convertible ~= "tuple") then 
          return cdata
        end
        local results = terralib.newlist()
        local entries = t:getentries()
        for i = tonumber(from) or 1,tonumber(to) or #entries do
            local e = entries[i]
            if e.field then
                local nm = terra.islabel(e.field) and e.field:tocname() or e.field
                results:insert(cdata[nm])
            end
        end
        return unpack(results)
    end
    return unpackterra,unpacklua
end
terra.unpackstruct = terra.internalmacro(createunpacks(false))
terra.unpacktuple = terra.internalmacro(createunpacks(true))

_G["unpackstruct"] = terra.unpackstruct
_G["unpacktuple"] = terra.unpacktuple
_G["tuple"] = terra.types.tuple
_G["global"] = terra.global

terra.select = terra.internalmacro(function(diag,tree,guard,a,b)
    return typecheck(newobject(tree,T.operator,"select", List { guard, a, b }))
end)
terra.debuginfo = terra.internalmacro(function(diag,tree,filename,linenumber)
    local customfilename,customlinenumber = tostring(filename:asvalue()), tonumber(linenumber:asvalue())
    return newobject(tree,T.debuginfo,customfilename,customlinenumber):withtype(terra.types.unit)
end)

local function createattributetable(q)
    local attr = q:asvalue()
    if type(attr) ~= "table" then
        error("attributes must be a table, not a " .. type(attr))
    end
    return T.attr(attr.nontemporal and true or false, 
                  type(attr.align) == "number" and attr.align or nil,
                  attr.isvolatile and true or false)
end

terra.attrload = terra.internalmacro( function(diag,tree,addr,attr)
    if not addr or not attr then
        error("attrload requires two arguments")
    end
    return typecheck(newobject(tree,T.attrload,addr,createattributetable(attr)))
end)

terra.attrstore = terra.internalmacro( function(diag,tree,addr,value,attr)
    if not addr or not value or not attr then
        error("attrstore requires three arguments")
    end
    return typecheck(newobject(tree,T.attrstore,addr,value,createattributetable(attr)))
end)


-- END GLOBAL MACROS

-- DEBUG

function prettystring(toptree,breaklines)
    breaklines = breaklines == nil or breaklines
    local buffer = terralib.newlist() -- list of strings that concat together into the pretty output
    local env = terra.newenvironment({})
    local indentstack = terralib.newlist{ 0 } -- the depth of each indent level
    
    local currentlinelength = 0
    local function enterblock()
        indentstack:insert(indentstack[#indentstack] + 4)
    end
    local function enterindenttocurrentline()
        indentstack:insert(currentlinelength)
    end
    local function leaveblock()
        indentstack:remove()
    end
    local function emit(fmt,...)
        local function toformat(x)
            if type(x) ~= "number" and type(x) ~= "string" then
                return tostring(x) 
            else
                return x
            end
        end
        local strs = terra.newlist({...}):map(toformat)
        local r = fmt:format(unpack(strs))
        currentlinelength = currentlinelength + #r
        buffer:insert(r)
    end
    local function pad(str,len)
        if #str > len then return str:sub(-len)
        else return str..(" "):rep(len - #str) end
    end
    local function differentlocation(a,b)
        return (a.linenumber ~= b.linenumber or a.filename ~= b.filename)
    end 
    local lastanchor = { linenumber = "", filename = "" }
    local function begin(anchor,...)
        local fname = differentlocation(lastanchor,anchor) and (anchor.filename..":"..anchor.linenumber..": ")
                                                           or ""
        emit("%s",pad(fname,24))
        currentlinelength = 0
        emit((" "):rep(indentstack[#indentstack]))
        emit(...)
        lastanchor = anchor
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
        emit("%s",t)
    end

    local function UniqueName(name,key)
        assert(name) assert(key)
        local lenv = env:localenv()
        local assignedname = lenv[key]
        --if we haven't seen this key in this scope yet, assign a name for this key, favoring the non-mangled name
        if not assignedname then
            local basename,i = name,1
            while lenv[name] do
                name,i = basename.."$"..tostring(i),i+1
            end
            lenv[name],lenv[key],assignedname = true,name,name
        end
        return assignedname
    end
    local function emitIdent(name,sym)
        assert(name) assert(terra.issymbol(sym))
        emit("%s",UniqueName(name,sym))
    end
    local luaexpression = "[ <lua exp> ]"
    local function IdentToString(ident)
        if ident.kind == "luaexpression" then return luaexpression
        else return tostring(ident.value) end
    end
    local function emitParam(p)
        assert(T.allocvar:isclassof(p) or T.param:isclassof(p))
        if T.unevaluatedparam:isclassof(p) then 
            emit("%s%s",IdentToString(p.name),p.type and " : "..luaexpression or "")
        else
            emitIdent(p.name,p.symbol) 
            if p.type then emit(" : %s",p.type) end
        end
    end
    local implicitblock = { repeatstat = true, fornum = true, fornumu = true}
    local emitStmt, emitExp,emitParamList,emitLetIn
    local function emitStmtList(lst) --nested Blocks (e.g. from quotes need "do" appended)
        for i,ss in ipairs(lst) do
            if ss:is "block" and not (#ss.statements == 1 and implicitblock[ss.statements[1].kind]) then
                begin(ss,"do\n")
                emitStmt(ss)
                begin(ss,"end\n")
            else
                emitStmt(ss)
            end
        end
    end
    local function emitAttr(a)
        emit("{ nontemporal = %s, align = %s, isvolatile = %s }",a.nontemporal,a.alignment or "native",a.isvolatile)
    end
    function emitStmt(s)
        if s:is "block" then
            enterblock()
            env:enterblock()
            emitStmtList(s.statements)
            env:leaveblock()
            leaveblock()
        elseif s:is "returnstat" then
            begin(s,"return ")
            emitExp(s.expression)
            emit("\n")
        elseif s:is "label" then
            begin(s,"::%s::\n",IdentToString(s.label))
        elseif s:is "gotostat" then
            begin(s,"goto %s\n",IdentToString(s.label))
        elseif s:is "breakstat" then
            begin(s,"break\n")
        elseif s:is "whilestat" then
            begin(s,"while ")
            emitExp(s.condition)
            emit(" do\n")
            emitStmt(s.body)
            begin(s,"end\n")
        elseif s:is "repeatstat" then
            begin(s,"repeat\n")
            enterblock()
            emitStmtList(s.statements)
            leaveblock()
            begin(s.condition,"until ")
            emitExp(s.condition)
            emit("\n")
        elseif s:is "fornum"or s:is "fornumu" then
            begin(s,"for ")
            emitParam(s.variable)
            emit(" = ")
            emitExp(s.initial) emit(",") emitExp(s.limit) 
            if s.step then emit(",") emitExp(s.step) end
            emit(" do\n")
            emitStmt(s.body)
            begin(s,"end\n")
        elseif s:is "forlist" then
            begin(s,"for ")
            emitList(s.variables,"",", ","",emitParam)
            emit(" in ")
            emitExp(s.iterator)
            emit(" do\n")
            emitStmt(s.body)
            begin(s,"end\n")
        elseif s:is "ifstat" then
            for i,b in ipairs(s.branches) do
                if i == 1 then
                    begin(b,"if ")
                else
                    begin(b,"elseif ")
                end
                emitExp(b.condition)
                emit(" then\n")
                emitStmt(b.body)
            end
            if s.orelse then
                begin(s.orelse,"else\n")
                emitStmt(s.orelse)
            end
            begin(s,"end\n")
        elseif s:is "defvar" then
            begin(s,"var ")
            emitList(s.variables,"",", ","",emitParam)
            if s.hasinit then
                emit(" = ")
                emitParamList(s.initializers)
            end
            emit("\n")
        elseif s:is "assignment" then
            begin(s,"")
            emitParamList(s.lhs)
            emit(" = ")
            emitParamList(s.rhs)
            emit("\n")
        elseif s:is "defer" then
            begin(s,"defer ")
            emitExp(s.expression)
            emit("\n")
        elseif s:is "statlist" then
            emitStmtList(s.statements)
        else
            begin(s,"")
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
     "@",9,"&",9,"not",9,"select",12)
    
    local function getprec(e)
        if e:is "operator" then
            if "-" == e.operator and #e.operands == 1 then return 9 --unary minus case
            else return prectable[e.operator] end
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

    function emitExp(e,maybeastatement)
        if breaklines and differentlocation(lastanchor,e)then
            local ll = currentlinelength
            emit("\n")
            begin(e,"")
            emit((" "):rep(ll - currentlinelength))
            lastanchor = e
        end
        if e:is "var" then
            if e.symbol then emitIdent(e.name,e.symbol)
            else emit("%s",e.name) end
        elseif e:is "globalvalueref" and e.value.kind == "globalvariable" then
            emitIdent(e.name,e.value.symbol)
        elseif e:is "globalvalueref" and e.value.kind == "terrafunction" then
            emit(e.value.name)
        elseif e:is "allocvar" then
            emit("var ")
            emitParam(e)
        elseif e:is "setter" then
            emit("<setter:") emitExp(e.setter) emit(">")
        elseif e:is "setteru" then emit("<setteru>")
        elseif e:is "operator" then
            local op = e.operator
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
                emit("<??operator:"..op.."??>")
            end
        elseif e:is "index" then
            doparens(e,e.value)
            emit("[")
            emitExp(e.index)
            emit("]")
        elseif e:is "literal" then
            if e.type:isintegral() then
                emit(e.stringvalue or "<int>")
            elseif type(e.value) == "string" then
                emit("%s",("%q"):format(e.value):gsub("\\\n","\\n"))
            else
                emit("%s",tostring(e.value))
            end
        elseif e:is "cast" or e:is "structcast" then
            emit("[")
            emitType(e.to or e.type)
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
        elseif e:is "selectu" or e:is "select" then
            doparens(e,e.value)
            emit(".")
            emit("%s",e.fieldname or IdentToString(e.field))
        elseif e:is "vectorconstructor" then
            emit("vector(")
            emitParamList(e.expressions)
            emit(")")
        elseif e:is "arrayconstructor" then
            emit("array(")
            emitParamList(e.expressions)
            emit(")")
        elseif e:is "constructor" then
            local success,keys = pcall(function() return e.type:getlayout().entries:map(function(e) return tostring(e.key) end) end)
            if not success then emit("<layouttypeerror> = ") 
            else emitList(keys,"",", "," = ",emit) end
            emitParamList(e.expressions)
        elseif e:is "constructoru" then
            emit("{")
            local function emitField(r)
                if r.type == "recfield" then
                    emit("%s = ",IdentToString(r.key))
                end
                emitExp(r.value)
            end
            emitList(e.records,"",", ","",emitField)
            emit("}")
        elseif e:is "constant" then
            if e.type:isprimitive() then
                emit("%s",tostring(tonumber(e.value)))
            else
                emit("<constant:"..tostring(e.type)..">")
            end
        elseif e:is "letin" then
            emitLetIn(e)
        elseif e:is "attrload" then
            emit("attrload(")
            emitExp(e.address)
            emit(", ")
            emitAttr(e.attrs)
            emit(")")
        elseif e:is "attrstore" then
            emit("attrstore(")
            emitExp(e.address)
            emit(", ")
            emitExp(e.value)
            emit(", ")
            emitAttr(e.attrs)
            emit(")")
        elseif e:is "luaobject" then
            if terra.types.istype(e.value) then
                emit("[%s]",e.value)
            elseif terra.ismacro(e.value) then
                emit("<macro>")
            elseif terra.isoverloadedfunction(e.value) then
                emit("%s",e.name)
            else
                emit("<lua value: %s>",tostring(e.value))
            end
        elseif e:is "method" then
             doparens(e,e.value)
             emit(":%s",IdentToString(e.name))
             emit("(")
             emitParamList(e.arguments)
             emit(")")
        elseif e:is "debuginfo" then
            emit("debuginfo(%q,%d)",e.customfilename,e.customlinenumber)
        elseif e:is "inlineasm" then
            emit("inlineasm(")
            emitType(e.type)
            emit(",%s,%s,%s,",e.asm,tostring(e.volatile),e.constraints)
            emitParamList(e.arguments)
            emit(")")
        elseif e:is "quote" then
            emitExp(e.tree)
        elseif e:is "luaexpression" then return luaexpression
        elseif maybeastatement then
            emitStmt(e)
        else
            emit("<??"..e.kind.."??>")
            error("??"..tostring(e.kind))
        end
    end
    function emitParamList(pl)
        emitList(pl,"",", ","",emitExp)
    end
    function emitLetIn(pl)
        if pl.hasstatements then
            enterindenttocurrentline()
            emit("let\n")
            enterblock()
            emitStmtList(pl.statements)
            leaveblock()
            begin(pl,"in\n")
            enterblock()
            begin(pl,"")
        end
        emitList(pl.expressions,"",", ","",emitExp)
        if pl.hasstatements then
            leaveblock()
            emit("\n")
            begin(pl,"end")
            leaveblock()
        end
    end
    if T.functiondef:isclassof(toptree) or T.functiondefu:isclassof(toptree) then
        begin(toptree,"terra %s",toptree.name or "<anon>")
        emitList(toptree.parameters,"(",",",") ",emitParam)
        if T.functiondef:isclassof(toptree) then
            emit(": ") emitType(toptree.type.returntype)
        elseif toptree.returntype then
            emit(": ")
            if T.Type:isclassof(toptree.returntype) then emitType(toptree.returntype)
            else emitExp(toptree.returntype) end
        end
        emit("\n")
        emitStmt(toptree.body)
        begin(toptree,"end\n")
    elseif T.functionextern:isclassof(toptree) then
        begin(toptree,"terra %s :: %s = <extern>\n",toptree.name,toptree.type)
    else
        emitExp(toptree,true)
        emit("\n")
    end
    return buffer:concat()
end

function T.terrafunction:prettystring(breaklines)
    if not self:isdefined() then
        return ("terra %s :: %s\n"):format(self.name,tostring(self.type))
    end
    return prettystring(self.definition,breaklines)
end
function T.terrafunction:printpretty(bl) io.write(self:prettystring(bl)) end
function T.terrafunction:__tostring() return self:prettystring(false) end
function T.quote:prettystring(breaklines) return prettystring(self.tree,breaklines) end
function T.quote:printpretty(bl) io.write(self:prettystring(bl)) end
function T.quote:__tostring() return self:prettystring(false) end

-- END DEBUG

local allowedfilekinds = { object = true, executable = true, bitcode = true, llvmir = true, sharedlibrary = true, asm = true }
local mustbefile = { sharedlibrary = true, executable = true }
function compilationunit:saveobj(filename,filekind,arguments,optimize)
    if filekind ~= nil and type(filekind) ~= "string" then
        --filekind is missing, shift arguments to the right
        filekind,arguments,optimize = nil,filekind,arguments
    end

    if optimize == nil then
        optimize = true
    end

    if filekind == nil and filename ~= nil then
        --infer filekind from string
        if filename:match("%.o$") then
            filekind = "object"
        elseif filename:match("%.bc$") then
            filekind = "bitcode"
        elseif filename:match("%.ll$") then
            filekind = "llvmir"
        elseif filename:match("%.so$") or filename:match("%.dylib$") or filename:match("%.dll$") then
            filekind = "sharedlibrary"
        elseif filename:match("%.s") then
            filekind = "asm"
        else
            filekind = "executable"
        end
    end
    if not allowedfilekinds[filekind] then
        error("unknown output format type: " .. tostring(filekind))
    end
    if filename == nil and mustbefile[filekind] then
        error(filekind .. " must be written to a file")
    end
    return terra.saveobjimpl(filename,filekind,self,arguments or {},optimize)
end

function terra.saveobj(filename,filekind,env,arguments,target,optimize)
    if type(filekind) ~= "string" then
        filekind,env,arguments,target,optimize = nil,filekind,env,arguments,target
    end
    local cu = terra.newcompilationunit(target or terra.nativetarget,false)
    for k,v in pairs(env) do
        if not T.globalvalue:isclassof(v) then error("expected terra global or function but found "..terra.type(v)) end
        cu:addvalue(k,v)
    end
    local r = cu:saveobj(filename,filekind,arguments,optimize)
    cu:free()
    return r
end


-- configure path variables
terra.cudahome = os.getenv("CUDA_HOME") or (ffi.os == "Windows" and os.getenv("CUDA_PATH")) or "/usr/local/cuda"
terra.cudalibpaths = ({ OSX = {driver = "/usr/local/cuda/lib/libcuda.dylib", runtime = "$CUDA_HOME/lib/libcudart.dylib", nvvm =  "$CUDA_HOME/nvvm/lib/libnvvm.dylib"}; 
                       Linux =  {driver = "libcuda.so", runtime = "$CUDA_HOME/lib64/libcudart.so", nvvm = "$CUDA_HOME/nvvm/lib64/libnvvm.so"}; 
                       Windows = {driver = "nvcuda.dll", runtime = "$CUDA_HOME\\bin\\cudart64_*.dll", nvvm = "$CUDA_HOME\\nvvm\\bin\\nvvm64_*.dll"}; })[ffi.os]
-- OS's that are not supported by CUDA will have an undefined value here
if terra.cudalibpaths then
	for name,path in pairs(terra.cudalibpaths) do
		path = path:gsub("%$CUDA_HOME",terra.cudahome)
		if path:match("%*") and ffi.os == "Windows" then
			local F = io.popen(('dir /b /s "%s" 2> nul'):format(path))
			if F then
				path = F:read("*line") or path
				F:close()
			end
		end
		terra.cudalibpaths[name] = path
	end
end                       

terra.systemincludes = List()
if ffi.os == "Windows" then
    -- this is the reason we can't have nice things
    local function registrystring(key,value,default)
    	local F = io.popen( ([[reg query "%s" /v "%s"]]):format(key,value) )
		local result = F and F:read("*all"):match("REG_SZ%W*([^\n]*)\n")
		return result or default
	end
	terra.vshome = registrystring([[HKLM\Software\WOW6432Node\Microsoft\VisualStudio\12.0]],"ShellFolder",[[C:\Program Files (x86)\Microsoft Visual Studio 12.0\VC\]])
	local windowsdk = registrystring([[HKLM\SOFTWARE\Wow6432Node\Microsoft\Microsoft SDKs\Windows\v8.1]],"InstallationFolder",[[C:\Program Files (x86)\Windows Kits\8.1\]])	

	terra.systemincludes:insertall {
		("%sVC/INCLUDE"):format(terra.vshome),
		("%sVC/ATLMFC/INCLUDE"):format(terra.vshome),
		("%sinclude/shared"):format(windowsdk),
		("%sinclude/um"):format(windowsdk),
		("%sinclude/winrt"):format(windowsdk),
		("%s/include"):format(terra.cudahome)
	}

    function terra.getvclinker() --get the linker, and guess the needed environment variables for Windows if they are not set ...
        local linker = terra.vshome..[[VC\BIN\x86_amd64\link.exe]]
        local vclib = terra.vclib or string.gsub([[%VC\LIB\amd64;%VC\ATLMFC\LIB\amd64;C:\Program Files (x86)\Windows Kits\8.1\lib\winv6.3\um\x64;]],"%%",terra.vshome)
        local vcpath = terra.vcpath or (os.getenv("Path") or "")..";"..terra.vshome..[[VC\BIN;]]
        vclib,vcpath = "LIB="..vclib,"Path="..vcpath
        return linker,vclib,vcpath
    end
end


-- path to terra install, normally this is figured out based on the location of Terra shared library or binary
local defaultterrahome = ffi.os == "Windows" and "C:\\Program Files\\terra" or "/usr/local"
terra.terrahome = os.getenv("TERRA_HOME") or terra.terrahome or defaultterrahome
local terradefaultpath =  ffi.os == "Windows" and ";.\\?.t;"..terra.terrahome.."\\include\\?.t;"
                          or ";./?.t;"..terra.terrahome.."/share/terra/?.t;"

package.terrapath = (os.getenv("TERRA_PATH") or ";;"):gsub(";;",terradefaultpath)

local function terraloader(name)
    local fname = name:gsub("%.","/")
    local file = nil
    local loaderr = ""
    for template in package.terrapath:gmatch("([^;]+);?") do
        local fpath = template:gsub("%?",fname)
        local handle = io.open(fpath,"r")
        if handle then
            file = fpath
            handle:close()
            break
        end
        loaderr = loaderr .. "\n\tno file '"..fpath.."'"
    end
    local function check(fn,err) return fn or error(string.format("error loading terra module %s from file %s:\n\t%s",name,file,err)) end
    if file then return check(terra.loadfile(file)) end
    -- if we didn't find the file on the real file system, see if it is included in the binary itself
    file = ("/?.t"):gsub("%?",fname)
    local internal = getinternalizedfile(file)
    if internal and internal.kind == "file" then
        local str,done = ffi.string(ffi.cast("const char *",internal.contents)),false
        local fn,err = terra.load(function()
            if not done then
                done = true
                return str
            end
        end,file)
        return check(fn,err)
    else
        loaderr = loaderr .. "\n\tno internal file '"..file.."'"
    end
    return loaderr
end
table.insert(package.loaders,terraloader)

function terra.makeenv(env,defined,g)
    local mt = { __index = function(self,idx)
        if defined[idx] then return nil -- local variable was defined and was nil, the search ends here
        elseif getmetatable(g) == Strict then return rawget(g,idx) else return g[idx] end
    end }
    return setmetatable(env,mt)
end

function terra.new(terratype,...)
    terratype:complete()
    local typ = terratype:cstring()
    return ffi.new(typ,...)
end
function terra.offsetof(terratype,field)
    terratype:complete()
    local typ = terratype:cstring()
    if terra.islabel(field) then
        field = field:tocname()
    end
    return ffi.offsetof(typ,field)
end

function terra.cast(terratype,obj)
    terratype:complete()
    local ctyp = terratype:cstring()
    return ffi.cast(ctyp,obj)
end

function terra.constant(typ,init)
    if typ ~= nil and not terra.types.istype(typ) then -- if typ is not a typ, shift arguments
        typ,init = nil,typ
    end
    if typ == nil then --try to infer the type, and if successful build the constant
        if type(init) == "cdata" then
            typ = terra.typeof(init)
        elseif type(init) == "number" then
            typ = (terra.isintegral(init) and terra.types.int) or terra.types.double
        elseif type(init) == "boolean" then
            typ = terra.types.bool
        elseif type(init) == "string" then
            typ = terra.types.rawstring
        elseif T.quote:isclassof(init) then
            typ = init:gettype()
        else
            error("constant constructor requires explicit type for objects of type "..terra.type(init))
        end
    end
    if init == nil or T.quote:isclassof(init) then -- cases: no init, quote init -> global constant
        return terra.global(typ,init,"<constant>",false,true)
    end
    local anchor = terra.newanchor(2)
    if type(init) == "string" and typ == terra.types.rawstring then
        return terra.newquote(newobject(anchor,T.literal,init,typ))
    end
    local orig = init -- hold anchor until we capture the value
    if type(init) ~= "cdata" or terra.typeof(init) ~= typ then
        init = terra.cast(typ,init)
    end
    if not typ:isaggregate() then
        return terra.newquote(newobject(anchor,T.constant,init,typ))
    end -- otherwise this is an aggregate pack it into a string literal
    local str,ptyp = ffi.string(init,terra.sizeof(typ)),terra.types.pointer(typ)
    local tree = newobject(anchor,T.literal,str,terra.types.rawstring) -- "literal"
    tree = newobject(anchor,T.cast,ptyp,tree):withtype(ptyp) -- [&typ](literal)
    tree = newobject(anchor,T.operator,"@", List { tree }):withtype(typ):setlvalue(true) -- @[&typ](literal)
    return terra.newquote(tree)
end
function terra.isconstant(obj)
    if T.globalvariable:isclassof(obj) then return obj:isconstant()
    elseif T.quote:isclassof(obj) then return obj.tree.kind == "literal" or obj.tree.kind == "constant"
    else return false end
end
_G["constant"] = terra.constant

-- equivalent to ffi.typeof, takes a cdata object and returns associated terra type object
function terra.typeof(obj)
    if type(obj) ~= "cdata" then
        error("cannot get the type of a non cdata object")
    end
    return terra.types.ctypetoterra[tonumber(ffi.typeof(obj))]
end

--equivalent to Lua's type function, but knows about concepts in Terra to improve error reporting
function terra.type(t)
    if terra.isfunction(t) then return "terrafunction"
    elseif terra.types.istype(t) then return "terratype"
    elseif terra.ismacro(t) then return "terramacro"
    elseif terra.isglobalvar(t) then return "terraglobalvariable"
    elseif terra.isquote(t) then return "terraquote"
    elseif terra.istree(t) then return "terratree"
    elseif terra.islist(t) then return "list"
    elseif terra.issymbol(t) then return "terrasymbol"
    elseif terra.isfunction(t) then return "terrafunction"
    elseif terra.islabel(t) then return "terralabel"
    elseif terra.isoverloadedfunction(t) then return "overloadedterrafunction"
    else return type(t) end
end

function terra.linklibrary(filename)
    assert(not filename:match("%.bc$"), "linklibrary no longer supports llvm bitcode, use terralib.linkllvm instead.")
    terra.linklibraryimpl(filename)
end
function terra.linkllvm(filename,target,fromstring)
    target = target or terra.nativetarget
    assert(terra.istarget(target),"expected a target or nil to specify native target")
    terra.linkllvmimpl(target.llvm_target,filename, fromstring)
    return { extern = function(self,name,typ) return terra.externfunction(name,typ) end }
end
function terra.linkllvmstring(str,target) return terra.linkllvm(str,target,true) end

terra.languageextension = {
    tokentype = {}; --metatable for tokentype objects
    tokenkindtotoken = {}; --map from token's kind id (terra.kind.name), to the singleton table (terra.languageextension.name) 
}

function terra.importlanguage(languages,entrypoints,langstring)
    local success,lang = xpcall(function() return require(langstring) end,function(err) return debug.traceback(err,2) end)
    if not success then error(lang,0) end
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
        terra.languageextension.tokenkindtotoken[name] = tbl
    end
end

function terra.runlanguage(lang,cur,lookahead,next,embeddedcode,source,isstatement,islocal)
    local lex = {}
    
    lex.name = terra.languageextension.name
    lex.string = terra.languageextension.string
    lex.number = terra.languageextension.number
    lex.eof = terra.languageextension.eof
    lex.default = terra.languageextension.default

    lex._references = terra.newlist()
    lex.source = source

    local function maketoken(tok)
        local specialtoken = terra.languageextension.tokenkindtotoken[tok.type]
        if specialtoken then
            tok.type = specialtoken
        end
        if type(tok.value) == "userdata" then -- 64-bit number in pointer
            tok.value = terra.cast(terra.types.pointer(tok.valuetype),tok.value)[0]
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
    local function doembeddedcode(self,isterra,isexp)
        self._cur,self._lookahead = nil,nil --parsing an expression invalidates our lua representations 
        local expr = embeddedcode(isterra,isexp)
        return function(env)
            local oldenv = getfenv(expr)
            setfenv(expr,env)
            local function passandfree(...)
                setfenv(expr,oldenv)
                return ...
            end
            return passandfree(expr())
        end
    end
    function lex:luaexpr() return doembeddedcode(self,false,true) end
    function lex:luastats() return doembeddedcode(self,false,false) end
    function lex:terraexpr() return doembeddedcode(self,true,true) end
    function lex:terrastats() return doembeddedcode(self,true,false) end

    function lex:ref(name)
        if type(name) ~= "string" then
            error("references must be identifiers")
        end
        self._references:insert(name)
    end

    function lex:typetostring(name)
        return name
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
    return typecheck(newobject(anchor,T.operator,opv,List{...}))
end)
--called by tcompiler.cpp to convert userdata pointer to stacktrace function to the right type;
function terra.initdebugfns(traceback,backtrace,lookupsymbol,lookupline,disas)
    local P,FP = terra.types.pointer, terra.types.funcpointer
    local po = P(terra.types.opaque)
    local ppo = P(po)

    terra.SymbolInfo = terra.types.newstruct("SymbolInfo")
    terra.SymbolInfo.entries = { {"addr", ppo}, {"size", terra.types.uint64}, {"name",terra.types.rawstring}, {"namelength",terra.types.uint64} };
    terra.LineInfo = terra.types.newstruct("LineInfo")
    terra.LineInfo.entries = { {"name",terra.types.rawstring}, {"namelength",terra.types.uint64},{"linenum", terra.types.uint64}};

    terra.traceback = terra.cast(FP({po},{}),traceback)
    terra.backtrace = terra.cast(FP({ppo,terra.types.int,po,po},{terra.types.int}),backtrace)
    terra.lookupsymbol = terra.cast(FP({po,P(terra.SymbolInfo)},{terra.types.bool}),lookupsymbol)
    terra.lookupline   = terra.cast(FP({po,po,P(terra.LineInfo)},{terra.types.bool}),lookupline)
    terra.disas = terra.cast(FP({po,terra.types.uint64,terra.types.uint64},{}),disas)
end

_G["terralib"] = terra --terra code can't use "terra" because it is a keyword

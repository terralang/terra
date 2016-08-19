local List = {}
List.__index = List
for k,v in pairs(table) do
    List[k] = v
end
setmetatable(List, { __call = function(self, lst)
    if lst == nil then
        lst = {}
    end
    return setmetatable(lst,self)
end})
function List:map(fn,...)
    local l = List()
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
function List:insertall(elems)
    for i,e in ipairs(elems) do
        self:insert(e)
    end
end
function List:isclassof(exp)
    return getmetatable(exp) == self
end

local Context = {}
function Context:__index(idx)
    local d = self.definitions[idx] or self.namespaces[idx]
    if d ~= nil then return d end
    return getmetatable(self)[idx]
end

-- prepare lexer stuff
local tokens = "=|?*,(){}."
local keywords = { attributes = true, unique = true, module = true }
for i = 1,#tokens do
    local t = tokens:sub(i,i)
    keywords[t] = true
end
-- parser/lexer function
local function parseAll(text)
    local pos = 1
    local cur = nil -- current token
    local value = nil -- current token value
    local function err(what)
        error(string.format("expected %s but found '%s' here:\n%s",what,value,
              text:sub(1,pos).."<--##    "..text:sub(pos+1,-1)))
    end
    local function skip(pattern)
        local matched = text:match(pattern,pos)
        pos = pos + #matched
        if pos <= #text then
            return false
        end
        cur,value = "EOF","EOF"
        return true
    end
    local function next()
        if skip("^%s*") then return end -- whitespace
        local c = text:sub(pos,pos)
        if c == "#" then -- comment
            if skip("^[^\n]*\n") then return end
            return next()
        end
        if keywords[c] then
            cur,value,pos = c,c,pos+1
            return
        end
        local ident = text:match("^[%a_][%a_%d]*",pos)
        if not ident then
            value = text:sub(pos,pos)
            err("valid token")
        end
        cur,value = keywords[ident] and ident or "Ident", ident
        pos = pos + #ident
    end
    local function nextif(kind)
        if cur ~= kind then return false end
        next()
        return true
    end
    local function expect(kind)
        if kind ~= cur then err(kind) end
        local v = value
        next()
        return v
    end
    
    local namespace = ""
    local function parseDefinedName()
        return namespace..expect("Ident")
    end
    
    local function parseField()
        local  f = {}
        f.type = expect("Ident")
        while nextif(".") do
            f.type = f.type .. "." .. expect("Ident")
        end
        f.namespace = namespace -- for resolving the symbol later
        if nextif("?") then
            f.optional = true
        elseif nextif("*") then
            f.list = true
        end
        f.name = expect("Ident")
        return f
    end
    local function parseFields()
        local fields = List()
        expect("(")
        if cur ~= ")" then
            repeat
                fields:insert(parseField())
            until not nextif(",")
        end
        expect(")")
        return fields
    end
    local function parseProduct()
        local p = { kind = "product", fields = parseFields() }
        p.unique = nextif("unique")
        return p
    end
    local function parseConstructor()
        local c = { name = parseDefinedName() }
        if cur == "(" then
            c.fields = parseFields()
        end
        c.unique = nextif("unique")
        return c
    end
    local function parseSum()
        local sum = { kind = "sum", constructors = List() }
        repeat
            sum.constructors:insert(parseConstructor())
        until not nextif("|")
        if nextif("attributes") then
            local attributes = parseFields()
            for i,ctor in ipairs(sum.constructors) do 
                ctor.fields = ctor.fields or List()
                for i,a in ipairs(attributes) do
                    ctor.fields:insert(a)
                end
            end
        end
        return sum
    end
    
    local function parseType()
        if cur == "(" then
            return parseProduct()
        else
            return parseSum()
        end
    end
    local definitions = List()
    local parseDefinitions
    local function parseModule()
        expect("module")
        local name = expect("Ident")
        expect("{")
        local oldnamespace = namespace
        namespace = namespace..name.."."
        parseDefinitions()
        expect("}")
        namespace = oldnamespace
    end
    local function parseDefinition()
        local d = { name = parseDefinedName() }
        expect("=")
        d.type = parseType()
        d.namespace = namespace
        definitions:insert(d)
    end
    function parseDefinitions()
        while cur ~= "EOF" and cur ~= "}" do
            if cur == "module" then parseModule()
            else parseDefinition() end
        end
    end
    next()
    parseDefinitions()
    expect("EOF")
    return definitions
end

local function checkbuiltin(t)
    return function(v) return type(v) == t end
end

local function checkoptional(checkt)
    return function(v) return v == nil or checkt(v) end
end

local function checklist(checkt)
    return function(vs)
        if not List:isclassof(vs) then return false end
        for i,e in ipairs(vs) do
            if not checkt(e) then return false,i end
        end
        return true
    end
end

local valuekey,nilkey = {},{}
local function checkuniquelist(checkt,listcache)
    return function(vs)
        if not List:isclassof(vs) then return false end
        local node = listcache
        for i,e in ipairs(vs) do
            if not checkt(e) then return false,i end
            local next = node[e]
            if not next then
                next = {}
                node[e] = next
            end
            node = next
        end
        local r = node[valuekey]
        if not r then
            r = vs
            node[valuekey] = r
        end
        return true,r
    end
end

local defaultchecks = {} 
for i in string.gmatch("nil number string boolean table thread userdata cdata function","(%S+)") do
    defaultchecks[i] = checkbuiltin(i)
end
defaultchecks["any"] = function() return true end

local function NewContext()
    return setmetatable({ checks = setmetatable({},{__index = defaultchecks}), members = {}, list = {}, uniquelist = {}, listcache = {}, optional = {}, definitions = {}, namespaces = {}},Context)
end

function Context:GetCheckForField(unique,field)
    local check = assert(self.checks[field.type],string.format("type not defined: %s",field.type))
    local function get(tbl,ctor)
        if not tbl[field.type] then
            tbl[field.type] = ctor(check,self.listcache)
        end
        return tbl[field.type]
    end
    if field.list and not unique then
        return get(self.list,checklist)
    elseif field.list and unique then
        return get(self.uniquelist,checkuniquelist)
    elseif field.optional then
        return get(self.optional,checkoptional)
    end
    return check
end
local function basename(name)
    return name:match("([^.]*)$")
end
function Context:_SetDefinition(name,value)
    local ctx = self.namespaces
    for part in name:gmatch("([^.]*)%.") do
        ctx[part] = ctx[part] or {}
        ctx = ctx[part]
    end
    local base = basename(name)
    ctx[base],self.definitions[name] = value,value
end
function Context:DeclareClass(name)
    assert(not self.definitions[name], "class name already defined")
    local m = {}
    self:_SetDefinition(name,{ members = m })
    self.checks[name] = function(v) return m[getmetatable(v) or false] or false end
end
local function reporterr(i,name,tn,v,ii)
    local fmt = "bad argument #%d to '%s' expected '%s' but found '%s'"
    if ii then
        v,fmt = v[ii],fmt .. " at list index %d"
    end
    local err = string.format(fmt,i,name,tn,type(v),ii)
    local mt = getmetatable(v)
    if mt then
        err = string.format("%s (metatable = %s)",err,tostring(mt))
    end
    error(err,3)
end
function Context:DefineClass(name,unique,fields)
    local mt = {}
    local class = self.definitions[name]
    
    if fields then
        for _,f in ipairs(fields) do 
            if f.namespace then -- resolve field type to fully qualified name
                local fullname = f.namespace..f.type
                if self.definitions[fullname] then
                    f.type = fullname
                end
                f.namespace = nil 
            end
        end
        class.__fields = fields -- for reflection in user-defined behavior
        local names = List()
        local checks = List()
        local tns = List()
        for i,f in ipairs(fields) do
            names:insert(f.name)
            tns:insert(f.list and f.type.."*" or f.type)
            checks:insert(self:GetCheckForField(unique,f))
        end
        
        if unique then
            function mt:__call(...)
                local node,key = self,"cache"
                local obj = {}
                for i = 1, #names do
                    local v = select(i,...)
                    local c,l = checks[i](v)
                    if not c then 
                       reporterr(i,name,tns[i],v,l) 
                    end
                    v = l or v -- use memoized list if it exists
                    obj[names[i]] = v
                    local next = node[key]
                    if not next then
                        next = {}
                        node[key] = next
                    end
                    node,key = next,v
                    if key == nil then
                        key = nilkey
                    end
                end
                local next = node[key]
                if not next then
                    next = setmetatable(obj,self)
                    if next.init then next:init() end
                    node[key] = next
                end
                return next
            end
        else
            function mt:__call(...)
                local obj = {}
                for i = 1, #names do
                    local v = select(i,...)
                    local c,ii = checks[i](v)
                    if not c then 
                       reporterr(i,name,tns[i],v,ii) 
                    end
                    obj[names[i]] = v
                end
                local r = setmetatable(obj,self)
                if r.init then r:init() end
                return r
            end
        end
        function class:__tostring()
            local members = List()
            for i,f in ipairs(fields) do
                local v,r = self[f.name]
                if f.list then
                    local elems = List()
                    for i,e in ipairs(self[f.name]) do
                        elems:insert(tostring(e))
                    end
                    r = "{"..elems:concat(",").."}"
                else
                    r = tostring(v)
                end
                if not (f.optional and v == nil) then
                    members:insert(string.format("%s = %s",f.name,r))
                end
            end
            return string.format("%s(%s)",name,members:concat(","))
        end
    else
        function class:__tostring() return name end
    end
    function mt:__tostring() return string.format("Class(%s)",name) end
    function mt:__newindex(k,v)
        for c,_ in pairs(self.members) do
            rawset(c,k,v)
        end
    end
    local check = assert(self.checks[name])
    function class:isclassof(obj)
        return check(obj)
    end
    class.__index = class
    class.members[class] = true
    setmetatable(class,mt)
    return class
end
function Context:Extern(name,istype)
    self.checks[name] = istype
end

function Context:Define(text)
    local defs = parseAll(text)
    -- register all new type names
    for i,d in ipairs(defs) do
        self:DeclareClass(d.name)
        if d.type.kind == "sum" then
            for i,c in ipairs(d.type.constructors) do
                self:DeclareClass(c.name)
            end
        end
    end
    for i,d in ipairs(defs) do
        if d.type.kind == "sum" then
            local parent = self:DefineClass(d.name,false,nil)
            for i,c in ipairs(d.type.constructors) do
                local child = self:DefineClass(c.name,c.unique,c.fields)
                parent.members[child] = true --mark that any subclass is a member of its parent 
                child.kind = basename(c.name)
                if not c.fields then --single value, just create it
                    self:_SetDefinition(c.name, setmetatable({},child))
                end
            end
        else
            self:DefineClass(d.name,d.type.unique,d.type.fields)
        end
    end
end
package.loaded["asdl"] = { NewContext = NewContext, List = List }
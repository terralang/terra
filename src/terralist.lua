--[[
-- the List type is a plain Lua table with additional methods that come from:
-- 1. all the methods in Lua's 'table' global
-- 2. a list of higher-order functions based on sml's (fairly minimal) list type.

-- For each function that is an argument of a high-order List function can be either:
-- 1. a real Lua function
-- 2. a string of an operator "+" (see op table)
-- 3. a string that specifies a field or method to call on the object
--    local mylist = List { a,b,c }
--    mylist:map("foo") -- selects the fields:  a.foo, b.foo, c.foo, etc.
--                      -- if a.foo is a function it will be treated as a method a:foo()
-- extra arguments to the higher-order function are passed through to these function.
-- rationale: Lua inline function syntax is verbose, this functionality avoids
-- inline functions in many cases

list:sub(i,j) -- Lua's string.sub, but for lists
list:rev() : List[A] -- reverse list
list:app(fn : A -> B) : {} -- app fn to every element
list:map(fn : A -> B) : List[B] -- apply map to every element resulting in new list
list:filter(fn : A -> boolean) : List[A] -- new list with elements were fn(e) is true
list:flatmap(fn : A -> List[B]) : List[B] -- apply map to every element, resulting in lists which are all concatenated together
list:find(fn : A -> boolean) : A? -- find the first element in list satisfying condition
list:partition(fn : A -> {K,V}) : Map[ K,List[V] ] -- apply k,v = fn(e) to each element and group the values 'v' into bin of the same 'k'
list:fold(init : B,fn : {B,A} -> B) -> B -- recurrence fn(a[2],fn(a[1],init)) ...
list:reduce(fn : {B,A} -> B) -> B -- recurrence fn(a[3],fn(a[2],a[1]))
list:reduceor(init : B,fn : {B,A} -> B) -> B -- recurrence fn(a[3],fn(a[2],a[1])) or init if the list is empty
list:exists(fn : A -> boolean) : boolean -- is any fn(e) true in list
list:all(fn : A -> boolean) : boolean -- are all fn(e) true in list

Every function that takes a higher-order function also has a 'i' variant that
Also provides the list index to the function:

list:mapi(fn : {int,A} -> B) -> List[B]
]]

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
function List:isclassof(exp)
    return getmetatable(exp) == self
end
function List:insertall(elems)
    for i,e in ipairs(elems) do
        self:insert(e)
    end
end
function List:rev()
    local l,N = List(),#self
    for i = 1,N do
        l[i] = self[N-i+1]
    end
    return l
end
function List:sub(i,j)
    local N = #self
    if not j then
        j = N
    end
    if i < 0 then
        i = N+i+1
    end
    if j < 0 then
        j = N+j+1
    end
    local l = List()
    for c = i,j do
        l:insert(self[c])
    end
    return l
end
function List:__tostring()
   return ("{%s}"):format(self:map(tostring):concat(","))
end

local OpTable = {
["+"] = function(x,y) return x + y end;
["*"] = function(x,y) return x * y end;
["/"] = function(x,y) return x / y end;
["%"] = function(x,y) return x % y end;
["^"] = function(x,y) return x ^ y end;
[".."] = function(x,y) return x .. y end;
["<"] = function(x,y) return x < y end;
[">"] = function(x,y) return x > y end;
["<="] = function(x,y) return x <= y end;
[">="] = function(x,y) return x >= y end;
["~="] = function(x,y) return x ~= y end;
["~="] = function(x,y) return x == y end;
["and"] = function(x,y) return x and y end;
["or"] = function(x,y) return x or y end;
["not"] = function(x) return not x end;
["-"] = function(x,y)
    if not y then
        return -x
    else
        return x - y
    end
end
}

local function selector(key)
    local fn = OpTable[key]
    if fn then return fn end
    return function(v,...)
        local sel = v[key]
        if type(sel) == "function" then
            return sel(v,...)
        else
            return sel
        end
    end
end
local function selectori(key)
    local fn = OpTable[key]
    if fn then return fn end
    return function(i,v,...)
        local sel = v[key]
        if type(sel) == "function" then
            return sel(i,v,...)
        else
            return sel
        end
    end
end

function List:mapi(fn,...)
    if type(fn) ~= "function" then
        fn = selectori(fn)
    end
    local l = List()
    for i,v in ipairs(self) do
        l[i] = fn(i,v,...)
    end
    return l
end
function List:map(fn,...)
    if type(fn) ~= "function" then
        fn = selector(fn)
    end
    local l = List()
    for i,v in ipairs(self) do
        l[i] = fn(v,...)
    end
    return l
end


function List:appi(fn,...)
    if type(fn) ~= "function" then
        fn = selectori(fn)
    end
    for i,v in ipairs(self) do
        fn(i,v,...)
    end
end
function List:app(fn,...)
    if type(fn) ~= "function" then
        fn = selector(fn)
    end
    for i,v in ipairs(self) do
        fn(v,...)
    end
end


function List:filteri(fn,...)
    if type(fn) ~= "function" then
        fn = selectori(fn)
    end
    local l = List()
    for i,v in ipairs(self) do
        if fn(i,v,...) then
            l:insert(v)
        end
    end
    return l
end
function List:filter(fn,...)
    if type(fn) ~= "function" then
        fn = selector(fn)
    end
    local l = List()
    for i,v in ipairs(self) do
        if fn(v,...) then
            l:insert(v)
        end
    end
    return l
end

function List:flatmapi(fn,...)
    if type(fn) ~= "function" then
        fn = selectori(fn)
    end
    local l = List()
    for i,v in ipairs(self) do
        local r = fn(i,v,...)
        for j,v2 in ipairs(r) do
            l:insert(v2)
        end
    end
    return l
end
function List:flatmap(fn,...)
    if type(fn) ~= "function" then
        fn = selector(fn)
    end
    local l = List()
    for i,v in ipairs(self) do
        local r = fn(v,...)
        for j,v2 in ipairs(r) do
            l:insert(v2)
        end
    end
    return l
end

function List:findi(fn,...)
    if type(fn) ~= "function" then
        fn = selectori(fn)
    end
    local l = List()
    for i,v in ipairs(self) do
        if fn(i,v,...) then
            return v
        end
    end
    return nil
end
function List:find(fn,...)
    if type(fn) ~= "function" then
        fn = selector(fn)
    end
    local l = List()
    for i,v in ipairs(self) do
        if fn(v,...) then
            return v
        end
    end
    return nil
end

function List:partitioni(fn,...)
    if type(fn) ~= "function" then
        fn = selectori(fn)
    end
    local m = {}
    for i,v in ipairs(self) do
        local k,v2 = fn(i,v,...)
        local l = m[k]
        if not l then
            l = List()
            m[k] = l
        end
        l:insert(v2)
    end
    return m
end
function List:partition(fn,...)
    if type(fn) ~= "function" then
        fn = selector(fn)
    end
    local m = {}
    for i,v in ipairs(self) do
        local k,v2 = fn(v,...)
        local l = m[k]
        if not l then
            l = List()
            m[k] = l
        end
        l:insert(v2)
    end
    return m
end

function List:foldi(init,fn,...)
    if type(fn) ~= "function" then
        fn = selectori(fn)
    end
    local s = init
    for i,v in ipairs(self) do
        s = fn(i,s,v,...)
    end
    return s
end
function List:fold(init,fn,...)
    if type(fn) ~= "function" then
        fn = selector(fn)
    end
    local s = init
    for i,v in ipairs(self) do
        s = fn(s,v,...)
    end
    return s
end

function List:reducei(fn,...)
    if type(fn) ~= "function" then
        fn = selectori(fn)
    end
    local N = #self
    assert(N > 0, "reduce requires non-empty list")
    local s = self[1]
    for i = 2,N do
        s = fn(i,s,self[i],...)
    end
    return s
end
function List:reduce(fn,...)
    if type(fn) ~= "function" then
        fn = selector(fn)
    end
    local N = #self
    assert(N > 0, "reduce requires non-empty list")
    local s = self[1]
    for i = 2,N do
        s = fn(s,self[i],...)
    end
    return s
end

function List:reduceori(init,fn,...)
    if type(fn) ~= "function" then
        fn = selectori(fn)
    end
    local N = #self
    if N == 0 then
      return init
    end
    local s = self[1]
    for i = 2,N do
        s = fn(i,s,self[i],...)
    end
    return s
end
function List:reduceor(init,fn,...)
    if type(fn) ~= "function" then
        fn = selector(fn)
    end
    local N = #self
    if N == 0 then
      return init
    end
    local s = self[1]
    for i = 2,N do
        s = fn(s,self[i],...)
    end
    return s
end

function List:existsi(fn,...)
    if type(fn) ~= "function" then
        fn = selectori(fn)
    end
    for i,v in ipairs(self) do
        if fn(i,v,...) then
            return true
        end
    end
    return false
end
function List:exists(fn,...)
    if type(fn) ~= "function" then
        fn = selector(fn)
    end
    for i,v in ipairs(self) do
        if fn(v,...) then
            return true
        end
    end
    return false
end

function List:alli(fn,...)
    if type(fn) ~= "function" then
        fn = selectori(fn)
    end
    for i,v in ipairs(self) do
        if not fn(i,v,...) then
            return false
        end
    end
    return true
end
function List:all(fn,...)
    if type(fn) ~= "function" then
        fn = selector(fn)
    end
    for i,v in ipairs(self) do
        if not fn(v,...) then
            return false
        end
    end
    return true
end

package.loaded["terralist"] = List

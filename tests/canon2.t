local C = terralib.includecstring [[
    typedef union {
            float v[2];
            struct {
                float x;
                float y;
            };
    } float2;
    static float2 a;
    void doit() {
        a.x = 4;
        a.y = 5;
    }
    float2* what() { return &a; }
]]

C.float2:printpretty()

local function nameindex(T) -- create a map from field names to their types
    assert(T:isstruct())
    local idx = {}
    local function visit(e)
        if e.field then 
            idx[e.field] = e.type -- single entry, add to map
        else -- a union, represented by a list of entries, add each member of union
            for i,e2 in ipairs(e) do 
                visit(e2) 
            end
        end
    end
    for i,e in ipairs(T:getentries()) do
        visit(e)
    end
    return idx
end
local anonstructgetter = macro(function(name,self)
    local fields = nameindex(self:gettype())
    for k,v in pairs(fields) do
        if k:match("_%d+") and v:isstruct() then
            local vfields = nameindex(v)
            if vfields[name] then
                return `self.[k].[name]
            end
        end
    end 
    error("no field "..name.." in struct of type "..tostring(T))
end)

C.float2.metamethods.__entrymissing = anonstructgetter

terra foo(pa : &C.float2)
    var a = @C.what()
    return a.v[0],a.v[1],a.x,a.y
end

C.doit()

local a = foo(C.what())
assert(4 == a._0)
assert(5 == a._1)
assert(4 == a._2)
assert(5 == a._3)
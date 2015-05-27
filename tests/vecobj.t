
local VecTypes = {}       
local Vec
Vec = terralib.memoize(function(typ,N)
    N = assert(tonumber(N),"expected a number")
    local ops = { "__sub","__add","__mul","__div", "__lt","__le","__gt","__ge","__eq","__ne"}
    local struct VecType { 
        data : typ[N]
    }
    VecTypes[VecType] = true
    local makeVec = macro(function(v)
        local typ = v:gettype()
        assert(typ:isarray())
        return `[Vec(typ.type,typ.N)] { v }
    end)
    VecType.metamethods.type, VecType.metamethods.N = typ,N
    VecType.metamethods.__typename = function(self) return ("%s_%d"):format(tostring(self.metamethods.type),self.metamethods.N) end
    for i, op in ipairs(ops) do
        VecType.metamethods[op] = macro(function(l,r)
            local lt = l:gettype()
            local rt = r:gettype()
            local N
            if VecTypes[lt] then 
                N = lt.metamethods.N
            end
            if VecTypes[rt] then
                if N then assert(rt.metamethods.N == N, "Vec size mismatch") end
                N = rt.metamethods.N
            end
            local exps = terralib.newlist()
            for i = 0,N-1 do
                local lv = VecTypes[lt] and (`l.data[i]) or (`l) 
                local rv = VecTypes[rt] and (`r.data[i]) or (`r) 
                exps:insert(`operator(op,lv,rv))
            end
            return `makeVec(array(exps))
        end)
    end
    VecType.metamethods.__apply = macro(function(self,idx) return `self.data[idx] end)
    return VecType
end)

terra foo(v : Vec(float,4), w : Vec(int,4))
    var x = (v*4+1*w)
    for i = 0,4 do
        print(x(i))
    end
    return x(2)
end

foo:printpretty(true,false)
foo:disas()

assert(19 == foo({{1,2,3,4}},{{5,6,7,8}}))
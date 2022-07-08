local ffi = require("ffi")

local Vec = terralib.memoize(function(typ,N)
    N = assert(tonumber(N),"expected a number")
    local ops = { "__sub","__add","__mul","__div" }
    local struct VecType { 
        data : typ[N]
    }
    VecType.metamethods.type, VecType.metamethods.N = typ,N
    VecType.metamethods.__typename = function(self) return ("%s_%d"):format(tostring(self.metamethods.type),self.metamethods.N) end
    for i, op in ipairs(ops) do
        local i = symbol(int,"i")
        local function template(ae,be)
            return quote
                var c : VecType
                for [i] = 0,N do
                    c.data[i] = operator(op,ae,be)
                end
                return c
            end
        end
        
        local terra doop1(a : VecType, b : VecType) [template(`a.data[i],`b.data[i])]  end
        local terra doop2(a : typ, b : VecType) [template(`a,`b.data[i])]  end
        local terra doop3(a : VecType, b : typ) [template(`a.data[i],`b)]  end
        VecType.metamethods[op] = terralib.overloadedfunction("doop",{doop1,doop2,doop3})
    end
    terra VecType.methods.FromConstant(x : typ)
        var c : VecType
        for i = 0,N do
            c.data[i] = x
        end
        return c
    end
    VecType.metamethods.__apply = macro(function(self,idx) return `self.data[idx] end)
    VecType.metamethods.__cast = function(from,to,exp)
        if from:isarithmetic() and to == VecType then
            return `VecType.FromConstant(exp)
        end
        error(("unknown conversion %s to %s"):format(tostring(from),tostring(to)))
    end
    return VecType
end)

-- FIXME: https://github.com/terralang/terra/issues/581
-- There are two limitations of Moonjit on PPC64le that require workarounds:
--  1. the printfloat callback results in a segfault
--  2. passing arrays to Terra from Lua results in garbage

if ffi.arch ~= "ppc64le" then
    printfloat = terralib.cast({float}->{},print)
else
    local c = terralib.includec("stdio.h")
    terra printfloat(x : float)
        c.printf("%f\n", x)
    end
end

terra foo(v : Vec(float,4), w : Vec(float,4))
    var z : Vec(float,4) = 1
    var x = (v*4)+w+1
    for i = 0,4 do
        printfloat(x(i))
    end
    return x(2)
end

foo:printpretty(true,false)
foo:disas()

if ffi.arch ~= "ppc64le" then
    assert(20 == foo({{1,2,3,4}},{{5,6,7,8}}))
else
    terra call_foo(v0 : float, v1 : float, v2 : float, v3 : float, w0 : float, w1 : float, w2 : float, w3 : float)
        var v : Vec(float,4)
        v(0) = v0
        v(1) = v1
        v(2) = v2
        v(3) = v3
        var w : Vec(float,4)
        w(0) = w0
        w(1) = w1
        w(2) = w2
        w(3) = w3
        return foo(v, w)
    end
    assert(20 == call_foo(1, 2, 3, 4, 5, 6, 7, 8))
end

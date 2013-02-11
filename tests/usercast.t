
struct A { a : int, b : float }

function A.metamethods.__cast(ctx,tree,from,to,exp)
    if from == int and to == A then
        return true, `A {exp, 1.f }
    elseif from == float and to == A then
        return true, `A { 1, exp }
    else
        return false
    end
end


terra moo(a : A)
    return a.a + a.b
end

terra bar()
    return moo(1) + moo(1.f)
end

local test = require("test")

test.eq(bar(), 4)
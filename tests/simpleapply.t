struct Vec { data : int[4] }
terra Vec:__apply(i : int)
    return self.data[i]
end

struct Vec2 { data : int[4] }
Vec2.methods.__apply = macro(function(ctx,tree,self,b)
    return `self.data[b]
end)

terra bar()
    var a = Vec { array(1,2,3,4) }
    var b = Vec2 { array(1,2,3,4) }
    b(2) = b(2) + 1
    return b(2) + a(2)
end

local test = require("test")
test.eq(bar(),7)
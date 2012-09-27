struct Vec { data : float[3] }

terra Vec:__getx()
    return self.data[0]
end
Vec.methods.__gety = macro(function(ctx,tree,self)
    return `self.data[1]
end)
    
terra bar()
    var a = Vec { array(1.f,2.f,3.f) }
    a["y"] = a["y"] + 1
    return a["x"] + a["y"]
end

local test = require("test")
test.eq(bar(),4)


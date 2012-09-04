

blk = quote
    var a = 3
    var b = 4
end

mya = blk:ref("a")
myb = blk:ref("b")

terra foo()
    mya = 5
    blk
    return mya + myb
end


local test = require("test")
test.eq(foo(),9)
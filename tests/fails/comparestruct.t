if not require("fail") then return end
struct S {}
terra foo()
    var a : S, b : S
    return a == b
end
foo()

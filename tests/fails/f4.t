if not require("fail") then return end
struct A { a : int, a : int }
terra foo()
    var a : A
end
foo()

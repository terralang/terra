if not require("fail") then return end
terralib.fulltrace = true
struct B { a : A[4] }
struct A { b : B }

terra foo()
    var a : A    
end
foo()

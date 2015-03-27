if not require("fail") then return end

struct B { a : A[4] } and
struct A { b : B }

terra foo()
    var a : A    
end
foo()

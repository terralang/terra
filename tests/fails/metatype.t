if not require("fail") then return end
local function foo(T)
    error("what")
end
struct A(foo) {
    a : int;
    b : int;
}


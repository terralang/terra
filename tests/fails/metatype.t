local function foo(T)
    error("what")
end
struct A(foo) {
    a : int;
    b : int;
}


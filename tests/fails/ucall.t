if not require("fail") then return end
struct Foo {}
function what(a)
end

terra uc()
    what(Foo {})
end

uc()
a = terra() return 4 end
local d = {}
do 
    struct A{}
    local terra a() return 5 end
    terra d.d(a : B) end
    terra B:a() end
    struct B {}
    terra c() end
    struct C {}
    assert(a() == 5)
end
assert(a() == 4)
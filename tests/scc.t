C = terralib.includec("stdio.h")

terra link(f : {} -> {})
    C.printf("visit %p\n",f)
end
-- create a graph like https://en.wikipedia.org/wiki/Tarjan%27s_strongly_connected_components_algorithm#/media/File:Tarjan%27s_Algorithm_Animation.gif
--  to test the scc handling in compiler
terra f0() : {}
    link(f4)
end
terra f1() : {}
    link(f0)
end
terra f2() : {}
    link(f1)
    link(f3)
end
terra f3() : {}
    link(f2)
end
terra f4() : {}
    link(f1)
end
terra f5() : {}
    link(f1)
    link(f4)
    link(f6)
end
terra f6() : {}
    link(f2)
    link(f5)
end
terra f7() : {}
    link(f3)
    link(f6)
    link(f7)
end

for i = 0,7 do
    _G["f"..tostring(i)]:compile()
end
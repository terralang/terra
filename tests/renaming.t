
C = terralib.includec("stdio.h")
terra main()
    C.printf("what\n")
end
main:setinlined(false)

terra realmain()
    main()
end

terralib.saveobj("renamed",{ main = realmain })

terralib.dumpmodule()
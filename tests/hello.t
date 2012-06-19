
local c = terralib.includec("stdio.h")

terra main()
	c.printf("hello, world\n")
end

main()
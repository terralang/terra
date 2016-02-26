local terra unalignedload(addr : &float)
	return terralib.attrload([&vector(float,4)](addr), { align = 4 })
end
local terra unalignedstore(addr : &float, value : vector(float,4))
	terralib.attrstore([&vector(float,4)](addr),value, { align = 4 })
end

terra foo(a : &float)
    unalignedstore(a,unalignedload(a+3))
end
foo:disas()
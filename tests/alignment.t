

terra foobar(a : &float)
	attribute(@a,{align = 4}) = attribute(a[3],{align = 4})
end

foobar:compile()

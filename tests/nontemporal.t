

terra foobar(a : &vector(float,4),b : vector(float,4))
	attribute(@a,{nontemporal = true}) = b
end

foobar:disas()

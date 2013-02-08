

terra foobar(a : &vector(float,4),b : vector(float,4))
	terralib.nontemporal(@a) = b
end

foobar:disas()

return {
    name = "examplelanguage"; --for error reporting
	entrypoints = {"sum"}; --these keywords will cause the parser to enter this language
	                       --they will also be treated as keywords inside the language
	keywords = {"done"}; --these become keywords only when parsing this language
	expression = function(self,lex)
		lex:expect("sum")
		local ids = terralib.newlist()
		if not lex:matches("done") then
			repeat
				local id = lex:expect(lex.name).value
				lex:ref(id)
				ids:insert(id)
			until not lex:nextif(",")
		end
		lex:expect("done")
		return function(envfn)
			local env = envfn()
			local sum = 0
			for i,id in ipairs(ids) do
				sum = sum + env[id]
			end
			return sum
		end
	end
}
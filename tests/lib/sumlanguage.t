local sumlanguage = {
	name = "sumlanguage"; --name for debugging
	entrypoints = {"sum"}; -- list of keywords that will start our expressions
	keywords = {"done"}; --list of keywords specific to this language
	expression = function(self,lex)
		local sum = 0
		lex:expect("sum") --first token should be "sum"
		if not lex:matches("done") then
			repeat
			    local t = lex:expect(lex.number)
			    print(t.valuetype,type(t.value))
				sum = sum + t.value --parse a number, return its value
			until not lex:nextif(",") --if there is a comma, consume it and continue
		end

		lex:expect("done")
		--return a function that is run when this expression would be evaluated by lua
		return function(environment_function)
			return sum
		end
	end;
}
return sumlanguage
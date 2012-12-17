local sumlanguage = {
	name = "sumlanguage"; --name for debugging
	entrypoints = {"sum"}; -- list of keywords that will start our expressions
	keywords = {"done"}; --list of keywords specific to this language
	expression = function(self,lex)
		local sum = 0
		local variables = terralib.newlist()
		lex:expect("sum")
		if not lex:matches("done") then
			repeat
				if lex:matches(lex.name) then --if it is a variable
					local name = lex:next().value
					lex:ref(name) --tell the Terra parser we will access a Lua variable, 'name'
					variables:insert(name) --add its name to the list of variables
				else
					sum = sum + lex:expect(lex.number).value
				end
			until not lex:nextif(",")
		end
		lex:expect("done")
		return function(environment_function)
			local env = environment_function() --capture the local environment
			                                   --a table from variable name => value
			local mysum = sum
			for i,v in ipairs(variables) do
				mysum = mysum + env[v]
			end
			return mysum
		end
	end;
}
return sumlanguage
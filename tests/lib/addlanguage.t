return {
    name = "addlanguage"; --for error reporting
	entrypoints = {"add"}; --these keywords will cause the parser to enter this language
	                       --they will also be treated as keywords inside the language
	keywords = {}; --these become keywords only when parsing this language
	expression = function(self,lex)
		lex:expect("add")
		local exprs = terralib.newlist()
		if not lex:matches("end") then
			repeat
				local expr = lex:luaexpr()
				exprs:insert(expr)
			until not lex:nextif(",")
		end
		lex:expect("end")
		return function(envfn)
			local env = envfn()
			local sum = 0
			for i,expr in ipairs(exprs) do
				sum = sum + expr(env)
			end
			return sum
		end
	end
}
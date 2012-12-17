return	{
	name = "def";
	entrypoints = {"def"};
	keywords = {};
	expression = function(self,lex)
		lex:expect("def")
		lex:expect("(")
		local formal = lex:expect(lex.name).value
		lex:expect(")")
		local expfn = lex:luaexpr()
		return function(environment_function)
			--return our result, a single argument lua function
			return function(actual)
				local env = environment_function()
				--bind the formal argument to the actual one in our environment
				env[formal] = actual
				--evaluate our expression in the environment
				return expfn(env)
			end
		end
	end;

	--normally these functions would be refactored to prevent code duplication,
	--we leave the duplication here to allow you to examine each individiually

	statement = function(self,lex)
		lex:expect("def")
		local fname = lex:expect(lex.name).value
		lex:expect("(")
		local formal = lex:expect(lex.name).value
		lex:expect(")")
		local expfn = lex:luaexpr()
		local ctor = function(environment_function)
			--return our result, a single argument lua function
			return function(actual)
				local env = environment_function()
				--bind the formal argument to the actual one in our environment
				env[formal] = actual
				--evaluate our expression in the environment
				return expfn(env)
			end
		end
		return ctor, { fname } -- create the statement: name = ctor(environment_function))
	end;

	localstatement = function(self,lex)
		lex:expect("def")
		local fname = lex:expect(lex.name).value
		lex:expect("(")
		local formal = lex:expect(lex.name).value
		lex:expect(")")
		local expfn = lex:luaexpr()
		local ctor = function(environment_function)
			--return our result, a single argument lua function
			return function(actual)
				local env = environment_function()
				--bind the formal argument to the actual one in our environment
				env[formal] = actual
				--evaluate our expression in the environment
				return expfn(env)
			end
		end
		return ctor, { fname } -- create the statement: local name = ctor(environment_function))
	end;
}
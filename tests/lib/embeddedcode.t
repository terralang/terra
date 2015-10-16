return	{
	name = "def";
	entrypoints = {"def","defexp","deft","deftexp"};
	keywords = {};
	expression = function(self,lex)
		local t = lex:next()
		lex:expect("(")
		local formal = lex:expect(lex.name).value
		if t.type == "deft" or t.type == "deftexp" then
		    lex:expect(":")
		    local typexpr = lex:luaexpr()
		    lex:expect(")")
		    local bodyexp
		    if t.type == "deftexp" then
		        bodyexp = lex:terraexpr()
		    else
		        bodyexp = lex:terrastats()
		        lex:expect("end")
		    end
		    return function(environment_function)
		        local env = environment_function()
		        local typ = typexpr(env)
		        assert(terralib.types.istype(typ),"not a type?")
		        local sym = symbol(typ,formal)
		        env[formal] = sym
		        local body = bodyexp(env)
		        if t.type == "deftexp" then
		            body = quote return body end
		        end
		        return terra([sym]) [body] end
		    end
		else
		    lex:expect(")")
		    local expfn
		    if t.type == "defexp" then
		        expfn = lex:luaexpr()
		    else
		        expfn = lex:luastats()
		        lex:expect("end")
		    end
		    return function(environment_function)
			    return function(actual)
				    local env = environment_function()
				    env[formal] = actual
				    return expfn(env)
				end
			end
		end
	end;
}
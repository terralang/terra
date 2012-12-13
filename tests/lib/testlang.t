return {
	keywords = {"akeyword"};
	entrypoints = {"image"};
	expression = function(self,lex,noskip)
		if not noskip then
			lex:next()
		end
		local t = lex:cur()
		lex:next()
		return function(env)
			terralib.tree.printraw(t)
			return t
		end 
	end;
	statement = function(self,lex)
		lex:next()
		local t = lex:cur()
		if lex:cur().type ~= lex.name or lex:lookahead().type ~= lex.number then
			lex:lookahead()
			return self:expression(lex,true)
		end
		local name = lex:cur().value
		lex:next()
		local v = lex:cur().value
		lex:next()
		return function(env)
			return v,v+1
		end, { {name}, {name.."1"} } 
	end
}
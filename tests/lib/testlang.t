return {
	keywords = {"akeyword"};
	entrypoints = {"image"};
	expression = function(self,lex,noskip)
		if not noskip then
			lex:next()
		end
		local ts =	terralib.newlist({lex:cur()})
		lex:next()

		while lex:testnext(",") do
			ts:insert(lex:cur())
			lex:next()
		end

		return function(env)
			terralib.tree.printraw(ts)
			return ts
		end

	end;
	statement = function(self,lex)
		lex:expect("image")
		if not lex:matches(lex.name) or not lex:lookaheadmatches(lex.number) then
			lex:lookahead()
			return self:expression(lex,true)
		end
		local name = lex:expect(lex.name).value
		local v = lex:expect(lex.number).value
		return function(env)
			return v,v+1
		end, { {name}, {name.."1"} } 
	end;
	localstatement = function(self,lex)
		lex:expect("image")
		local n = lex:expect(lex.name).value
		local v = lex:expect(lex.number).value
		return function(env)
			return v
		end, { {n} }

	end
}
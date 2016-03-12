

return {
	keywords = {"akeyword"};
	entrypoints = {"image", "foolist"};
	expression = function(self,lex,noskip)
		if not noskip then
			if lex:nextif("foolist") then
				return self:foolist(lex)
			end
			lex:next()
		end
		local ts =	terralib.newlist({lex:cur()})
		lex:next()

		while lex:nextif(",") do
			ts:insert(lex:cur())
			lex:next()
		end

		return function(env)
			terralib.printraw(ts)
			return ts
		end

	end;
	foolist = function(self,lex)
		local begin = lex:expect("{").linenumber
		local r = terralib.newlist()
		if not lex:matches("}")  then
			repeat
				local t = lex:expect(lex.name)
				r:insert(t.value)
				lex:ref(t.value)
			until not lex:nextif(",")
		end
		lex:expectmatch("}","{",begin)
		return function(envfn)
			local env = envfn()
			local rr = {}
			for i,k in ipairs(r) do
				rr[i] = env[k]
			end
			return unpack(rr)
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
		end, { {name}, name.."1" } 
	end;
	localstatement = function(self,lex)
		lex:expect("image")
		local n = lex:expect(lex.name).value
		local v = lex:expect(lex.number).value
		local v2 = lex:expect(lex.number).value
		return function(env)
			return v + v2
		end, { n }

	end
}
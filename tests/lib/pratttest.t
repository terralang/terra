local Parser = terralib.require("lib/parsing")

local lang = {}



local function leftbinary(P,lhs)
	local op = P:next().type
	local rhs = P:exp(op)
	return { name = op, lhs = lhs, rhs = rhs }
end

local function rightbinary(P,lhs)
	local op = P:next().type
	local rhs = P:exp(op,"right")
	return { name = op, lhs = lhs, rhs = rhs }
end

lang.exp = Parser.Pratt()
           :prefix("-",function(P)
           		P:next()
           		local v = P:exp(3)
           		return { name = "uminus", arg = v }
           end)
           :infix("-",1,leftbinary)
           :infix("+",1,leftbinary)
           :infix("*",2,leftbinary)
           :infix("/",2,leftbinary)
           :infix("^",3,rightbinary)
           :prefix(Parser.default, function(P) return P:simpleexp() end)

lang.prefixexp = function (P)
	if P:nextif("(") then
		local v = P:exp()
		P:expect(")")
		return v
	elseif P:matches(P.name) or P:matches(P.number) then
		return P:next().value
	else
		P:error("unexpected symbol")
	end
end
lang.simpleexp = function(P)
	local v = P:prefixexp()
	if P:nextif("(") then
		local arg = P:exp()
		P:expect(")")
		return { name = "call", fn = v, arg = arg }
	else
		return v
	end
end

return {
	name = "pratttest";
	entrypoints = {"goexp"};
	keywords = {};
	expression = function(self,lexer)
		lexer:expect("goexp")
		local ast = Parser.Parse(lang,lexer,"exp")
		return function(exp) return ast end
	end;
}
--import that Parser object (called P in the lib/parsing.t file)
local Parser = require("parsing")

--define a table that implements our language
local lang = {}


--rule for leftassociative binary operators
--P is the interface to the parser
--it contains (1) all of the functions defined in the lexer object
--(2) methods that invoke the rules for non-terminals in our language
--(e.g. P:exp() will run the exp rule defined below, P:simpleexp() will run the simpleexp rule)

local function leftbinary(P,lhs)
	local op = P:next().type
	local rhs = P:exp(op) --parse the rhs, passing 'op' to the exp rule indicates we want
	                      --to parse only expressions with higher precedence than 'op'
	                      --this will result in left-associative operators
	return { name = op, lhs = lhs, rhs = rhs } --build the ast
end

local function rightbinary(P,lhs)
	local op = P:next().type
	local rhs = P:exp(op,"right") --parse the rhs, passing 'op' and then specify "right" associativity 
	                              --indicates to parse expressions with precedence equal-to or higher-than 'op'
	                              --this will result in right associative operators
	return { name = op, lhs = lhs, rhs = rhs }
end

lang.exp = Parser.Pratt()
           :prefix("-",function(P)
           		P:next()
           		local v = P:exp(3) --precedence can also be specified with a number directly
           		                   --here we use 3 to unary minus higher precidence than binary minus
           		return { name = "uminus", arg = v }
           end)
           :infix("-",1,leftbinary)
           :infix("+",1,leftbinary)
           :infix("*",2,leftbinary)
           :infix("/",2,leftbinary)
           :infix("^",3,rightbinary)
           --default rules fire when no other rule is defined for the token
           --here we invoke another rule 'simpleexp'
           :prefix(Parser.default, function(P) return P:simpleexp() end)

lang.simpleexp = function(P)
	local v = P:prefixexp()
	if P:nextif("(") then --function application
		local arg = P:exp()
		P:expect(")")
		return { name = "call", fn = v, arg = arg }
	else
		return v
	end
end

lang.prefixexp = function (P)
	if P:nextif("(") then --expression in parens
		local v = P:exp() --if you do not give a precedence
		                  --it assumes you want to parse an expression of _any_ precedence
		P:expect(")")
		return v
	elseif P:matches(P.name) or P:matches(P.number) then
		return P:next().value
	else
		P:error("unexpected symbol") --the API automatically adds context information to errors.
	end
end


return {
	name = "pratttest";
	entrypoints = {"goexp"};
	keywords = {};
	expression = function(self,lexer)
		lexer:expect("goexp")
		--Parse runs our parser by combining our language 'lang' with the lexer
		--"exp" indicates we want to start parsing an exp non-terminal.
		local ast = Parser.Parse(lang,lexer,"exp")
		return function(exp) return ast end
	end;
}
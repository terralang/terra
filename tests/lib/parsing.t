
local P = {}

--same tokentypes as lexer, duplicated here for convience
P.name = terralib.languageextension.name
P.string = terralib.languageextension.string
P.number = terralib.languageextension.number
P.eof = terralib.languageextension.eof
P.default = terralib.languageextension.default

--a parser for a language is defined by a table of functions, one for each non-termina
--in the language (e.g expression,statement, etc.)

--these functions are either (1) raw recursive decent parsers
-- or (2) Pratt parser objects

--pratt parser objects behave like functions
--but their behavior is defined by adding rules for what to do when 
--a prefix or suffix is found
--futhermore, when using a pratt parser object,  you can specify
--a precedence such that the parser will only parse expressions 
--with precedence _higher_ than that.
--see tests/lib/pratttest.t for examples of how to use this interface
--to parse common patters

P.pratt = {}
function P.Pratt()
	return setmetatable({
		infixtable = {};
		prefixtable = {};
	},{ __index = P.pratt, __call = P.pratt.__call })
end


--define a rule for infix operators like '+'
--precidence is a numeric precedence
--tokentype is a lexer token type (see embeddinglanguages.html)
--rule is a function: function(parser,lhs) ... end
--it is given the parser object and the AST value for the lhs of the expression.
--it should parse and return the AST value for current expression
--P.default can be used to define a rule that fires when no other rule applies
function P.pratt:infix(tokentype,prec,rule)
	if self.infixtable[tokentype] then
		error("infix rule for "..tostring(tokentype).." already defined")
	end
	self.infixtable[tokentype] = { 
		prec = prec;
		rule = rule;
	}
	return self
end

--define a prefix rule
--rule is a function: function(parser) ... end, that takes the parser object
--and returns an AST for the expression

function P.pratt:prefix(tokentype,rule)
	if self.prefixtable[tokentype] then
		error("prefix rule for "..tostring(tokentype).." already defined")
	end
	self.prefixtable[tokentype] = rule
	return self
end

P.defaultprefix = function(parser)
	parser:error("unexpected symbol")
end
--table-driven implementation, invoked when you call the Pratt parser object
P.pratt.__call = function(pratt,parser,precortoken,fixity)
	local isleft = fixity == nil or fixity == "left"
	local limit
	if not precortoken then
		limit,isleft = 0,false
	elseif type(precortoken) == "number" then
		limit = precortoken
	else
		if not pratt.infixtable[precortoken] then
			error("precidence not defined for "..tostring(precortoken))
		end
		limit = pratt.infixtable[precortoken].prec
	end
	local tt = parser:cur().type
	local prefixrule = pratt.prefixtable[tt] or pratt.prefixtable[P.default] or P.defaultprefix
	local results = { prefixrule(parser) }
	while true do
		tt = parser:cur().type
		local op = pratt.infixtable[tt] or pratt.infixtable[P.default]
		if not op or (isleft and op.prec <= limit) or (not isleft and op.prec < limit) then
			break
		end
		results = { op.rule(parser,unpack(results)) }
	end
	return unpack(results)
end


--create a parser
--langtable is the table of non-terminal functions and/or pratt parser objects
--lexer is the lexer object given by the language extension interface
function P.Parser(langtable,lexer)
    local instance = {}
	for k,v in pairs(lexer) do
		if type(v) == "function" then
			instance[k] = function(self,...) return v(lexer,...) end
		elseif string.sub(k,1,1) ~= "_" then
			instance[k] = v
		end
	end
	for k,v in pairs(langtable) do
		if instance[k] then error("language nonterminal overlaps with lexer function "..k) end
		instance[k] = v
	end
	return instance
end

--create a parser and run a non-terminal in one go
--nonterminal is the name (e.g. "expression") of the non-terminal to use as the starting point in the langtable
function P.Parse(langtable,lexer,nonterminal)
	local self = P.Parser(langtable,lexer)
	return self[nonterminal](self)
end


return P
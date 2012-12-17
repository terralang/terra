
local P = {}

P.name = terralib.languageextension.name
P.string = terralib.languageextension.string
P.number = terralib.languageextension.number
P.eof = terralib.languageextension.eof
P.default = terralib.languageextension.default

P.pratt = {}

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
function P.pratt:prefix(tokentype,rule)
	if self.prefixtable[tokentype] then
		error("prefix rule for "..tostring(tokentype).." already defined")
	end
	self.prefixtable[tokentype] = rule
	return self
end

P.defaultinfix = function(parser)
	parser:error("unexpected symbol")
end
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


function P.Pratt()
	return setmetatable({
		infixtable = {};
		prefixtable = {};
	},{ __index = P.pratt, __call = P.pratt.__call })
end


function P.Parse(langtable,lexer,nonterminal)
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
	return instance[nonterminal](instance)
end

return P
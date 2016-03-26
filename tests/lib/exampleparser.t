local Parse = require "parsing"

local Tree = {}
Tree.__index = Tree
function Tree:is(t)
    return getmetatable(t) == Tree
end

function Tree:new(P,kind)
    return setmetatable({kind = kind, offset = P:cur().offset, linenumber = P:cur().linenumber, filename = P.source},Tree)
end
function Tree:dump()
    terralib.printraw(self)
end
function Tree:copy(nt)
    for k,v in pairs(self) do
        if not nt[k] then nt[k] = v end
    end
    return setmetatable(nt,Tree)
end
function Tree:anchor(kind,nt)
    nt.filename,nt.linenumber,nt.offset = self.filename,self.linenumber,self.offset 
    nt.kind = kind
    return setmetatable(nt,Tree)
end

local unary_prec = 5

local function binary(P,lhs,fixity)
    local n = Tree:new(P,"binary")
    n.op = P:next().type
    n.lhs,n.rhs = lhs,P:exp(n.op,fixity)
    return n
end
local leftbinary = binary
local function rightbinary(P,lhs,fixity) return binary(P,lhs,"right") end
local function unary(P)
	local n = Tree:new(P,"unary")
	n.op = P:next().type
	n.exp = P:exp(unary_prec)
	return n
end	

local function literal(P,value)
    local n = Tree:new(P,"literal")
    P:next()
    n.value = value
    return n
end

local lang = {}

lang.exp = Parse.Pratt() -- returns a pratt parser
:prefix("-", unary)
:prefix("not", unary)
:infix("or", 0, leftbinary)
:infix("and", 1, leftbinary)

:infix("<", 2, leftbinary)
:infix(">", 2, leftbinary)
:infix("<=", 2, leftbinary)
:infix(">=", 2, leftbinary)
:infix("==", 2, leftbinary)
:infix("~=", 2, leftbinary)

:infix("+", 3, leftbinary)
:infix("-", 3, leftbinary)
:infix("*", 4, leftbinary)
:infix('/', 4, leftbinary)
:infix('%', 4, leftbinary)

:infix('^', 6,   rightbinary)
:infix('.', 7, function(P,lhs)
    local n = Tree:new(P,"select")
    n.exp = lhs
    P:next()
    local start = P:cur().linenumber
    if P:nextif('[') then --allow an escape to determine a field expression
        n.field = P:luaexpr()
        P:expectmatch(']', '[', start)
    else
        n.field = P:expect(P.name).value
    end
    return n
end)
:infix('[', 8, function(P,lhs)
    local n = Tree:new(P,"index")
	n.exp = lhs
	local begin = P:next().linenumber
	n.index = P:exp()
	P:expectmatch(']', '[', begin)
	return n
end)
:infix('(',   8, function(P,lhs)
    local n = Tree:new(P,"apply")
    local begin = P:next().linenumber
	n.exp,n.params = lhs,{}
	if not P:matches(')') then
	    repeat
	        table.insert(n.params,P:exp())
	    until not P:nextif(',')
	end
	P:expectmatch(')', '(', begin)
	return n
end)
:prefix(Parse.name,function(P)
    local n = Tree:new(P,"var")
    n.name = P:next().value
    P:ref(n.name) --make sure var appears in the envfn passed to constructor
    return n
end)
:prefix(Parse.number, function(P) return literal(P,P:cur().value) end)
:prefix('true', function(P) return literal(P,true) end)
:prefix('false', function(P) return literal(P,false) end)
:prefix('(', function(P)
    local start = P:next().linenumber
	local v = P:exp()
	P:expectmatch(")", "(", start)
	return v
end)
:prefix('{', function(P)
    local n = Tree:new(P,"constructor")
    local start = P:next().linenumber
    n.entries = {}
    repeat
        if P:matches("}") then break end
        table.insert(n.entries,P:field())
    until not (P:nextif(",") or P:nextif(";"))
    P:expectmatch("}", "{", start)
    return n
end)
:prefix("[", function(P)
    local n = Tree:new(P,"escape")
    local start = P:next().linenumber
    n.luaexp = P:luaexpr()
    P:expectmatch("]", "[", start)
    return n
end)
function lang.field(P)
    local n = Tree:new(P,"field")
    if P:matches(P.name) and P:lookaheadmatches("=") then
        n.name = P:next().value
        P:expect("=")
        n.value = P:exp()
    elseif P:matches("[") then
        local start = P:next().linenumber
        n.name = P:exp()
        P:expectmatch("]","[", start)
        P:expect("=")
        n.value = P:exp()
    else
        n.value = P:exp()
    end
    return n
end

lang.decl = function(P)
    local n = Tree:new(P,"decl")
    n.name = P:expect(P.name).value
    if P:nextif(":") then
        n.type = P:luaexpr()
    end
    return n
end
local function parselist(P,nt)
    local es = {}
    repeat
        table.insert(es,P[nt](P))
    until not P:nextif(",")
    return es
end
lang.statement = function (P)
	if P:nextif("var") then
		local n = Tree:new(P,"declaration")
		n.vars = parselist(P,"decl")
		if P:nextif("=") then
		    n.initializers = parselist(P,"exp")
		end
		return n
	elseif P:nextif("if") then
		local n = Tree:new(P,"if")
		n.conditionals = {}
		repeat
		    local c = {}
		    c.condition = P:exp()
		    P:expect("then")
		    c.body = P:block()
		    table.insert(n.conditionals,c)
		until not P:nextif("elseif")
		if P:nextif("else") then
		    n.orelse = P:block()
		end
		P:expect("end")
		return n
	elseif P:nextif("while") then
	    local n = Tree:new(P,"while")
	    n.cond = P:exp()
	    P:expect("do")
	    n.block = P:block()
	    P:expect("end")
	    return n
	elseif P:nextif("do") then
		local n = Tree:new(P,"scope")
		n.body = P:block()
		P:expect("end")
		return n
	elseif P:nextif("repeat") then
	    local n = Tree:new(P,"repeat")
	    n.body = P:block()
	    P:expect("until")
	    n.cond = P:exp()
	    return n
	elseif P:nextif("for") then
	    local n = Tree:new(P,"for")
	    n.vars = parselist(P,"decl")
	    if P:nextif("=") then
	        n.numeric = true
	    else
	        P:expect("in")
	    end
	    n.initializers = parselist(P,"exp")
	    P:expect("do")
	    n.body = P:block()
	    P:expect("end")
	    return n
	else
	    local lhs = parselist(P,"exp")
	    if #lhs > 1 or P:matches("=") then
	        local n = Tree:new(P,"assign")
	        P:expect("=")
	        n.lhs,n.rhs = lhs,parselist(P,"exp")
	        return n
	    else
	        return lhs
	    end
	end
end

local block_terminators = {"end","else","elseif","until","break","in","return"}
local is_block_terminator = {}
for _,b in ipairs(block_terminators) do is_block_terminator[b] = true end

lang.block = function(P)
    local n = Tree:new(P,"block")
    n.statements = {}
	while not is_block_terminator[P:cur().type] do
	    table.insert(n.statements,P:statement())
	end
	if P:nextif("break") then
		local nn = Tree:new(P,"break")
		table.insert(n.statements,nn)
	elseif P:nextif("return") then
	    local nn = Tree:new(P,"return")
	    n.exps = parselist(P,"exp")
	    table.insert(n.statements,nn)
	end
	return n
end

return {
    name = "exampleparser"; --for error reporting
	entrypoints = {"P"}; --these keywords will cause the parser to enter this language
	                     --they will also be treated as keywords inside the language
	keywords = {}; --these become keywords only when parsing this language
	expression = function(self,lex)
	    lex:next()
	    local key = lex:next().value
		assert(type(key) == "string")
		local tree = Parse.Parse(lang,lex,key)
		return function(envfn) tree:dump() return tree end
	end
}
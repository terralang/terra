--[[
This is an example of embedding and compiling a language.
It uses the language extension API to embed a new Language ("eg") into Lua and
then generates Terra code to implement the eg language.

The eg language is a toy example language that looks pretty similar to Terra/Lua,
but only contains a few constructs.

   def foo(a : eg.numbertype) : eg.number  --'def' starts a definition, param/return types must be annotated
                                           --they must always be eg.number 
       var b = 4*a + 3 --simple expressions and varible definitions, variables must always have definitions
	   b = b + 1 -- assignments
	   if b < 0 then --simple if statements, 'else' is optional, there is not elseif.
	   	 b = b + 1
	   else
	   	 b = foo(3) - 1 --and function calls to other example functions
	   end
	   return b*b --simple return statements
   end

To show you how to use all language embedding features, 
we also allow a local variable form:

   local def foo(a : eg.numbertype) : eg.numbertype return 4 end

an anonymous form:

   foo = def(a : eg.numbertype) : eg.numbertype) return 4 end

and the name for the global statement can be a table lookup

   foo = {}
   def foo.bar(a : eg.numbertype) : eg.numbertype return 4 end

]]

-- Language extension setup

--The functions 'expression' and 'statement' are entry points into the eg language
--they will be called when we encounter an eg expression (anonymous def) or
--when we encounter a statment (def ..., or local def ...)
local expression,statement


--This table describes how the eg language extends the Lua parser.
--It is returned by this file.
local langdefinition = {
	name = "example";
	entrypoints = { "def" }; --list of new keywords that will cause
	                         --Lua to call this extension if they are seen
	keywords = {}; --list of new keywords added by this language

	--this will be called when "def" is seen as a Lua expression
	--lex is an interface to the Lua lexer that will be used by our parser
	expression = function(self,lex) return expression(lex) end;

	--this will be called when "def" is seen as a statement
	statement = function(self,lex) return statement(lex,false) end;

	--this will be called when "def" immediately follows "local" at the
	--beginning of a statment
	localstatement = function(self,lex) return statement(lex,true) end;
}


-- Basic datatypes ----------------------------------------------------------

-- Create a global object to hold library functionality for our 'eg' language
-- this is the equivalent of Terra's 'terralib'
eg = {}

--A basic type object. 
eg.type = {}
eg.type.__index = eg.type
function eg.type:__tostring() return self.kind end

function eg.istype(a)
	return getmetatable(a) == eg.type
end

--There are only two types in our language. 

--a number type representing a double:
eg.number = setmetatable({kind = "number"},eg.type)

--and a type to represent eg functions
--these functions will always take 1 number argument and return 1 number
eg.funcpointer = setmetatable({kind = "function"},eg.type)


--A Tree object to represent a node in our abstract syntax tree (AST)
--these are local to this file since they do not need to be accessed externally from our compiler

local tree = {}
tree.__index = tree


--We will treat trees as immutable in our compiler. 
--This is normally a good idea, since it is often not safe to mutate trees.
--For instance, the parser will run once for a statement, creating an untyped AST.
--If that statement was nested in some loop, then that AST can be re-used 
--many times, and should not be mutated during type checking or compilation.

--Here we create a helper function to create a new tree using this tree as a _template_
--'init' is a new table with values that will override the values in this tree
--otherwise, we copy the values in this tree into the new tree
function tree:copy(init)
	for k,v in pairs(self) do
		if not init[k] then
			init[k] = v
		end
	end
	return setmetatable(init,tree)
end

--Our parser will tag each tree it creates with the linenumber, filename, and offset (in bytes)
--into the file where a tree appeared. During typechecking, we may need to create new trees (not copies).
--In this case, we _still_ force a new tree to be created based on an old one, but only copy the line
--number information. This practice ensures that trees _always_ have line number information associated with them
--that will be important for error reporting.
function tree:new(init)
	init.linenumber,init.filename,init.offset = self.linenumber,self.filename,self.offset
	return setmetatable(init,tree)
end

--A eg function object is the Lua object that holds the implementation of an eg function (equivalent to a Terra 'function' object)
eg.func = {}
eg.func.__index = eg.func
function eg.isfunction(e)
	return getmetatable(e) == eg.func
end

local function newegfunction(typedtree,impl)
	--impl is a terra function that was compiled to implement this function
	--typedtree is the typechecked tree
	return setmetatable({ typedtree = typedtree, impl = impl }, eg.func)
end

--make it possible to call a function directly: foo(arg)
function eg.func.__call(self,...)
	return self.impl(...)
end

-- Parsing ---------------------------------------------------------------------------


--parsedef is our entrypoint into the parser for eg functions. 
--It will take the 'lex' object passed
--into the language extension and parse a definition.
--It starts parsing starting with the '(' of the argument list. The functions
--'expression' and 'statement' parse everything up to that point since it differs
--depending on how the 'def' begins
local parsedef

--createdef is called when a 'def' function is instanciated (when the expression is actually 
--evaluated in Lua code). This can happen multiple times for each parsed tree.
--It will take the 'untypedtree' from parsing, combined with the local Lua environment (mapping from name -> Lua value).
local createdef

--the entrypoint for 'def' expressions
function expression(lex)
	lex:expect("def") --they always start with 'def'
	local untypedtree = parsedef(lex) --followed by the argument list and body, handled by parsedef
	
	--we must return a 'constructor' function that is called whenever this expresion is evaluated
	--this function will combine the parsed tree with the local Lua environment when it is evaluated.
	return function(env)
		--'env' is a function. When it is evaluated, it captures the values of Lua variables in this expression's
		--local environment
		return createdef(untypedtree,env())
	end
end

--entrypoint for 'def' statements, if 'islocal' is 'true' then this 
--statement started with the 'local' keyword
function statement(lex,islocal)
	lex:expect("def")
	local nm = lex:expect(lex.name).value
	if not islocal then
		--a nonlocal function may be table lookup (e.g. def 'foo.bar(...')
		nm = terralib.newlist{ nm }
		while lex:nextif(".") do
			nm:insert(lex:expect(lex.name).value)
		end
	end
	local tree = parsedef(lex)
	return function(env)
		return createdef(tree,env())
	end,{ nm } --in addition to the constructor function, statements can return a _list_ of variable names that are bound to the values
	           --returned by the constructor
	           --if the statement is not preceeded by 'local', then the _names themselves_ can be lists of strings.
	           --In this case the _name_ {"foo","bar"} turns into "foo.bar = constructor(...)"
end


--We will use top-down precedence parsing, see lib/parsing.t for more information
local Parser = require("parsing")

--A parser in our parsing library is defined by a table of different non-terminals (e.g. lang.expression, lang.statement, etc.)
local lang = {}

--Create a new tree object, using the current linenumber information from the parser.
--This is the _only_ function that creates a tree without already having another tree.
--'kind' is something like "defvar", "if", or "var" that describes the purpose of this tree
local function newtree(P,kind)
	local thetree = { kind = kind, linenumber = P:cur().linenumber, filename = P.source, offset = P:cur().offset }
	return setmetatable(thetree,tree)
end

--the rule for "def"
function lang.def(P) --each function defined in the 'lang' table will take the parser object 'P' as its argument
	                 --in addition to containing the same interface as the 'lex' object, it contains methods
	                 --for reach non-terminal (e.g. P:def() will parse a 'def' non-terminal)
	local tree = newtree(P,"def")
	P:expect("(")
	tree.arg = P:expect(P.name).value --extract the string value of the name
	P:expect(":")
	tree.argtype = P:type() --Parse the non-terminal 'type' which we will define later as function in the 'lang' table
	P:expect(")")
	P:expect(":")
	tree.returntype =  P:type()
	tree.statements = P:statlist() --different non-terminals can return different types 'statlist' will return a list of statements
	P:expect("end")
	return tree
end

--entry-point for parsing, constructs the parser and parser a 'def'
function parsedef(lex)
	return Parser.Parse(lang,lex,"def") --run our Parser. It will start by parsing the "def" non-terminal, which we will define later.
end

--types in eg are just Lua expressions, just like in Terra.
--We can use the lexer's :luaexpr() function to parse a lua expression and return a function that will
--evaluate that expression when run.
function lang.type(P)
	return P:luaexpr()
end

--parse a single statement. each of these rules is pretty straightforward.
function lang.statement(P)
	if P:nextif("var") then
		local tree = newtree(P,"defvar")
		tree.name = P:expect(P.name).value
		P:expect("=")
		tree.expression = P:expression()
		return tree
	elseif P:nextif("return") then
		local tree = newtree(P,"return")
		tree.expression = P:expression()
		return tree
	elseif P:nextif("if") then
		local tree = newtree(P,"if")
		tree.condition = P:expression()
		P:expect("then")
		tree.thenB = P:statlist()
		tree.elseB = terralib.newlist()
		if P:nextif("else") then
			tree.elseB = P:statlist()
		end
		P:expect("end")
		return tree
	else
		local lhs = P:expression()
		local tree = newtree(P,"assign")
		tree.lhs = lhs
		P:expect("=")
		tree.rhs = P:expression()
		return tree
	end
end


--these tokens can follow a block of statments, we will use them when parsing a list of statements.
local tokensfollowingblocks = { "end", "else" }


local canfollowblock = {} --a map from "token" -> bool, true if the token can follow a block
for i,t in ipairs(tokensfollowingblocks) do
	--initilize the table with the list of tokens
	canfollowblock[t] = true
end

function lang.statlist(P)
	local stmts = terralib.newlist() --terrlib.newlist creates a list with a few extra functions than normal Lua tables
	                                 -- list:map(func) is a standard 'map' operator
	                                 -- list:insert(v) will append a value
	-- keep parsing a statement until we see a token that ends the block (either an "end" or an "else")
	while not canfollowblock[P:cur().type] do
		stmts:insert(P:statement())
	end
	return stmts
end

--for expressions we will use top-down precedence parsing.
--this allows us to define rules for when we see a token at the beginning of an expression (prefix)
--or when we see it follow another expression (infix)
--it also allows us to specify and control the precedence for infix operators.

lang.expression = Parser.Pratt() --like normal parsing functions, you can call this parser with P:expression()

--if we see a name (an identifier) at the beginning of a statment, then it is a variable:
lang.expression:prefix(Parser.name,function(P)
	local tree = newtree(P,"var")
	tree.name = P:next().value
	P:ref(tree.name) --variables may be references to values in the surrounding _Lua_ scope
	                 --if we want these variables to show up in the 'env' table passed to 'createdef'
	                 --we must call the lexer's 'def' method. Otherwise, Lua doesn't know you are interested
	                 --in that value. It is safe to call 'ref' on things you never use.
	return tree
end)

--an expression might be a raw number.
lang.expression:prefix(Parser.number,function(P)
	local tree = newtree(P,"constant")
	tree.value = P:next().value
	return tree
end)
--or an expression in parens.
lang.expression:prefix("(",function(P)
	P:next() --skip (
	local v = P:expression()
	P:expect(")")
	return v
end)
--or a unary minus
lang.expression:prefix("-",function(P)
	local tree = newtree(P,"operator")
	P:next() --skip '-'
	tree.operator = "-"
	tree.operands = terralib.newlist { P:expression(9) } --here we pass a precedence of '9' to the 'expression' method
	                                                     --this means that 'expression' will only parse an expression with precedence
	                                                     --higher than '9' (In this case 9 is the precedence of unary minus).
	                                                     --For instance if the token stream looks like "4 + 3", this call will only parse
	                                                     --the '4' since the '+' operator has precedence '2'
	                                                     --when called without an argument 'expression' parses with a precedence of 0 (i.e. the largest expression possible)
	return tree
end)
--function application "foo(a)" is an _infix_ operator
--the '(' follows an expression. It has the highest precedence ('10') in the eg language
--for infix operators have a second parameter 'lhs' that is the value parsed before reaching the infix operator
lang.expression:infix("(",10,function(P,lhs)
	local tree = newtree(P,"apply")
	P:next() --skip '('
	tree.fn = lhs
	tree.argument = P:expression()
	P:expect(")")
	return tree
end)

--this function defines what to do for any left-associated 
--binary infix operator (a + b, c*d, etc.)
local function doleftbinary(P,lhs)
	local tree = newtree(P,"operator")
	local tok = P:next()
	local rhs = P:expression(tok.type) --in addition to specifying a precedence as a number
	                                   --you can also specify it as a token type (tok.type).
	                                   --If you registered the tokentype "lang.expression:infix(tokentype,prec,...."
	                                   --then tokentype has the predecence 'prec'
	                                   --here we parse expressions only with precedence higher than prec
	                                   --so 'a + b + c' will parse as '(a + b)' here rather than '(a + (b + c))' which would
	                                   --be incorrectly right associative.
	tree.operator = tok.type
	tree.operands = terralib.newlist { lhs, rhs }
	return tree
end
--now register all our binary operators.
--They are listed from lowest precedence (1) to highest.
local binaryoperators = { {"<",">","<=",">=" },
                          {"-","+"},
                          {"*","/"} }
for prec,values in ipairs(binaryoperators) do
	for i,v in ipairs(values) do
		lang.expression:infix(v,prec,doleftbinary)
	end
end

-- Constructor -----------------------------------------------------------------------------------

local typecheck --takes the untyped tree and environment, produces typed tree
local compile -- takes the typedtree and produces a Terra function that implements it


--define our constructor function
function createdef(untypedtree,env)
	
	--first typecheck the function (this will error out if it is not correct)
	local typedcode = typecheck(untypedtree,env)

	--then compile the typed code into a Terra function
	local egfn		= compile(typedcode)
	
	--finally create the wrapper eg function object for this 'def'
	return newegfunction(typedcode,egfn)
end


-- Typechecking ---------------------------------------------------------------------------------

function typecheck(untypedtree,luaenv)
	
	local checkexp --check an expression tree, and return a tree with the tree.type field set to a valid eg type
	local checkstmt --check/return a single statment
	local checkstmts --check and return a list of statements
	local checklvalue --check an expression that can appear on the lhs of an exression
	                  --we will set tree.lvalue = true for any expression that can appear on the lhs of an assignment
	local createvaluefromlua --convert a raw Lua value into a value in the eg language
	                         --we will use this when looking up symbols from the Lua environment
	
	--the return type, it is always a number
	local therettype = eg.number

	--terralib.newenvironment creates a nested hash table.
	--it has functions env:enterblock() and env:leaveblock() to push/pop a new level of symbols
	--it can also keep track of the external lua environment for us. env:localenv() return a map from string -> local value (not including lua scope).
	--while env:combinedenv() returns a map from string -> local  value or lua value (if local value is not defined)

	--here we will use the environment as a map from name -> type
	local env = terralib.newenvironment(luaenv)


	--terralib.newdiagnostics creates a helper object for reporting errors. 
	--its method diag:reporterror(tree,msg) has an argument 'tree' which should have the location information: tree.filename, tree.offset, and tree.linenumber.
	--these will be used to report an error and the place where it occured.
	local diag = terralib.newdiagnostics()
	

	--parse a list of statments, each list of statements starts its own scope,
	--so we push/pop the environment table
	function checkstmts(stmts)
		env:enterblock()
		local ns = stmts:map(checkstmt)
		env:leaveblock()
		return ns
	end

	--make sure exp has type 'typ' or report an error
	local function expecttype(typ,exp)
		if typ ~= exp.type then
			diag:reporterror(exp,"expected a ",typ," but found ",exp.type)
			--diag:reporterror does not stop execution!
			--this is on purpose: we want to report as many type errors as we can
			--however it is important that even when there is an error, typechecking must continue
		end
		return exp
	end
	function checkexp(e)
		local k = e.kind
		if "constant" == k then
			--constants are always numbers, just tag them with the type
			return e:copy { type = eg.number }
		elseif "operator" == k then
			local typedoperands = terralib.newlist()
			for i,o in ipairs(e.operands) do
				--all operands only work on numbers, so just ensure all arguments are numbers
				local to = expecttype(eg.number,checkexp(o))
				typedoperands:insert(to)
			end
			--all operators only result in numbers as well
			return e:copy { operands = typedoperands, type = eg.number }
		elseif "apply" == k then
			--function must have a function type
			local fn = expecttype(eg.funcpointer,checkexp(e.fn))
			--and the argument must be a number
			local arg = expecttype(eg.number,checkexp(e.argument))
			return e:copy { fn = fn, argument = arg, type = eg.number }
		elseif "var" == k then
			--variables can be local (defined in an eg scope)
			--or Lua variables that we will convert into constants or function references
			local typeofdefn = env:localenv()[e.name]
			if typeofdefn then
				--symbol exists as part of the local scope, return a variable reference
				--lvalue is set to true, because a variable can be on the lhs
				return e:copy { type = typeofdefn, lvalue = true }
			else
				--otherwise it might be a lua value, look it up in the Lua environment
				local lv = env:luaenv()[e.name]
				if not lv then
					--it was defined it either place...
					diag:reporterror(e,"variable not defined")
					--remember: we _must_ continue typechecking:
					return e:copy { type = eg.number }
				end
				--variable was defined, try to translate it from Lua into an eg value
				return createvaluefromlua(e,lv)
			end
		end
	end

	function createvaluefromlua(tree,value)
		if type(value) == "number" then
			--if the value is a number then just create a constant
			return tree:new { kind = "constant", value = value, type = eg.number }
		elseif eg.isfunction(value) then
			--the value was a eg function object, create a "functionliteral" reference to it
			return tree:new { kind = "functionliteral", value = value, type = eg.funcpointer }
		else
			--we don't know what to do with this value...
			diag:reporterror(tree,"Lua value not understood by example compiler: ",type(value))
			return tree:copy { type = eg.number }
		end
	end


	function checkstmt(s)
		local k = s.kind
		if "defvar" == k then
			local exp = checkexp(s.expression)
			env:localenv()[s.name] = exp.type --map this variable to its type in the local environment
			return s:copy { expression = exp } 
		elseif "return" == k then
			local exp = expecttype(therettype,checkexp(s.expression))
			return s:copy { expression = exp }
		elseif "assign" == k then
			local lhs = checklvalue(s.lhs) --must be an lvalue!
			local rhs = expecttype(lhs.type,checkexp(s.rhs))
			return s:copy { lhs = lhs, rhs = rhs }
		elseif "if" == k then
			local cond = expecttype(eg.number,checkexp(s.condition))
			local thenB = checkstmts(s.thenB)
			local elseB = checkstmts(s.elseB)
			return s:copy { condition = cond, thenB = thenB, elseB = elseB }
		end
	end
	
	function checklvalue(e)
		local exp = checkexp(e)
		--check if e.lvalue is set, if no this is a problem
		if not e.lvalue then
			diag:reporterror(e,"lvalue required in this context")
		end
		return exp
	end

	--now we begin the overall typechecking procedure

	--like environments, diagnostics are scoped, so we begin a new diagnostic scope here
	--and enter the block for the entire function
	env:enterblock()
	
	--evaluate the argument/return types. These were parsed Lua expressions and returned as Lua functions
	--We can evaluate them by passing the local lua envronment as an argument:
	local argtype = untypedtree.argtype(env:luaenv())
	local rettype = untypedtree.returntype(env:luaenv())

	--in our simplified language they must be numbers
	if argtype ~= eg.number or rettype ~= eg.number then
		diag:reporterror(untypedtree,"argument/return to function must be numbers")
	end
	--the argument is also in scope, so make sure to put it in the environment
	env:localenv()[untypedtree.arg] = argtype

	--now check the body
	local stmts = checkstmts(untypedtree.statements)

	env:leaveblock()
	--if any error are reported, we now abort (this will call Lua's error function)
	diag:finishandabortiferrors("Errors reported during typechecking.",3)
	return untypedtree:copy { argtype = argtype, returntype = rettype, statements = stmts }
end


--the structure of the compiler is similar to typechecking except there
--are no longer any errors to handle, and each function will return quotations rather than ASTs
function compile(typedcode)

	--this time our environments will map strings -> Terra symbols holding the value for each variable
	local env = terralib.newenvironment()

	local emitstmt
	local emitstmts
	local emitexp

	--convert eg type into Terra type
	local function gettype(egtype)
		if egtype == eg.number then
			return double
		elseif egtype == eg.funcpointer then
			return double -> double
		end
	end
	function emitexp(e)
		local k = e.kind
		if "constant" == k then
			return e.value --just the number
		elseif "functionliteral" == k then
			--e.value is a eg.func object
			return e.value.impl --the terra function that implements this eg function
		elseif "operator" == k then
			local operands = e.operands:map(emitexp)
			--'operator' is a built-in Terra macro that allows you to use the built-in operators like
			--'+' programmatically "operator("+",3,4)" is equivalent to 3 + 4.
			--e.operator is a string that is a valid Terra operator.
			--we need to cast the result back to a double because it might be a comparison (3 < 4), which returns a bool
			return `double(operator(e.operator,operands))
		elseif "apply" == k then
			local fn = emitexp(e.fn)
			local arg = emitexp(e.argument)
			return `fn(arg)
		elseif "var" == k then
			--return the symbol from the local environment
			return env:localenv()[e.name]
		end
		error("??")
	end
	function emitstmts(stmts)
		env:enterblock()
		local r = stmts:map(emitstmt)
		env:leaveblock()
		return r
	end
	function emitstmt(s)
		local k = s.kind
		if "defvar" == k then
			local exp = emitexp(s.expression)
			--create a Terra symbol to represent this variable
			--we pass its type and a name in as arguments to make debugging the result easier
			--but it would be optional in this case
			local sym = symbol(gettype(s.expression.type),s.name) 
			env:localenv()[s.name] = sym --put this symbol in the local environment
			return quote var [sym] = exp end 
		elseif "return" == k then
			local exp = emitexp(s.expression)
			return quote return exp end
		elseif "assign" == k then
			local lhs = emitexp(s.lhs)
			local rhs = emitexp(s.rhs)
			return quote lhs = rhs end
		elseif "if" == k then
			local cond = emitexp(s.condition)
			local thenB = emitstmts(s.thenB)
			local elseB = emitstmts(s.elseB)
			--the ~= 0 here is to convert from double to boolean since there are not bools in eg
			return quote if cond ~= 0 then thenB else elseB end end
		end
		error("??")
	end

	local arg = symbol(gettype(typedcode.argtype),typedcode.name)
	env:enterblock() --scope for entire function
	env:localenv()[typedcode.arg] = arg --register the parameter symbol

	--create the terra function that implements this eg function
	local terra impl([arg]) : gettype(typedcode.returntype)
		[ emitstmts(typedcode.statements) ]
	end
	env:leaveblock()
	return impl
end

-- Return --------------------------------------------------------------------------
-- to register this extension with Terra, we return the language definition table
-- that defines the parser entry points and additional keywords

return langdefinition
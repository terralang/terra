Embedding Languages in Terra
============================

_Zach DeVito <zdevito@stanford.edu>_

This document decribes how to write a parser extension for Terra that will allow you to embed your own language in Lua similar to the way Terra code is embedded in Lua. For more information on Terra itself, see the `README`.

Overview
--------

Language extensions in the Terra system allow you to create custom Lua statements and expressions that you can use to implement your own embedded language. Each language registers a set of entry-point keywords that indicate the start of a statment or expression in your language. If the Terra parser sees one of these keywords at the beginning of a Lua expression or statement, it will switch control of parsing over to your language, where you can  parse the tokens into an abstract syntax tree (AST), or other intermediate representation. After creating the AST, your language then returns a _constructor_ function back to Terra parser. This function will be called during execution when your statement or expression should run.

This guide introduces language extensions with a simple stand-alone example, and shows how to register the extension with Terra. We then expand on this example by showing how it can interact with the Lua environment. The end of the guide documents the language extension interface, and the interface to the lexer in detail.


A Simple Example
----------------

To get started, let's add a simple language extension to Lua that sums up a list of numbers. The syntax will look like `sum 1,2,3 done`, and when run it will sum up the numbers, producing the value `6`. A language extension is defined using a Lua table. Here is the table for our language
	
	local sumlanguage = {
		name = "sumlanguage"; --name for debugging
		entrypoints = {"sum"}; -- list of keywords that will start our expressions
		keywords = {"done"}; --list of keywords specific to this language
		expression = function(self,lex) --called by Terra parser to enter this language
			--implementation here
		end;
	}

We list `sum` in the `entrypoint` list since we want Terra to hand control over to our language when it encounters this token at the beginning of an expression. We also list `done` as a keyword since we are using it to end our expression. When the Terra parser sees the `sum` token it will call the `expression` function passing in an interface to the lexer, `lex`. Here is the implemention:

	expression = function(self,lex)
		local sum = 0
		lex:expect("sum") --first token should be "sum"
		if not lex:matches("done") then
			repeat
				local v = lex:expect(lex.number).value --parse a number, return its value
				sum = sum + v
			until not lex:nextif(",") --if there is a comma, consume it and continue
		end

		lex:expect("done")
		--return a function that is run when this expression would be evaluated by lua
		return function(environment_function)
			return sum
		end
	end

We use the `lex` object to interact with the tokens. The interface is document below. Since the statement only allows numeric constants, we can perform the summation during parsing. Finally, we return a _constructor_ function that will be run everytime this statement is executed. We can use it in Lua code like so:

	print(sum 1,2,3 done) -- prints 6

The file `tests/lib/sumlanguage.t` contains the code for this example, and `tests/sumlanguage1.t` has an example of its use.

Loading and Running the Language
--------------------------------
In order to use our language extension, it needs to be registered with Terra runtime. If you are using the `terra` interpreter you can load language extensions with the `-l` flag:

	terra -l tests/lib/sumlanguage.t tests/sumlanguage1.t

The file specified should _return_ the Lua table describing your language:

	local sumlanguage = { ... } --fill in your table
	return sumlanguage

You can also register language extensions using Terra's C-API by calling `terra_loadlanguage(lua_State * L)` with the language table on the top of the Lua stack. From Lua, you can call `terralib.loadlanguage(mylang)`. However, since a file is parsed _before_ it is run, `terralib.loadlanguage` will only affect subsequent calls to `terra.loadfile`, not the current file.

Interacting with Lua symbols
----------------------------

One of the advantages of Terra is that it shares the same lexical scope as Lua, making it easy to parameterize Terra functions. Extensions languages can also access Lua's static scope. Let's example our sum language so that it supports both constant numbers, as well as Lua variables:
	
	local a = 4
	print(sum a,3 done) --prints 7

To do this we need to modify the code in our `expression` function:

	expression = function(self,lex)
		local sum = 0
		local variables = terralib.newlist()
		lex:expect("sum")
		if not lex:matches("done") then
			repeat
				if lex:matches(lex.name) then --if it is a variable
					local name = lex:next().value
					lex:ref(name) --tell the Terra parser we will access a Lua variable, 'name'
					variables:insert(name) --add its name to the list of variables
				else
					sum = sum + lex:expect(lex.number).value
				end
			until not lex:nextif(",")
		end
		lex:expect("done")
		return function(environment_function)
			local env = environment_function() --capture the local environment
			                                   --a table from variable name => value
			local mysum = sum
			for i,v in ipairs(variables) do
				mysum = mysum + env[v]
			end
			return mysum
		end
	end

Now an expression can be a varible name (`lex.name`). Unlike constants, we don't know the value of this variable at parse time, so we can calculate the entire sum then. Instead, we save the variable name (`variables:insert(name)`) and tell the Terra parser that will need to value of this variable at runtime )`lex:ref(name)`).  In our _constructor_ we now capture the local lexical environment by calling the `environment_function` parameter, and look up the values of our variables in the environment to compute the sum. It is important to call `lex:ref(name)`. If we had not called it, then this environment table will not contain the value of the variables we need.

Recursively Parsing Lua
-----------------------

Sometimes in the middle of your language you may want to call back into the Lua parser to parse an entire Lua expression. For instance, Terra types are Lua expressions:

	var a : int = 3

In this example, `int` is actually a Lua expression.

The method `lex:luaexpr()` will parse a Lua expression and returns a Lua function that implements expression. This functions takes the local lexical environment, and returns the value of the expression in that environment. As an example, let's add a concise way of specifying a single argument Lua function `def(a) exp` where `a` is a single argument and `exp` is a Lua expression. Here is our language:

	{
		name = "def";
		entrypoints = {"def"};
		keywords = {};
		expression = function(self,lex)
			lex:expect("def")
			lex:expect("(")
			local formal = lex:expect(lex.name).value
			lex:expect(")")
			local expfn = lex:luaexpr()
			return function(environment_function)
				--return our result, a single argument lua function
				return function(actual)
					local env = environment_function()
					--bind the formal argument to the actual one in our environment
					env[formal] = actual
					--evaluate our expression in the environment
					return expfn(env)
				end
			end
		end;
	}

The full code for this example can be found in `tests/lib/def.t` and `tests/def1.t`.

Extending Statements
--------------------

In addition to extending the syntax of expressions, you can also define new syntax for statements and local variable declarations:

	terra foo() end -- a new statement
	local terra foo() end -- a new local variable declaration

This is done by specifying the `statement` and `localstatement` functions in your language table. These function behave the same way as the `expression` function, but they can optionally return a list of names that they define. The file `test/lib/def.t` shows how this would work for the `def` constructor to support statements:
	
	def foo(a) luaexpr --defines global variable foo
	local def bar(a) luaexpr --defins local variable bar


Higher-Level Parsing via Pratt Parsers
--------------------------------------

Writing a parser that directly uses the lexer interface can be tedious. One simple approach that makes parsing easier (especially for expressions with multiple precedence levels) is Pratt parsing, or top-down precedence parsing (for more information, see http://javascript.crockford.com/tdop/tdop.html). We've provided a library built on top of the Lexer interface to help do this. It can be found, along with documentation of the API in `tests/lib/parsing.t`. An example extension written using this library is found in `tests/lib/pratttest.t` and `tests/pratttest1.t`. 

The Language and Lexer API
-------------------------

This section decribes the API for defining languages and interacting with the `lexer` object in detail. The Lua table that specifies your language requires that you define several fields:

* `name` a name for your language used for debugging
* `entrypoints` a Lua list specifying the keywords that can begin a term in your language. These keywords must not be a Terra or Lua keyword and cannot overlap with entry-points for other loaded languages (In the future, we may allow you to rename entry-points when you load a language to resolve conflicts). These keywords must be valid Lua identifiers (i.e. they must be alphanumeric and cannot start with anumber). In the future, we may expand this to allow arbitrary operators (e.g. `+=`) as well.
* `keywords` a Lua list specifying any additional keywords used your language. Like entry-points these also must be valid identifiers. A keyword in Lua or Terra is always considered a keyword in your language, so you do not need to list them here. 
* `expression` (Optional) A Lua method `function(self,lexer)` that is called whenever the parser encounters an entry-point keyword at the beginning of a Lua expression. `self` is your language object, and `lexer` is a Lua object used to interact with Terra's lexer to retrieve tokens and report errors. Its API is decribed below. The `expression` method should return a _constructor_ function `function(environment_function)`. The constructor is called every time the expression is evaluated and should return the value of the expression as it should appear in Lua code.  Its argument, `environment_function`, is a function  that when called, returns the local lexical environment.
* `statement` (Optional) A Lua method `function(self,lexer)` called when the parser encounters an entry-point keyword at the beginning of a Lua _statement_. Similar to `expression`, it returns a constructor function. Additionally, it can return a second argument that is a list of assignements that the statment performs to variables. For instance, the value `{ "a", "b", {"c","d"} }` will behave like the Lua statment `a,b,c.d = constructor(...)`
* `localstatement` (Optional) A Lua method `function(self,lexer)` called when the parser encounters an entry-point keyword at the beginning of a `local` statment (e.g. `local terra foo() end`). Similar to `statement` this method can also return a list of names (e.g. `{"a","b"}`). However, in this case, these names will be defined as local variables `local a, b = constructor(...)`

The methods in the Language are given an interface `lexer` to Terra _lexer_, which can be used to examine the stream of _tokens_, and report errors.  A _token_ is a Lua table with fields:

* `token.type` the _token type_. For keywords and operators this is just a string (e.g. `"and"`, or `"+"`). The values `lexer.name`, `lexer.number`, `lexer.string` indicate the token is respecitively an identifier (e.g. `myvar`), a number (e.g. 3), or a string (e.g. `"my string"`). The type `lexer.eof` indicates the end of the token stream. 
* `token.value` for names, strings, and numbers this is the specific value (e.g. `3.3`). Currently numbers are always represented as Lua numbers (i.e. doubles). In the future, we will extend this to include integral types as well.
* `token.linenumber` The linenumber on which this token occured (not availiable for lookahead tokens).
* `token.offset` The offset in characters from the beginning of the file where this token occured (not availiable for lookahead tokens).

The `lexer` object then provides the following methods fields and methods. The `lexer` itself is only valid during parsing and should _not_ be called from the constructor function.

* `lexer:cur()` Returns the current _token_. Does not modify the position.
* `lexer:lookahead()` Returns the _token_ following the current token. Does not modify the position. Only 1 token of lookahead is allowed to keep the implementation simple.
* `lexer:matches(tokentype)` shorthand for `lexer:cur().type == tokentype`
* `lexer:lookaheadmatches(tokentype)` shorthand for `lexer:lookahead().type == tokentype`
* `lexer:next()` Returns the current token, and advances to the next token.
* `lexer:nextif(tokentype)` If `tokentype` matches the `type` of the current token, it returns the token and advances the lexer. Otherwise, it returns `false` and does not advance the lexer. This function is useful when you want to try to parse many alternatives.
* `lexer:expect(tokentype)` If `tokentype` matches the `type of the current token, it returns the token and advances the lexer. Otherwise, it stops parsing an emits an error. It is useful to use when you know what token should appear.
* `lexer:expectmatch(tokentype,openingtokentype,linenumber)` Same as `expect` but provides better error reporting for matched tokens. For instance, to parse the closing brace '}' of a list you can call `lexer:expectmatch('}','{',lineno)`. It will report a mismatched bracket as well as the opening and closing lines.
* `lexer.source` A string containing the filename, or identifier for the stream (useful for future error reporting)
* `lexer:error(msg)` Report a parse error and give up. `msg` is a string. Does not return.
* `lexer:errorexpected(msg)` Report that the string `msg` was expected but did not appear. Does not return.
* `lexer:typetostring(tokentype)` Converts the token _type_ to a string. Useful for error reporting.
* `lexer:ref(name)` `name` is a string. Indicates to the Terra parser that your language may refer to the Lua variable `name`. This function must be called for any free identifiers that you are interested in looking up. Otherwise, the identifier may not appear in the lexical environment passed to your _constructor_ functions. It is safe (though less efficient) to call it for identifiers that may not  reference.
* `lexer:luaexpr()` Parses a single Lua expression from the token stream. This can be used to switch back into the Lua language for expressions in your language. For instance, Terra uses this to parse its types (which are just Lua expressions): `var a : aluaexpression(4) = 3`. It returns a function `function(lexicalenv)` that takes a table of the current lexical scope (such as the one return from `environment_function` in the constructor) and returns the value of the expression evaluated in that scope. This function is not indended to be used to parse a Lua expression into an AST. Currently, parsing a Lua expression into an AST requires you to writing the parser yourself. In the future we plan to add a library which will let you pick and choose pieces of Lua/Terra's grammer to use in your language.


Future Extensions
-----------------

* The Pratt parsing library will be extended to support composing multiple languages together

* We will use the composable Pratt parsing library to implement a library of common statements and expressions from Lua/Terra that will allow the user to pick and choose which statements to include, making it easy to get started with a language.





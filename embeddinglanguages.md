Embedding Languages in Terra
============================

_Zach DeVito <zdevito@stanford.edu>_

This document decribes how to write a parser extension for Terra that will allow you to embed your own language in Lua similar to the way Terra code is embedded in Lua. For more information on Terra itself, see the `README`.

Overview
--------

Language extensions in the Terra system allow you to create custom Lua statements and expressions that you can use to implement your own embedded language. Each language registers a set of entry-point keywords that indicate the start of a statment or expression in your language. If the Terra parser sees one of these keywords at the beginning of a Lua expression or statement, it will switch control of parsing over to your language, where you can  parse the tokens into an AST. After creating the AST, your language then returns a _constructor_ function back to Terra parser. This function will be called during execution when your statement or expression should run.

We first discuss how to load a language extension into the Terra runtime, and the go into detail about specifying its behavior.

Loading a Language
------------------
A language extension is defined using a Lua table like this one:

	{ 
	  name = "mylanguage";
	  keywords = "mykeyword";
	  entrypoints = "startmylanguage";
	  expression = function(self,lexer)
	     --parse an expression for my language
	  end;
	}

The precise details of the API are described later. In order to user your language extension, it needs to be registered with Terra runtime. If you are using the `terra` interpreter you can load language extensions with the `-l` flag:

	terra -l mylanguage.t my_script_using_my_language.t

The file `mylanguage.t` should _return_ the Lua table describing your language:

	local mylang = { ... } --fill in your table
	return mytable

You can also register language extensions using Terra's C-API by calling `terra_loadlanguage(lua_State * L)` with the language table on the top of the Lua stack. From Lua, you can call `terralib.loadlanguage(mylang)`. However, since a file is parsed _before_ it is run, `terralib.loadlanguage` will only affect subsequent calls to `terra.loadfile`, not the current file.

Specifying a Language
---------------------

The Lua table that specifies your language requires that you define several fields:

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
* `lexer:next()` Advances the current token. Returns nothing.
* `lexer:nextif(tokentype)` If `tokentype` matches the `type` of the current token, it returns the token and advances the lexer. Otherwise, it returns `false` and does not advance the lexer. This function is useful when you want to try to parse many alternatives.
* `lexer:expect(tokentype)` If `tokentype` matches the `type of the current token, it returns the token and advances the lexer. Otherwise, it stops parsing an emits an error. It is useful to use when you know what token should appear.
* `lexer:expectmatch(tokentype,openingtokentype,linenumber)` Same as `expect` but provides better error reporting for matched tokens. For instance, to parse the closing brace '}' of a list you can call `lexer:expectmatch('}','{',lineno)`. It will report a mismatched bracket as well as the opening and closing lines.
* `lexer.source` A string containing the filename, or identifier for the stream (useful for future error reporting)
* `lexer:error(msg)` Report a parse error and give up. `msg` is a string. Does not return.
* `lexer:errorexpected(msg)` Report that the string `msg` was expected but did not appear. Does not return.
* `lexer:typetostring(tokentype)` Converts the token _type_ to a string. Useful for error reporting.
* `lexer:ref(name)` `name` is a string. Indicates to the Terra parser that your language may refer to the Lua variable `name`. This function must be called for any free identifiers that you are interested in looking up. Otherwise, the identifier may not appear in the lexical environment passed to your _constructor_ functions. It is safe (though less efficient) to call it for identifiers that may not  reference.
* `lexer:luaexpr()` Parses a single Lua expression from the token stream. This can be used to switch back into the Lua language for expressions in your language. For instance, Terra uses this to parse its types (which are just Lua expressions): `var a : aluaexpression(4) = 3`. It returns a function `function(lexicalenv)` that takes a table of the current lexical scope (such as the one return from `environment_function` in the constructor) and returns the value of the expression evaluated in that scope. This function is not indended to be used to parse a Lua expression into an AST. Currently, parsing a Lua expression into an AST requires you to writing the parser yourself. In the future we plan to add a library which will let you pick and choose pieces of Lua/Terra's grammer to use in your language.


Examples
--------

TODO: a simple sum statement that works on identifiers

TODO: a short lambda form for Lua

Future Extensions
-----------------

* A library for doing top-down precedence parsing (i.e. Pratt parsers). 
* A library of common statements and expressions from Lua/Terra that allows the user to pick and choose which statements to include, making it easy to get started with a language.





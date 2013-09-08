---
layout: post
title: Terra API Reference
---
<h1>Terra API Reference</h1>

* auto-gen TOC:
{:toc}

C API
=====

Like Lua, Terra is designed to be embedded into existing code.
The C API for Terra serves as the entry-point for running Terra-Lua programs.
In fact, the `terra` executable and REPL are just clients of the C API. The Terra C API extends [Lua's API](http://www.lua.org/manual/5.1/manual.html#3) with a set of Terra-specific functions. A client first creates a `lua_State` object and then calls `terra_init` on it to initialize the Terra extensions. Terra provides equivalents to the `lua_load` set of functions (e.g. `terra_loadfile`), which treat the input as Terra-Lua code.

---
    int terra_init(lua_State * L);

Initializes the internal Terra state for the `lua_State` `L`. `L` must be an already initialized `lua_State`.

---
    int terra_load(lua_State *L,
                   lua_Reader reader,
                   void *data,
                   const char *chunkname);

Loads a combined Terra-Lua chunk. Terra equivalent of `lua_load`. This function takes the same arguments as `lua_load` and performs identically except it parses the input as a combined Terra-Lua program (i.e. a Lua program that has Terra extensions). Currently there is no binary format for combined Lua-Terra code, so the input must be text.

---
    
    int terra_loadfile(lua_State * L, const char * file);

Loads the file as a combined Terra-Lua chunk. Terra equivalent of `luaL_loadfile`.

---

    int terra_loadbuffer(lua_State * L, 
                         const char *buf, 
                         size_t size, 
                         const char *name);

Loads a buffer as a combined Terra-Lua chunk. Terra equivalent of `luaL_loadbuffer`.

---

    int terra_loadstring(lua_State *L, const char *s);

Loads string `s` as a combined Terra-Lua chunk. Terra equivalent of `luaL_loadstring`.

---
    
    int terra_setverbose(lua_State * L, int v);

Sets the verbosity for Terra libraries. Valid values are 0 (no debug output) to 2 (very verbose).

---

    terra_dofile(L, file)
    
Loads and runs the file `file`. Equivalent to
    
    (terra_loadfile(L, fn) || lua_pcall(L, 0, LUA_MULTRET, 0))
    
---

    terra_dostring(L, s)

Loads and runs the string `s`. Equivalent to

    (terra_loadstring(L, s) || lua_pcall(L, 0, LUA_MULTRET, 0))



Lua API
=======

Terra provides syntax extensions for creating Terra functions, types, and quotations.
Each of these extensions constructs a first-class Lua value. Terra's Lua API is used to manipulate these objects. For instance, you can disassemble a function (`terrafn:disas()`), or query properties of a type (`typ:isarithmetic()`).

List
----

Lists are a simple wrapper around Lua tables that provides some additional functionality.
They are returned from other API calls (e.g. `func:getdefinitions()`)

---

    terralib.newlist([lst])

Creates a new list. `lst` is an optional table to use as the initializer.

---

    terralib.islist(exp)

True if `exp` is a list.


---

    list:map(fn)

Standard list map function. `fn` is a Lua function that takes an element of the list and returns another object. 

---

    list:flatmap(fn)

The value `fn` should be a function that takes an element of the list and then returns a _list_ of elements. Creates a new list by calling `fn` on each element and concatenating the results.

---

    terralib.israwlist(l)

Returns true if `l` is a table that has no keys or has a contiguous range of integer keys from `1` to `N` for some `N`, and contains no other keys.

Function
--------

Terra functions are entry-points into Terra code. Each function can contain 0 or more [Function Definitions](#function_definition). A function with 0 definitions is the equivalent of a function declaration in other statically typed languages. One definition indicates a simple function, and multiple definitions is the equivalent of an [overloaded function](http://en.wikipedia.org/wiki/Function_overloading).

---

    [local] terra myfunctionname
    
_Terra function declaration_. If `myfunctionname` is not already a Terra function, it creates a new function with 0 definitions and stores it the Lua variable `myfunctionname`. If `myfunctionname` is already a function, then it does not modify it.
If the optional `local` keyword is used, then `myfunctionname` is first defined as a new local Lua variable.  When used without the `local` keyword, `myfunctionname` can be a table specifier (e.g. `a.b.c`). If `mystruct` is a [Struct](#structs), then `mystruct:mymethod` is equivalent to using the specifier `mystruct.methods.mymethod`.

---

    [local] terra myfunctionname(arg0 : type0, 
                                 ... 
                                 argN : typeN) 
            [...] 
    end 

_Terra function definition_. Adds the [function definition](#function_definition) specified by the code to the Terra function `myfunctionname`. If `myfunctionname` is not a Terra function, then it first creates a new function declaration using the same rules as Terra function declarations.  If `myfunctionname` is a method specifier (e.g. `terra mystruct:mymethod(arg0 : type0,...)`), then it is desugared to `terra mystruct.methods.mymethod(self : &mystruct, arg0 : type0,...)`.

---

    myfunction(arg0,...,argN)

`myfunction` is a Terra function. Invokes `myfunction` from Lua. It is an error to call this on a function with 0 definitions.  This utility method calls `funcdefinition(arg0,...argN)` on each of this functions definitions until it finds one that does not produce an error. For functions with a single definition this is equivalent to calling the the function definition directly. See the documentation for calling [function definitions](#function_definition) for more details.

---

    func:compile(async)

Utility method that calls `funcdefinition:compile(async)` on each definition of this function. See the documentation for [function definitions](#function_definition) for more details about compilation. Can be called [asynchronously](#asynchronous_compilation).

---

    func:emitllvm(async)

Utility method that calls `funcdefinition:emitllvm(async)` on each definition of this function. See the documentation for [function definitions](#function_definition) for more details about compilation. Can be called [asynchronously](#asynchronous_compilation).

---

    func:adddefinition(v)

Adds a new function definition `v` to this function.

---

    func:getdefinitions()

Returns a [List](#lists) of definitions for this function.

---

    func:printstats()

Prints statistics about how long this function took to compile and JIT. Will cause the function definitions to compile.

---

    func:disas()

Disassembles all of the function definitions into x86 assembly and optimized LLVM, and prints them out. Useful for debugging performance. Will cause the function definitions to compile.

---

    func:printpretty([printcompiled])

Print out a visual representation of the code in this function. If `printcompiled` is `false`, then this will print out an untyped version of the function. Otherwise, this will cause the function
definitions to compile, and print out a type-checked representation of the function (with all macros and method invocations expanded).

---

    terralib.isfunction(obj)

True if `obj` is a Terra function.

Function Definition
-------------------

Function definitions are concrete implementations of a function. Each definition is compiled lazily. A function definition may be (1) uncompiled, (2) in the process of type-checking, (3) emitted to LLVM but not JITed to machine code, or (4) JITed to machine code. Functions will only be in state (2) during calls to the Terra compiler, but may still be observable to user-defined functions like macros and metamethods that run during type-checking.

---

    function terralib.isfunctiondefinition(obj)

True if `obj` is a function definition.

---

    r0, ..., rn = myfuncdefinition(arg0, ... argN)
    
Invokes `myfunctiondefinition` from Lua. Arguments are converted into the expected Terra types using the [rules](#converting_between_lua_values_and_terra_values) for converting between Terra values and Lua values. Return values are converted back into Lua values using the same rules. Causes the function to be compiled to machine code.

---

    success, typ = funcdefinition:peektype()

Attempt to find out the type of this definition but do _not_ compile it. If `success` is `true` then `typ` is the [type](#types) of the function. Otherwise, the function did not have an explicitly annotated return type and was not already compiled. 

---

    funcdefinition:compile(async)

Compile the function into machine code. Can be called [asynchronously](#asynchronous_compilation).

---

    funcdefinition:emitllvm(async)

Compile the function into LLVM but do not JIT to machine code. Can be called [asynchronously](#asynchronous_compilation). This is used for offline compilation where the machine code is not needed.

---

    typ = funcdefinition:gettype(async)

Return the [type](#types) of the function. This will cause the function to be emitted to LLVM. Can be called [asynchronously](#asynchronous_compilation).

---

    funcdefinition:getpointer()

Return the LuaJIT `ctype` object that points to the machine code for this function. Will cause the function to be compiled.


Constant
--------

Terra constants represent constant values used in Terra code. For instance, if you want to create a [lookup table](http://en.wikipedia.org/wiki/Lookup_table) for the `sin` function, you might first use Lua to calculate the values and then create a constant Terra array of floating point numbers to hold the values. Since the compiler knows the array is constant (as opposed to a global variable), it can make more aggressive optimizations.

---

    constant([type],init)

Create a new constant. `init` is converted to a Terra value using the normal conversion [rules](#converting_between_lua_values_and_terra_values). If the optional [type](#types) is specified, then `init` is converted to that `type` explicitly. [Completes](#types) the type.

---

    terralib.isconstant(obj)

True if `obj` is a Terra constant.



Global Variable
---------------

Global variables are Terra values that are shared among all Terra functions. 

---

    global([type], [init])

Creates a new global variable of type `type` given the initial value `init`. Either `type` or `init` must be specified. If `type` is not specified we attempt to infer it from `init`. If `init` is not specified the global is left uninitialized. `init` is converted to a Terra value using the normal conversion [rules](#converting_between_lua_values_and_terra_values). If `init` is specified, this [completes](#types) the type.

---

    globalvar:getpointer()

Returns the `ctype` object that is the pointer to this global variable in memory. [Completes](#types) the type.

---

    globalvar:get()

Gets the value of this global as a LuaJIT `ctype` object. [Completes](#types) the type.

---

    globalvar:set(v)

Converts `v` to a Terra values using the normal conversion [rules](#converting_between_lua_values_and_terra_values), and the global variable to this value. [Completes](#types) the type.

Macro
-----

Macros allow you to insert custom behavior into the compiler during type-checking. Because they run during compilation, they should be aware of [asynchronous compilation](#asynchronous_compilation) when calling back into the compiler.

---

    macro(function(arg0,arg1,...,argN) [...] end)

Create a new macro. The function will be invoked at compile time for each call in Terra code.  Each argument will be a Terra [quote](#quote) representing the argument. For instance, the call `mymacro(a,b,foo())`), will result in three quotes as arguments to the macro.  The macro must return a single value that will be converted to a Terra object using the compilation-time conversion [rules](#converting_between_lua_values_and_terra_values).

---

    terralib.ismacro(t)
    
True if `t` is a macro.


Escapes
-------

Escapes are a special construct adapted from [multi-stage programming](http://www.cs.rice.edu/~taha/MSP/) that allow you to use Lua to generate Terra expressions. Escapes are created using the bracket operator and contain a single lua expression (e.g. `[ 4 + 5 ]`) that is evaluated when the surrounding Terra code is _defined_ (note: this is different from [macros](#macros) which run when a function is _compiled_). Escapes are evaluated in the lexical scope of the Terra code. In addition to including the identifiers in the surround Lua scope, this scope will include any identifiers defined in the Terra code. In Lua code these identifiers are represented as [symbols](#symbol). For example, in the following escape:

    terra foo(a : int)
        var b = 4
        return [dosomething(a,b)]
    end

The arguments `a` and `b` to `dosomething` will be [symbols](#symbols) that are references to the variables defined in the Terra code. 

We also provide syntax sugar for escapes of identifiers and table selects when they are used in expressions or statements. For instance the Terra expression `ident` is treated as the escape `[ident]`, and the table selection `a.b.c` is treated as the escape `[a.b.c]` when both `a` and `b` are Lua tables.

---

    terra foo()
        return [luaexpr],4
    end 

`[luaexpr]` is a single-expression escape. `luaexpr` is a single Lua expression that is evaluated to a Lua value when the function is _defined_. The resulting Lua expression is converted to a Terra object using the compilation-time conversion [rules](#converting_between_lua_values_and_terra_values). If the conversion results in a list of Terra values, it is truncated to a single value.

---
    terra foo()
        bar(3,4,[luaexpr])
    end
    
`[luaexpr]` is a multiple-expression escape since it occurs as the last expression in a list of expressions. It has the same behavior as a single expression escape, except when the conversion of `luaexpr` results in multiple Terra expressions. In this case, the values are appended to the end of the expression list (in this case, the list of arguments to the call to `bar`).

---
    
    terra foo()
        [luaexpr]
        return 4
    end

`[luaexpr]` is a statement escape. This form has the same behavior as a multiple-expression escape but is also allowed to return [quotes](#quote) of Terra statements. If the conversion from `luaexpr` results in a list of Terra values, then are all inserted into the current block.

---

    terra foo([luaexpr] : int)
        var [luaexpr] = 4
        mystruct.[luaexpr]
    end

Each `[luaexpr]` is an example of a escape of an identifier. `luaexpr` must result in a [symbol](#symbol). For field selectors (`a.[luaexpr]`), methods (`a:[luaexpr]()`) or labels (`goto [luaexpr]`), `luaexpr` can also result in a string. This form allows you to define identifiers programmatically. When a symbol with an explicitly defined type is used to define a variable, then the variable will take the type of the symbol unless the type of the variable is explicitly specified. For instance if we construct a symbol (`foo = symbol(int)`), the `var [foo]` will have type `int`, and `var [foo] : float` will have type `float`.

---

    terra foo(a : int, [luaexpr])
    end
    
`[luaexpr]` is an escape of a list of identifiers. In this case, it behaves similarly to an escape of a single identifier, but may also return a list of explicitly typed symbols which will be appended as parameters in the parameter list.

Quote
-----

Quotes are an operator from  [multi-stage programming](http://www.cs.rice.edu/~taha/MSP/) that allows you to construct a Terra statement or expression from Lua code. When quotes are returned from escapes, metamethods, they code they contain is spliced into the surrounding Terra code.

---
    `terraexpr

The backtick operator creates a quotation that contains a single terra _expression_. `terraexpr` can be any Terra expression. Any escapes that `terraexpr` contains will be evaluated when the expression is constructed.

---
    quote
        terrastmts
    end

The `quote` operator creates a quotation that contains a list of terra _statements_. These can only be spliced into Terra code where a statement would normally appear.
 

---
    quote
        terrastmts
    in
        terraexp1,terraexp2,...,terraexpN
    end

The `quote` operation can also include an optional `in` statement that creates several expressions. This `quote` can be spliced into Terra code where an expression would normally appear and behaves like a function that returns multiple values.

---

    terralib.isquote(t)

Returns true if `t` is a quote.

---

    typ = quoteobj:astype()

Try to interpret this quote as if it were a Terra type object. This is normally used in [macros](#macros) that expect a type as an argument (e.g. `sizeof([&int])`). This function converts the `quote` object to the type (e.g. `&int`).

---

    typ = quoteobj:gettypes()

If the quote object is a typed expression that was passed as an argument to a macro, this will return the list of types for the values that will result when it is evaluated. For simple quotes (e.g. with the backtick operator) this will return exactly one type. But for more complicated expressions (e.g. `quote var a = 1 in a, 2 * a end`), this may return zero or more types. 

---
    
    typ = quoteobj:gettype()

If the quote object is a typed expression that was passed as an argument to a macro, this returns the type of the value that will result when it is evaluated. Equivalent to `quoteobj:gettypes()[1]`. It is an error if the quoted expression results in no values.

---

    luaval = quoteobj:asvalue()

Try to interpret this quote as if it were a simple Lua value. This is normally used in [macros](#macros) that expect constants as an argument (e.g. the macro that truncates expressions `truncate(2,foo())`). Currently only supports very simple constants (e.g. numbers). Consider using an escape rather than a macro when you want to pass more complicated data structures to generative code.

---

    quoteobj:printpretty()

Print out a visual representation of the code in this quote. Because quotes are not type-checked until they are placed into a function, this will print an untyped representation of the function.

Symbol
------

Symbols are abstract representations of Terra identifiers. They can be used in Terra code where an identifier is expected (e.g. a variable use, a variable definition, a field name, a method name, a label). They are similar to the symbols returned by LISP's `gensym` function. 

---

    terralib.issymbol(s)

True if `s` is a symbol.

---

    symbol([typ],[displayname])

Construct a new symbol. This symbol will be unique from any other symbol. `typ` is an optional type for the symbol. If the symbol is used in a variable definition without an explicit type, then the variable will use `typ` as its type. `displayname` is an optional name that will be printed out in error messages when this symbol is encountered.


Types
-----

Type objects are first-class Lua values that represent the types of Terra objects. Terra's built-in type system closely resembles that of low-level languages like C.  Type constructors are valid Lua expressions.  To support recursive types like linked lists, [Struct](#structs) can be declared before their members and methods are fully specified.When a struct is declared but not defined, it is _incomplete_ and cannot be used as value. However, pointers to incomplete types can be used as long as no pointer arithmetic is required. A type will become _complete_ when it needs to be fully specified (e.g. we are using it in a compiled function, or we want to allocate a global variable with the type). At this point a full definition for the type must be available.

---
    
    int int8 int16 int32 int64
    uint  uint8 uint16 uint32 uint64
    bool
    float double
    
Primitive types.

---

    &typ
    
Constructs a pointer to `typ`.

---

    typ[N]

Constructs an array of `N` instances of type `typ`. `N` must be a positive integer.

---
    vector(typ,N)

Constructs a vector of `N` instances of type `typ`. `N` must be an integer and `typ` must be a primitive type. These types are abstractions vector instruction sets like [SSE](http://en.wikipedia.org/wiki/Streaming_SIMD_Extensions).

---

    parameters -> returns
    
Constructs a function pointer. Both  `parameters`  and `returns` can be lists of types (e.g. `{int,int}`) or a single type `int`. 

---

    struct { field0 : type2 , ..., fieldN : typeN }

Constructs a structural type. We use a [nominative](http://en.wikipedia.org/wiki/Nominative_type_system) type systems for structs, so each call to `struct` returns a unique type. Structs are the primary user-defined data-type. See [Structs](#structs) for more information.

---

    terralib.types.istype(t)

True if `t` is a type.

---

    type:isprimitive()

True if `type` is a primitive type (see above).

---

    type:isintegral()

True if `type` is any integer type. 

---

    type:isfloat()

True if `type` is `float` or `double`.

---

    type:isarithmetic()

True if `type` is integral or float.

---

    type:islogical()

True if `type` is `bool` (we might eventually supported sized boolean types that are closer to the machine representation of flags in vector instructions).

---

    type:canbeord()

True if the `type` can be used in expressions `or` and `and` (i.e. integral and logical but not float).

---

    type:ispointer()

True if `type` is a pointer. `type.type` is the type pointed to.

---

    type:isarray()

True if `type` is an array. `type.N` is the length. `type.type` is the element type.

---

    type:isfunction()

True if `type` is a function (not a function pointer). `type.returns` is a list of return types. `type.parameters` is a list of parameter types.

---

    type:isstruct()

True if `type` is a [struct](#structs).

---

    type:ispointertostruct()

True if `type` is a pointer to a struct.

---

    function types.type:ispointertofunction()

True if `type` is a pointer to a function.

---

    type:isaggregate() 

True if `type` is an array or a struct (any type that can hold arbitrary types).

---

    type:iscomplete()

True if the `type` is fully defined and ready to use in code. This is always true for non-aggregate types. For aggregate types, this is true if all types that they contain have been defined. Call type:complete() to force a type to become complete.

---

    type:isvector()

True if the `type` is a vector. `type.N` is the length. `type.type` is the element type.

---

    type:(isprimitive|isintegral|isarithmetic|islogical|canbeord)orvector()

True if the `type` is a primitive type with the requested property, or if it is a vector of a primitive type with the requested property.

---

    type:complete()

Forces the type to be complete. For structs, this will calculate the layout of the struct (possibly calling `__getentries` and `__staticinitialize` if defined), and recursively complete any types that this type references.

Structs 
-------

Structs are Terra's user-defined Type. Each struct has a list of `entries` which describe the layout of the type in memory, a table of `methods` which can be invoked using the `obj:method(arg)` syntax sugar, and a table of `metamethods` which allow you to define custom behavior for the type (e.g. custom type conversions). 

---
    [local] struct mystruct
    
_Struct declaration_ If `mystruct` is not already a Terra struct, it creates a new struct and stores it the Lua variable `mystruct`. If `mystruct` is already a struct, then it does not modify it. If the optional `local` keyword is used, then `mystruct` is first defined as a new local Lua variable.  When used without the `local` keyword, `mystruct` can be a table specifier (e.g. `a.b.c`).

    [local] struct mystruct {
        field0 : type0;
        ...
        union {
            fieldUnion0 : type1;
            fieldUnion1 : type2;
        }
        ...
        fieldN : typeN;
    }

_Struct definition_. If `mystruct` is not already a Struct, then it creates a new struct with the behavior of struct declarations. It then fills in the `entries` table of the struct with the fields and types specified in the body of the defintion. The `union` block can be used to specify that a group of fields should share the same location in memory. If `mystruct` was previously given a definition, then defining it again will result in an error.

---

    terralib.types.newstruct([displayname])

Constructs and returns a new struct. `displayname` is an option name that will be displayed by error messages.

---

    mystruct.entries

The `entries` field is a [List](#list) of field entries. Each field entry is one of:
* A table `{ field = stringorsymbol, type = terratype }`, specifying a named field.
* Type `terratype`, specifying an anonymous field that will be given a name (e.g. `_0`, `_1`, ...) automatically.
* A [List](#list) of field entries that will be allocated together in a union.

---

    mystruct.methods

The `methods` field is a table mapping strings or [symbols](#symbol) to functions (both Lua/Terra) or [macros](#macros). In Terra code the expression `myobj:mymethod(arg0,...argN)` will be desugared to `[T.methods.mymethod](myobj,arg0,...,argN)` if type of `myobj` is `T`. If the type of `myobj` is `&T` then this desugars to `[T.methods.mymethod](@myobj,arg0,...,argN)`. Additionally, when a method is invoked as a method and its first argument has `T` but the formal parameter has type `&T` then the argument will be automatically converted to a pointer by taking its address. This _method reciever cast_ allows method calls on objects to modify the object.

---

    mystruct.metamethods

The `metamethods` field can be used to extend the behavior of structs by definition the following fields:

* `entries = __getentries(self)` -- a _Lua_ function that overrides the default behavior that determines the fields in a struct. By default, `__getentries` just returns the `self.entries` table. It can be overridden to determine the fields in the struct computationally. The `__getentries` function will be called by the compiler once when it first requires the list of entries in the struct. Since the type is not yet complete during this call, doing anything in this method that requires the type to be complete will result in an error.
* `method = __getmethod(self,methodname)` -- a _Lua_ function that overrides the default behavior that looks up a method for a struct statically. By default, `__getmethod(self,methodname)` will return `self.methods[methodname]`. If the resulting value is `nil` then it will call `__methodmissing` as described below. By defining `__getmethod`, you can change the behavior of method lookup. This metamethod will be called by the compiler for every static invocation of `methodname` on this type. Since it can be called multiple times for the same `methodname`, any expensive operations should be memoized across calls. 
* `__staticinitialize(self)` -- a _Lua_ function called after the type is complete but before the compiler returns to user-defined code. Since the type is complete, you can now do things that require a complete type such as create vtables, or examine offsets using the `terralib.offsetof`. The static initializers for entries in a struct will run before the static initializer for the struct itself.
* `castedexp = __cast(from,to,exp)` -- a _Lua_ function that can define conversions between your type and another type. `from` is the type of `exp`, and `to` is the type that is required.  For type `mystruct`, `__cast` will be called when either `from` or `to` is of type `mystruct` or type `&mystruct`. If there is a valid conversion, then the method should return `castedexp` where `castedexp` is the expression that converts `exp` to `to`. Otherwise, it should report a descriptive error using the `error` function. The Terra compiler will try any applicable `__cast` metamethod until it finds one that works.
* `__methodmissing(methodname,arg0,...,argN)` -- A terra macro that is called when `methodname` is not found in the method table of the type. It should return a Terra expression to use in place of the method call.
* custom operators: `__sub, __add, __mul, __div, __mod, __lt, __le, __gt, __ge,`
    `__eq, __ne, __and, __or, __not, __xor, __lshift, __rshift,` 
    `__select, __apply, __get` Can be either a Terra method, or a macro. These are invoked when the type is used in the corresponding operator. `__apply` is used for function application, `__get` for field selection `mystruct.missingfield` for a field that doesn't exist in the struct, and `__select` for `terralib.select`.  In the case of binary operators, at least one of the two arguments will have type `mystruct`. The interface for custom operators hasn't been heavily tested and is subject to change.


C Backwards Compatibility
-------------------------

Terra uses the [Clang](http://clang.llvm.org) frontend to allow Terra code to be backwards compatible with C. The current implementation of this functionality is somewhat limited. For instance, including a C header will only import the functions and any types that those functions refer to, but will not import global variables, enums, or types that are not used by functions. This will be improved in the future.

---

    table = terralib.includecstring(code,...)

Import the string `code` as C code.  Flags to Clang can be passed as additional arguments (e.g. `includecstring(code,"-I","..")`). Returns a Lua table mapping the names of included C functions to Terra [function](#function) objects, and names of included C types (e.g. typedefs) to Terra [types](#types).

---

    table = terralib.includec(filename,...)

Similar to `includecstring` except that C code is loaded from `filename`. This uses Clangs default path for header files. `...` allows you to pass additional arguments to Clang (including more directories to search).

---

    terralib.linklibrary(filename)
    
Load the dynamic library in file  `filename`. If header files imported with `includec` contain declarations whose definitions are not linked into the executable in which Terra is run, then it is necessary to dynamically load the definitions with `linklibrary`. This situation arises when using external libraries with the `terra` REPL/driver application. 

Managing Terra Values from Lua
------------------------------

We provide wrappers around LuaJIT's [FFI API](http://luajit.org/ext_ffi.html) that allow you to allocate and manipulate Terra objects directly from Lua.

---

    terralib.typeof(obj)

Return the Terra type of `obj`. Object must be a LuaJIT `ctype` that was previously allocated using calls into the Terra API, or as the return value of a Terra function. 

---

    terralib.new(terratype,[init])

Wrapper around LuaJIT's `ffi.new`. Allocates a new object with the type `terratype`. `init` is an optional initializer that follows the [rules](#converting_between_lua_values_and_terra_values) for converting between Terra values and Lua values. This object will be garbage collected if it is no longer reachable from Lua.

---

    terralib.sizeof(terratype)

Wrapper around `ffi.typeof`. Completes the `terratype` and returns its size in bytes.

---

    terralib.offsetof(terratype,field)

Wrapper around `ffi.offsetof`. Completes the `terratype` and returns the offset in bytes of `field` inside `terratype`.


---

    terralib.cast(terratype,obj)

Wrapper around `ffi.cast`. Converts `obj` to `terratype` using the [rules](#converting_between_lua_values_and_terra_values) for converting between Terra values and Lua values.


Loading Terra Code
-------------------

These functions allow you to load chunks of mixed Terra-Code code at runtime.

---

    terralib.load(readerfn)

Lua equivalent of C API call `terra_load`. `readerfn` behaves the same as in Lua's `load` function.

---

    terralib.loadstring(s)

Lua equivalent of C API call `terra_loadstring`. 

---

    terralib.loadfile(filename)

Lua equivalent of C API call `terra_loadfile`.
 
---

    terralib.require(modulename)
    
Load the terra code `modulename`. `require` first checks if `modulename` has already been loaded by a previous call to `require`, returning the previously loaded results if available. Otherwise it searches `package.path` for the module. `package.path` is a semi-colon separated list of templates, e.g.:
    
    "lib/?.t;./?.t"
    
The `modulename` is first converted into a path by replacing any `.` with a directory separator, `/`. Then each template is tried until a file is found. For instance, using the example path, the call `terralib.require("foo.bar")` will try to load `lib/foo/bar.t` or `foo/bar.t`. If a file is found, then `require` will return the result of calling `terralib.loadfile` on the file. By default, `package.path` is set to the environment variable `LUA_PATH`. If `LUA_PATH` is not set then `package.path` will contain `./?.t` as a path.

Converting between Lua values and Terra values
----------------------------------------------

When compiling or invoking Terra code, it is necessary to convert values between Terra and Lua. Internally, we implement this conversion on top of LuaJIT's [foreign-function interface](http://luajit.org/ext_ffi.html), which makes it possible to call C functions and use C values directly from Lua. Since Terra type system is similar to that of C's, we can reuse most of this infrastructure.  

### Converting Lua values to Terra values of known type ###

When converting Lua values to Terra, we sometimes know the expected type (e.g. when the type is specified in a `terralib.cast` or `terralib.constant` call). In the case, we follow LuaJIT's [conversion semantics](http://luajit.org/ext_ffi_semantics.html#convert_fromlua), substituting the equivalent C type for each Terra type.

### Converting Lua values to Terra values with unknown type ###

When a Lua value is used directly from Terra code through an [escape](#escapes)), or a Terra value is create without specifying the type (e.g. `terralib.constant(3)`), then we attempt the infer the type of the object. If successful, then the standard conversion is applied. If the `type(value)` is:

* `cdata` -- If it was previously allocated from the Terra API, or returned from Terra code, then it is converted into the Terra type equivalent to the `ctype` of the object.
* `number` -- If `floor(value) == value` and value can fit into an `int` then the type is an `int` otherwise it is `double`.
* `boolean` -- the type is `bool`.
* `string` -- converted into a `rawstring` (i.e. a `&int8`). We may eventually add a special string type.
* otherwise -- the type cannot be inferred. If you know the type of the object, then you use a `terralib.cast` function to specify it. 

### Compile-time conversions ###

When a Lua value is used as the result of an [escape](#escapes) operator in a Terra function, additional conversions are allowed:

* [Global Variable](#global_variable) -- value becomes a lvalue reference to the global variable in Terra code.
* [Symbol](#symbol) -- value becomes a lvalue reference to the variable defined using the symbol. If the variable is not in scope, this will become a compile-time error.
* [Quote](#quote) -- the code defined in the quote will be spliced into the Terra code. If the quote contains only statements, it can only be spliced in where a statement appears.
* [Constant](#constant) -- the constant is spliced into the Terra code.
* Lua Function -- If used in a function call, the lua function is `terralib.cast` to the Terra function type that has no return values, and whose parameters are the Terra types of the actual parameters of the function call. If not use in a function call, results in an error.
* [Macro](#macro) -- If used as a function call, the macro will be run at compile time. The result of the macro will then be convert to Terra using the compile-time conversion rules and spliced in place.
* [Type](#types) -- If used as an argument to a macro call, it will be passed-through such that calling `arg:astype()` will return the value. If used as a function call (e.g. `[&int](v)`, it acts as an explicit cast to that type.
* [List](#list) or a rawlist (as classified by `terralib.israwlist`) -- Each member of the list is recursively converted to a Lua value using compile-time conversions (excluding the conversions for Lists). If used as a statement or where multiple expressions can appear, all values of the list are spliced in place. Otherwise, if used where only a single expression can appear, the list is truncated to 1 value.
* `cdata` aggregates (structs and arrays) -- If a Lua `cdata` aggregate of Terra type `T` is referenced directly in Terra code, the value in Terra code will be an lvalue reference of type `T` to the Lua-allocated memory that holds that aggregate. 
* otherwise -- the value is first converted to a Terra vlue using the standard rules for converting Lua to Terra values with unknown type. The resulting value is then spliced in place as a _constant_.



### Converting Terra values to Lua values ###

When converting Terra values back into Lua values (e.g. from the results of a function call), we follow LuaJIT's [conversion semantics](http://luajit.org/ext_ffi_semantics.html#convert_tolua) from C types to Lua objects, substituting the equivalent C type for each Terra type.

Asynchronous Compilation
------------------------

When the Terra compiler encounters a [macro](#macros) or [metamethod](#structs), it can call back into user-defined code. The user-defined code in a macro or metamethod might need to create additional Terra functions or types, and try to compile and run Terra functions. This means user-defined code can _re-enter_ the Terra compiler. For the most part this behavior works fine.  However, it is possible for user-defined code to try to compile a function or complete a type that is _already_ being compiled. In this case, the call to `compile` will report an error since it cannot fulfill the (circular) request. It is possible that the user-defined code doesn't need the compilation to finish while inside the macro, but only needs the compilation finished before the compiler returns control to user code that called it synchronously.

If the `async` argument to a compilation function is not `nil` or `false`, then the function is called asynchronous. It may return before the compilation is complete and only needs to be finished by the time the compiler returns to a synchronous call. Furthermore, if `async` is a Lua function, then it will be registered as a callback that will be invoked as soon as the requested compilation operation has completed (in the simple cases where there is no recursive loop, it will just be invoked immediately). 

Situations requiring callbacks arise when building class systems that have virtual function tables (vtables). To build a vtable, you need to compile the concrete implementations of the type's methods and then fill in the vtable with these values. However, it is possible that these functions were already being compiled. In this case, we still need to compile these functions and fill-in the vtable, but cannot finish this task inside the type's `__staticinitialize` metamethod.  By calling compile asynchronously and registering a callback that fills in the vtable, we can guarantee that the vtable is filled in before the call to the compiler returns while allowing `__staticinitialize` to return before the vtable is complete. Callbacks are guaranteed to be invoked before returning to user-defined code that invoked the compiler synchronously. So we know that the vtable will be initialized before any of this newly compiled code is run.

Debugging
---------

Terra provides a few library functions to help debug and performance tune code.

---

    terra terralib.traceback(uctx : &opaque)

A Terra function that can be called from Terra code to print a stack trace. If `uctx` is `nil` then this will print the current stack. `uctx` can also be a pointer to a `ucontext_t` object (see `ucontext.h`) and will print the stack trace for that context.
By default, the interpreter will print this information when a program segfaults.

---
    terra.currenttimeinseconds()

A Lua function that returns the current time in seconds since some fixed time in the past. Useful for performancing tuning Terra code.

Embedded Language API
=====================

Language extensions in the Terra system allow you to create custom Lua statements and expressions that you can use to implement your own embedded language. Each language registers a set of entry-point keywords that indicate the start of a statement or expression in your language. If the Terra parser sees one of these keywords at the beginning of a Lua expression or statement, it will switch control of parsing over to your language, where you can  parse the tokens into an abstract syntax tree (AST), or other intermediate representation. After creating the AST, your language then returns a _constructor_ function back to Terra parser. This function will be called during execution when your statement or expression should run.

This guide introduces language extensions with a simple stand-alone example, and shows how to register the extension with Terra. We then expand on this example by showing how it can interact with the Lua environment. The end of the guide documents the language extension interface, and the interface to the lexer in detail.


A Simple Example
----------------

To get started, let's add a simple language extension to Lua that sums up a list of numbers. The syntax will look like `sum 1,2,3 done`, and when run it will sum up the numbers, producing the value `6`. A language extension is defined using a Lua table. Here is the table for our language
    
    local sumlanguage = {
      name = "sumlanguage"; --name for debugging
      -- list of keywords that will start our expressions
      entrypoints = {"sum"}; 
      keywords = {"done"}; --list of keywords specific to this language
       --called by Terra parser to enter this language
      expression = function(self,lex)
        --implementation here
      end;
    }

We list `"sum"` in the `entrypoints` list since we want Terra to hand control over to our language when it encounters this token at the beginning of an expression. We also list `"done"` as a keyword since we are using it to end our expression. When the Terra parser sees the `sum` token it will call the `expression` function passing in an interface to the lexer, `lex`. Here is the implementation:

    expression = function(self,lex)
      local sum = 0
      lex:expect("sum") --first token should be "sum"
      if not lex:matches("done") then
        repeat
          --parse a number, return its value
          local v = lex:expect(lex.number).value 
          sum = sum + v
        --if there is a comma, consume it and continue
        until not lex:nextif(",") 
      end

      lex:expect("done")
      --return a function that is run 
      --when this expression would be evaluated by Lua
      return function(environment_function)
        return sum
      end
    end

We use the `lex` object to interact with the tokens. The interface is documented below. Since the statement only allows numeric constants, we can perform the summation during parsing. Finally, we return a _constructor_ function that will be run every time this statement is executed. We can use it in Lua code like so:

    print(sum 1,2,3 done) -- prints 6

The file `tests/lib/sumlanguage.t` contains the code for this example, and `tests/sumlanguage1.t` has an example of its use.

Loading and Running the Language
--------------------------------
In order to use our language extension, it needs to be _imported_.
The language extension mechanism includes an `import` statment to load the language extension:

    import "lib/sumlanguage" --active the new parsing rules
    result = sum 1,2,3 done

Since `import` statements are evaluated at _parse_ time, the argument must be a string literal. 
The parser will then call `terralib.require` on the string literal to load the language extension file.
The file specified should _return_ the Lua table describing your language:

    local sumlanguage = { ... } --fill in your table
    return sumlanguage

The imported language will be enabled only in the local scope where the import statement occured:

    do
        import "lib/sumlanguage"
        result = sum 1,2,3 done --ok, in scope
        if result == 6 then
            result = sum 4,5 done -- ok, still in scope
        end
    end
    result = sum 6,7 done --error! sumlanguage is not in scope

Multiple languages can be imported in the same scope as long as their `entrypoints` do not overlap.
If their entrypoints do overlap, the languages can still be imported in the same file as long as the `import` statements occur in different scopes.

Interacting with Lua symbols
----------------------------

One of the advantages of Terra is that it shares the same lexical scope as Lua, making it easy to parameterize Terra functions. Extension languages can also access Lua's static scope. Let's extend our sum language so that it supports both constant numbers, as well as Lua variables:
    
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
            --tell the Terra parser 
            --we will access a Lua variable, 'name'
            lex:ref(name) 
            --add its name to the list of variables
            variables:insert(name) 
          else
            sum = sum + lex:expect(lex.number).value
          end
        until not lex:nextif(",")
      end
      lex:expect("done")
      return function(environment_function)
        --capture the local environment
        --a table from variable name => value
        local env = environment_function() 
        local mysum = sum
        for i,v in ipairs(variables) do
          mysum = mysum + env[v]
        end
        return mysum
      end
    end

Now an expression can be a variable name (`lex.name`). Unlike constants, we don't know the value of this variable at parse time, so we cannot calculate the entire sum before execution. Instead, we save the variable name (`variables:insert(name)`) and tell the Terra parser that will need the value of this variable at runtime (`lex:ref(name)`).  In our _constructor_ we now capture the local lexical environment by calling the `environment_function` parameter, and look up the values of our variables in the environment to compute the sum. It is important to call `lex:ref(name)`. If we had not called it, then this environment table will not contain the variables we need.

Recursively Parsing Lua
-----------------------

Sometimes in the middle of your language you may want to call back into the Lua parser to parse an entire Lua expression. For instance, Terra types are Lua expressions:

    var a : int = 3

In this example, `int` is actually a Lua expression.

The method `lex:luaexpr()` will parse a Lua expression. It returns a Lua function that implements the expression. This functions takes the local lexical environment, and returns the value of the expression in that environment. As an example, let's add a concise way of specifying a single argument Lua function, `def(a) exp`, where `a` is a single argument and `exp` is a Lua expression. This is similar to Pythons `lambda` statement. Here is our language extension:

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
            --bind the formal argument 
            --to the actual one in our environment
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

Writing a parser that directly uses the lexer interface can be tedious. One simple approach that makes parsing easier (especially for expressions with multiple precedence levels) is Pratt parsing, or top-down precedence parsing (for more information, see http://javascript.crockford.com/tdop/tdop.html). We've provided a library built on top of the Lexer interface to help do this. It can be found, along with documentation of the API in `tests/lib/parsing.t`. An example extension written using this library is found in `tests/lib/pratttest.t` and an example program using it in `tests/pratttest1.t`. 

The Language and Lexer API
-------------------------

This section decribes the API for defining languages and interacting with the `lexer` object in detail.

### Language Table ###
A language extension is defined by a Lua table containing the following fields.

---

    name
    
a name for your language used for debugging

---

    entrypoints

A Lua list specifying the keywords that can begin a term in your language. These keywords must not be a Terra or Lua keyword and cannot overlap with entry-points for other loaded languages (In the future, we may allow you to rename entry-points when you load a language to resolve conflicts). These keywords must be valid Lua identifiers (i.e. they must be alphanumeric and cannot start with anumber). In the future, we may expand this to allow arbitrary operators (e.g. `+=`) as well.

---

    keywords

A Lua list specifying any additional keywords used in your language. Like entry-points, these also must be valid identifiers. A keyword in Lua or Terra is always considered a keyword in your language, so you do not need to list them here. 

---

    expression

(Optional) A Lua method `function(self,lexer)` that is called whenever the parser encounters an entry-point keyword at the beginning of a Lua expression. `self` is your language object, and `lexer` is a Lua object used to interact with Terra's lexer to retrieve tokens and report errors. Its API is decribed below. The `expression` method should return a _constructor_ function `function(environment_function)`. The constructor is called every time the expression is evaluated and should return the value of the expression as it should appear in Lua code.  Its argument, `environment_function`, is a function  that when called, returns the local lexical environment as Lua table from  variable names to values.

---

    statement 
    
(Optional) A Lua method `function(self,lexer)` called when the parser encounters an entry-point keyword at the beginning of a Lua _statement_. Similar to `expression`, it returns a constructor function. Additionally, it can return a second argument that is a list of assignements that the statment performs to variables. For instance, the value `{ "a", "b", {"c","d"} }` will behave like the Lua statment `a,b,c.d = constructor(...)`

---

    localstatement

(Optional) A Lua method `function(self,lexer)` called when the parser encounters an entry-point keyword at the beginning of a `local` statment (e.g. `local terra foo() end`). Similar to `statement` this method can also return a list of names (e.g. `{"a","b"}`). However, in this case, these names will be defined as local variables `local a, b = constructor(...)`

### Tokens ###

The methods in the language are given an interface `lexer` to Terra _lexer_, which can be used to examine the stream of _tokens_, and to report errors.  A _token_ is a Lua table with fields:

---

    token.type

The _token type_. For keywords and operators this is just a string (e.g. `"and"`, or `"+"`). The values `lexer.name`, `lexer.number`, `lexer.string` indicate the token is respectively an identifier (e.g. `myvar`), a number (e.g. 3), or a string (e.g. `"my string"`). The type `lexer.eof` indicates the end of the token stream. 

---

    token.value

For names, strings, and numbers this is the specific value (e.g. `3.3`). Currently numbers are always represented as Lua numbers (i.e. doubles). In the future, we will extend this to include integral types as well.

---

    token.linenumber

The linenumber on which this token occurred (not available for lookahead tokens).

---

    token.offset

The offset in characters from the beginning of the file where this token occurred (not available for lookahead tokens).

### Lexer ###

The `lexer` object provides the following methods fields and methods. The `lexer` itself is only valid during parsing. For instance, it should _not_ be called from the constructor function.

---

    lexer:cur()

Returns the current _token_. Does not modify the position.


---

    lexer:lookahead()

Returns the _token_ following the current token. Does not modify the position. Only 1 token of lookahead is allowed to keep the implementation simple.

---

    lexer:matches(tokentype)

shorthand for `lexer:cur().type == tokentype`

---

    lexer:lookaheadmatches(tokentype)

Shorthand for `lexer:lookahead().type == tokentype`

---

    lexer:next()

Returns the current token, and advances to the next token.

---

    lexer:nextif(tokentype)

If `tokentype` matches the `type` of the current token, it returns the token and advances the lexer. Otherwise, it returns `false` and does not advance the lexer. This function is useful when you want to try to parse many alternatives.

---

    lexer:expect(tokentype)

If `tokentype` matches the type of the current token, it returns the token and advances the lexer. Otherwise, it stops parsing an emits an error. It is useful to use when you know what token should appear.

---

    lexer:expectmatch(tokentype,openingtokentype,linenumber)

Same as `expect` but provides better error reporting for matched tokens. For instance, to parse the closing brace `}` of a list you can call `lexer:expectmatch('}','{',lineno)`. It will report a mismatched bracket as well as the opening and closing lines.

---

    lexer.source

A string containing the filename, or identifier for the stream (useful for future error reporting)

---

    lexer:error(msg)

Report a parse error and give up. `msg` is a string. Does not return.

---

    lexer:errorexpected(msg)

Report that the string `msg` was expected but did not appear. Does not return.

---

    lexer:ref(name)

`name` is a string. Indicates to the Terra parser that your language may refer to the Lua variable `name`. This function must be called for any free identifiers that you are interested in looking up. Otherwise, the identifier may not appear in the lexical environment passed to your _constructor_ functions. It is safe (though less efficient) to call it for identifiers that it may not reference.

---

    lexer:luaexpr()

Parses a single Lua expression from the token stream. This can be used to switch back into the Lua language for expressions in your language. For instance, Terra uses this to parse its types (which are just Lua expressions): `var a : aluaexpression(4) = 3`. It returns a function `function(lexicalenv)` that takes a table of the current lexical scope (such as the one return from `environment_function` in the constructor) and returns the value of the expression evaluated in that scope. This function is not intended to be used to parse a Lua expression into an AST. Currently, parsing a Lua expression into an AST requires you to writing the parser yourself. In the future we plan to add a library which will let you pick and choose pieces of Lua/Terra's grammar to use in your language.


Future Extensions
-----------------

* The Pratt parsing library will be extended to support composing multiple languages together

* We will use the composable Pratt parsing library to implement a library of common statements and expressions from Lua/Terra that will allow the user to pick and choose which statements to include, making it easy to get started with a language.





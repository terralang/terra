---
layout: post
title: Terra API Reference
---

---

* auto-gen TOC:
{:toc}

List
====

API calls in `terralib` that return arrays will always return a List object, which is a more complete List data type for use inside Lua code.

The List type is a plain Lua table with additional methods that come from:

1. all the methods in Lua's 'table' global
2. a list of higher-order functions based on [SML's (fairly minimal) list type](http://sml-family.org/Basis/list.html).

These make it easier to meta-program Terra objects.

---

    local List = require("terralist")

    List() -- empty list
    List { 1,2,3 } -- 3 element list

Creates a new list, possibly initialized by a table.

---

List also has the following functions:

     -- Lua's string.sub, but for lists
    list:sub(i,j)

    -- reverse list
    list:rev() : List[A]

    -- app fn to every element
    list:app(fn : A -> B) : {}

    -- apply map to every element resulting in new list
    list:map(fn : A -> B) : List[B]

     -- new list with elements where fn(e) is true
    list:filter(fn : A -> boolean) : List[A]

    -- apply map to every element, resulting in lists which are all concatenated together
    list:flatmap(fn : A -> List[B]) : List[B]

    -- find the first element in list satisfying condition
    list:find(fn : A -> boolean) : A?

    -- apply k,v = fn(e) to each element and group the values 'v' into bin of the same 'k'
    list:partition(fn : A -> {K,V}) : Map[ K,List[V] ]

    -- recurrence fn(a[2],fn(a[1],init)) ...
    list:fold(init : B,fn : {B,A} -> B) -> B

    -- recurrence fn(a[3],fn(a[2],a[1]))
    list:reduce(fn : {B,A} -> B) -> B

    -- is any fn(e) true in list
    list:exists(fn : A -> boolean) : boolean

    -- are all fn(e) true in list
    list:all(fn : A -> boolean) : boolean

Every function that takes a higher-order function also has an `i` variant that also provides the list index to the function:

    list:mapi(fn : {int,A} -> B) -> List[B]

---

List functions like `map` are higher-order functions that take a function as an argument.
For each function that is an argument of a high-order List function can be either:
1. a real Lua function
2. a string of an operator "+" (see op table in `src/terralist.lua`)
3. a string that specifies a field or method to call on the object

Example:
    local mylist = List { a,b,c }
    mylist:map("foo") -- selects the fields:  a.foo, b.foo, c.foo, etc.
                      -- if a.foo is a function it will be treated as a method a:foo()

Extra arguments to the higher-order function are passed through to these function. Rationale: Lua inline function syntax is verbose, this functionality avoids inline functions in many cases.

---
    local List = require("terralist")
    List:isclassof(exp)

True if `exp` is a list.

---

    terralib.israwlist(l)

Returns true if `l` is a table that has no keys or has a contiguous range of integer keys from `1` to `N` for some `N`, and contains no other keys.


Terra Reflection API
====================

Every Terra entity is also a first-class Lua object. These include Terra [Functions](#Functions), Terra [Types](#Types), and Terra [Global Variables](#global_variables). [Quotes](#quotes) are the objects returned by Terra's quotation syntax (backtick and `quote`), representing a fragment of Terra code not yet inside a Terra function.  [Symbols](#symbols) represent a unique name for a variables and are used to define new parameters and locals.

When a Terra function returns a value that cannot be converted into an equivalent Lua object, it turns into a Terra [Value](#values), which is a wrapper that can be accessed from Lua (Internally this is a LuaJIT `"cdata"` object).

Each object provides a Lua API to manipulate it. For instance, you can disassemble a function (`terrafn:disas()`), or query properties of a type (`typ:isarithmetic()`).

Generic
-------

    tostring(terraobj)
    print(terraobj)

All Terra objects have a string representation that you can use for debugging.

---
    terra.islist(t)
    terra.isfunction(t)
    terra.types.istype(t)
    terra.isquote(t)
    terra.issymbol(t)
    terra.ismacro(t)
    terra.isglobalvar(t)
    terra.islabel(t)
    terra.isoverloadedfunction(t)

Checks that a particular object is a type of Terra class.

---

    terralib.type(o)

Extended version of `type(o)` with the following definition:

    function terra.type(t)
       if terra.isfunction(t) then return "terrafunction"
       elseif terra.types.istype(t) then return "terratype"
       elseif terra.ismacro(t) then return "terramacro"
       elseif terra.isglobalvar(t) then return "terraglobalvariable"
       elseif terra.isquote(t) then return "terraquote"
       elseif terra.istree(t) then return "terratree"
       elseif terra.islist(t) then return "list"
       elseif terra.issymbol(t) then return "terrasymbol"
       elseif terra.isfunction(t) then return "terrafunction"
       elseif terra.islabel(t) then return "terralabel"
       elseif terra.isoverloadedfunction(t) then return "overloadedterrafunction"
       else return type(t) end
    end

---

    memoized_fn = terralib.memoize(function(a,b,c,...) ... end)

Memoize the result of a function. The first time a function is call with a particular set of arguments, it calls the function to calculate the return value and caches it. Subsequent calls with the same arguments (using Lua equality) will return that value. Useful for generating templated values, such as `Vector(T)` where the same vector type should be returned everytime for the same `T`.

Function
--------

Terra functions are entry-points into Terra code. Functions can be either defined or undefined (`myfunction:isdefined()`). An undefined function has a known type but its implementation has not yet been provided. The definition of a function can be changed via `myfunction:resetdefinition(another_function)` until it is first run.


---

    [local] terra myfunctionname :: type_expresion
    [local] terra myfunctionname :: {int,bool} -> {int}

_Terra function declaration_. It creates a new undefined function and stores it the Lua variable `myfunctionname`.
 If the optional `local` keyword is used, then `myfunctionname` is first defined as a new local Lua variable.  When used without the `local` keyword, `myfunctionname` can be a table specifier (e.g. `a.b.c`).

 <!--- If `mystruct` is a [Struct](#exotypes-structs), then `mystruct:mymethod` is equivalent to using the specifier `mystruct.methods.mymethod`. --->

---

    [local] terra myfunctionname(arg0 : type0,
                                 ...
                                 argN : typeN)
            [...]
    end

_Terra function definition_. Defines `myfunctioname` using the body of code specified. If `myfunctioname` already exists and is undefined, then it adds the definition to the existing function declaration. Otherwise it first creates a new function declaration and then adds the definition.

---

    local func = terralib.externfunction(function_name,function_type)

Create a Terra function bound to an externally defined function. Example:

    local atoi = terralib.externfunction("atoi",{rawstring} -> {int})

---

    myfunction(arg0,...,argN)

`myfunction` is a Terra function. Invokes `myfunction` from Lua. It is an error to call this on undefined functions. Arguments are translated to Terra using the [rules for translating Lua values to Terra](#converting-lua-values-to-terra-values-of-known-type) and return values are translated by using the [rules for translating Terra values to Lua](#converting-terra-values-to-lua-values).

---

    local b = func:isdefined()

`true` if function has a filled in definition. To define a function use `func:adddefinition`,
`func:resetdefinition` or using function definition syntax `terra func(...) ... end`.

---

    local b = func:isextern()

`true` if this function is bound to an external symbol like libc's `printf`. External functions are created either through importing C functions via `terralib.includec`, or by calling `terralib.externfunction`

---

    func:adddefinition(another_function)

Sets the definition of `func` to the current definition of `another_function`. `another_function` must be defined and `func` must be undefined. The types of `func` and `another_function` must match.

---

    func:resetdefinition(another_function)

Sets (or resets) the definition of `func` to the current definition of `another_function`. `another_function` must be defined. `func` may or may not be defined. It is an error to call this on a function that has already been compiled.

---

    func:printstats()

Prints statistics about how long this function took to compile and JIT. Will cause the function to compile.

---

    func:disas()

Disassembles all of the function definitions into x86 assembly and optimized LLVM, and prints them out. Useful for debugging performance. Will cause the function definition to compile.

---

    func:printpretty([quote_per_line=true])

Print out a visual representation of the code in this function. By default, this prints each part of the code that was originally specified on a separate line as a individual lines. If `quote_per_line` is `false`, it will print a more collapsed representation that may be easier to read.

---

    r0, ..., rn = myfunc(arg0, ... argN)

Invokes `myfunctiondefinition` from Lua. Arguments are converted into the expected Terra types using the [rules](#converting-between-lua-values-and-terra-values) for converting between Terra values and Lua values. Return values are converted back into Lua values using the same rules. Causes the function to be compiled to machine code.

---

    func:compile()

Compile the function into machine code. Ensures that every function and global variable needed by the function is also defined.

---

    function_type = func:gettype()

Return the [type](#types) of the function. `function_type.parameters` is a list of the parameters types. `function_type.returntype` is the return type. If the function returns multiple values, this return type will be a tuple.

---

    func:getpointer()

Return the LuaJIT `ctype` object that points to the machine code for this function. Will cause the function to be compiled.

---

    str = func:getname()
    func:setname(str)

Get or set the pretty name for the function. This is useful when viewing generated code but does not otherwise change the behavior of the function.

---

    func:setinlined(bool)

When `true` function when be always inlined. When `false` the function will never be inlined. By default, functions will be inlined at the descrection of LLVM's function inliner.

Types
-----

Type objects are first-class Lua values that represent the types of Terra objects. Terra's built-in type system closely resembles that of low-level languages like C.  Type constructors (like `&int`) are valid Lua expressions that return Terra type objects.  To support recursive types like linked lists, [structs](#exotypes-structs) can be declared before their members and methods are fully specified. When a struct is declared but not defined, it is _incomplete_ and cannot be used as value. However, pointers to incomplete types can be used as long as no pointer arithmetic is required. A type will become _complete_ when it needs to be fully specified (e.g. we are using it in a compiled function, or we want to allocate a global variable with the type). At this point a full definition for the type must be available.

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

    parameters -> returntype

Constructs a function pointer. Both  `parameters`  and `returns` can be lists of types (e.g. `{int,int}`) or a single type `int`. If `returntype` is a list, a `tuple` of the values in the list is the type returned from the function.

---

    struct { field0 : type2 , ..., fieldN : typeN }

Constructs a user-defined type, or exotype. Each call to `struct` creates a unique type since we use a [nominative](http://en.wikipedia.org/wiki/Nominative_type_system) type systems. See [Exotypes](#exotypes-structs) for more information.

---

    tuple(type0,type1,...,typeN)

Constructs a tuple, which is a special kind of `struct` that contains the values `type0`... `typeN` as fields `obj._0` .... `obj._N`.  Unlike normal structs, each call to `tuple` with the same arguments will return the same type.

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

True if `type` is a function (not a function pointer). `type.parameters` is a list of parameter types. `type.returntype` is return type. If a function returns multiple values this type will be a `tuple` of the values.

---

    type:isstruct()

True if `type` is a [struct](#exotypes-structs).

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

    type:isunit()

True if the `type` is the empty tuple. The empty tuple is also the return type of functions that return no values.

---

    type:(isprimitive|isintegral|isarithmetic|islogical|canbeord)orvector()

True if the `type` is a primitive type with the requested property, or if it is a vector of a primitive type with the requested property.

---

    type:complete()

Forces the type to be complete. For structs, this will calculate the layout of the struct (possibly calling `__getentries` and `__staticinitialize` if defined), and recursively complete any types that this type references.

    type:printpretty()

Print the type, including its members if it is a struct.

---

    terralib.sizeof(terratype)

Wrapper around `ffi.sizeof`. Completes the `terratype` and returns its size in bytes.

---

    terralib.offsetof(terratype,field)

Wrapper around `ffi.offsetof`. Completes the `terratype` and returns the offset in bytes of `field` inside `terratype`.



Quotes
------

Quotes are the Lua objects that get returned by terra quotation operators (backtick and `quote ... in ... end`). They rerpresent a fragment of Terra code (a statement or expression) that has not been placed into a function yet. The escape operators (`[...]` and `escape ... emit ... end`) splice quotes into the surround Terra code. Quotes have a short form for generating just one _expression_ and long form for generating _statements and expressions_.

---
    quotation = `terraexpr
    -- `create a quotation

The short form of a quotation. The backtick operator creates a quotation that contains a single terra _expression_. `terraexpr` can be any Terra expression. Any escapes that `terraexpr` contains will be evaluated when the expression is constructed.

---
    quote
        terrastmts
    end

The long form of a quotation. The `quote` operator creates a quotation that contains a list of terra _statements_. This quote can appear where an expression or a statement would be legal in Terra code. If it appears in an expression context, its type is the empty tuple.

---

    quote
        terrastmts
    in
        terraexp1,terraexp2,...,terraexpN
    end

The long `quote` operation can also include an optional `in` statement that creates several expressions. When this `quote` is spliced into Terra code where an expression would normally appear, its value is the tuple constructed by those expressions.

    local a = quote
        var a : int = foo()
        var b : int = bar()
    in
        a + b + b
    end
    terra f()
        var c : int = [a] -- 'a' has type int.
    end

---

    terralib.isquote(t)

Returns true if `t` is a quote.

---

    typ = quoteobj:gettype()

Return the Terra type of this quotation.

---

    typ = quoteobj:astype()

Try to interpret this quote as if it were a Terra type object. This is normally used in [macros](#macros) that expect a type as an argument (e.g. `sizeof([&int])`). This function converts the `quote` object to the type (e.g. `&int`).


---

    bool = quoteobj:islvalue()

`true` if the quote can be used on the left hand size of an assignment (i.e. it is an l-value).

---


    luaval = quoteobj:asvalue()

Try to interpret this quote as if it were a simple Lua value. This is normally used in [macros](#macros) that expect constants as an argument. Only works for a subset of values (anything that can be a Constant expression). Consider using an escape rather than a macro when you want to pass more complicated data structures to generative code.

---

    quoteobj:printpretty()

Print out a visual representation of the code in this quote. Because quotes are not type-checked until they are placed into a function, this will print an untyped representation of the function.


Symbol
------

Symbols are abstract representations of Terra identifiers. They can be used in Terra code where an identifier is expected, e.g. a variable use, a variable definition, a function argument, a field name, a method name, a label (see also [Escapes](#escapes)). They are similar to the symbols returned by LISP's `gensym` function.

---

    terralib.issymbol(s)

True if `s` is a symbol.

---

    symbol(typ,[displayname])

Construct a new symbol. This symbol will be unique from any other symbol. `typ` is the type for the symbol. `displayname` is an optional name that will be printed out in error messages when this symbol is encountered.

Values
------

We provide wrappers around LuaJIT's [FFI API](http://luajit.org/ext_ffi.html) that allow you to allocate and manipulate Terra objects directly from Lua.

---

    terralib.typeof(obj)

Return the Terra type of `obj`. Object must be a LuaJIT `ctype` that was previously allocated using calls into the Terra API, or as the return value of a Terra function.

---

    terralib.new(terratype,[init])

Wrapper around LuaJIT's `ffi.new`. Allocates a new object with the type `terratype`. `init` is an optional initializer that follows the [rules](#converting-between-lua-values-and-terra-values) for converting between Terra values and Lua values. This object will be garbage collected if it is no longer reachable from Lua.

---

    terralib.cast(terratype,obj)

Wrapper around `ffi.cast`. Converts `obj` to `terratype` using the [rules](#converting-between-lua-values-and-terra-values) for converting between Terra values and Lua values.


Global Variables
----------------

Global variables are Terra values that are shared among all Terra functions.

---
    global(type,[init,name,isextern])
    global(init,[name,isextern])

Creates a new global variable of type `type` given the initial value `init`. Either `type` or `init` must be specified. If `type` is not specified we attempt to infer it from `init`. If `init` is not specified the global is left uninitialized. `init` is converted to a Terra value using the normal conversion [rules](#converting-between-lua-values-and-terra-values). If `init` is specified, this [completes](#types) the type.

`init` can also be a [Quote](#quote), which will be treated as a [constant expression](#constants) used to initialized the global.
`name` is used as the debugging name for the global.
If `isextern` is true, then this global is bound to an externally defined variable with the name `name`.

---

    globalvar:getpointer()

Returns the `ctype` object that is the pointer to this global variable in memory. [Completes](#types) the type.

---

    globalvar:get()

Gets the value of this global as a LuaJIT `ctype` object. [Completes](#types) the type.

---

    globalvar:set(v)

Converts `v` to a Terra values using the normal conversion [rules](#converting-between-lua-values-and-terra-values), and the global variable to this value. [Completes](#types) the type.


---

    globalvar:setname(str)
    str = globalvar:getname()

Set or get the debug name for this global variable. This can help with debugging but does not otherwise change the behavior of the global.

---

    typ = globalvar:gettype()

Get the terra type of the global variable.

---

    globalvar:setinitializer(init)

Set or change the initializer expression for this global. Only valid before the global is compiled. This can be used to update the value of a globalvar as you add more code to the system. For instance, if you have a global variable storing the vtable for you class, you can add more values to it as you add methods to the class.

Constant
--------

Terra constants represent constant values used in Terra code. For instance, if you want to create a [lookup table](http://en.wikipedia.org/wiki/Lookup_table) for the `sin` function, you might first use Lua to calculate the values and then create a constant Terra array of floating point numbers to hold the values. Since the compiler knows the array is constant (as opposed to a global variable), it can make more aggressive optimizations.

---

    constant([type],init)

Create a new constant. `init` is converted to a Terra value using the normal conversion [rules](#converting-between-lua-values-and-terra-values). If the optional [type](#types) is specified, then `init` is converted to that `type` explicitly. [Completes](#types) the type.

`init` can also be a Terra [quote](#quotes) object. In this case the quote is treated as a _constant initializer expresssion_:

    local complexobject = constant(`Complex { 3, 4 })
    --`

Constant expressions are a subset of Terra expressions whose values are guaranteed to be constant and correspond roughly to LLVM's concept of a constant expression. They can include things whose values will be constant after compilation but whose value is not known beforehand such as the value of a function pointer:

    terra a() end
    terra b() end
    terra c() end
    -- array of function pointers to a,b, and c.
    local functionarray = const(`array(a,b,c))
    -- `

---

    terralib.isconstant(obj)

True if `obj` is a Terra constant.

Macro
-----

Macros allow you to insert custom behavior into the compiler during type-checking. Because they run during compilation, they should be aware of [asynchronous compilation](#asynchronous-compilation) when calling back into the compiler.

---

    macro(function(arg0,arg1,...,argN) [...] end)

Create a new macro. The function will be invoked at compile time for each call in Terra code.  Each argument will be a Terra [quote](#quote) representing the argument. For instance, the call `mymacro(a,b,foo())`), will result in three quotes as arguments to the macro.  The macro must return a single value that will be converted to a Terra object using the compilation-time conversion [rules](#converting-between-lua-values-and-terra-values).

---

    terralib.ismacro(t)

True if `t` is a macro.

Exotypes (Structs)
------------------

We refer to Terra's way of creating user-defined aggregate types as exotypes
because they are defined *external* to Terra itself, using a Lua API.
The design tries to provide the raw mechanisms for defining the behavior of user-defined types without imposing any language-specific policies. Policy-based class systems such as those found in Java or C++ can then be created as libraries on top of these raw mechanisms. For conciseness and familiarity, we use the keyword `struct` to refer to these types in the language itself.

We also provide syntax sugar for defining exotypes for the most common cases.
This section first discuses the Lua API itself, and then shows how the syntax sugar translates into it.

More information on the rationale for this design is available in our [publications](publications.html).

### Lua API

A new user-defined type is created with the following call:

        mystruct = terralib.types.newstruct([displayname])

`displayname` is an optional name that will be displayed by error messages, but each call to `newstruct` creates a unique type regardless of name (We use a [nominative](http://en.wikipedia.org/wiki/Nominative_type_system) type system. The type can then be used in Terra programs:

    terra foo()
        var a : mystruct --instance of mystruct type
    end

The memory layout and behavior of the type when used in Terra programs is defined by setting *property functions* in the types `metamethods` table:

    mystruct.metamethods.myproperty = function ...

When the Terra typechecker needs to know information about the type, it will call the property function in the metamethods table of the type. If a property is not set, it may have a default behavior which is discussed for each property individually.

The following fields in `metamethods` are supported:

----

    entries = __getentries(self)

A _Lua_ function that determines the fields in a struct computationally. The `__getentries` function will be called by the compiler once when it first requires the list of entries in the struct. Since the type is not yet complete during this call, doing anything in this method that requires the type to be complete will result in an error. `entries` is a [List](#list) of field entries. Each field entry is one of:

* A table `{ field = stringorsymbol, type = terratype }`, specifying a named field.
* A table `{stringorsymbol,terratype}`, also specifying a named field.
* A [List](#list) of field entries that will be allocated together in a union sharing the same memory.

By default, `__getentries` just returns the `self.entries` table, which is set by the `struct` definition syntax.

----

    method = __getmethod(self,methodname)

A _Lua_ function looks up a method for a struct when the compiler sees a method invocation `mystruct:mymethod(...)` or a static method lookup `mystruct.mymethod`.  `mymethod` may be either a string or a [symbol](#symbol). This metamethod will be called by the compiler for every static invocation of `methodname` on this type. Since it can be called multiple times for the same `methodname`, any expensive operations should be memoized across calls.
`method` may be a Terra function, a Lua function, or a [macros](#macro) which will run during typechecking.

Assuming that `__getmethod` returns the value `method`, then in Terra code the expression `myobj:mymethod(arg0,...argN)` turns into `[method](myobj,arg0,...,argN)` if type of `myobj` is `T`.

If the type of `myobj` is `&T` then it desugars to `[method](@myobj,arg0,...,argN)`.
If, when a method is invoked, `myobj` has type `T` but the formal parameter has type `&T` then the argument will be automatically converted to a pointer by taking its address. This _method receiver cast_ allows method calls on objects to modify the object.

By default, `__getmethod(self,methodname)` will return `self.methods[methodname]`, which is set by the method definition syntax sugar. If the table does not contain the method, then the typechecker will call `__methodmissing` as described below.

----

    __staticinitialize(self)

A _Lua_ function called after the type is complete but before the compiler returns to user-defined code. Since the type is complete, you can now do things that require a complete type such as create vtables, or examine offsets using the `terralib.offsetof`. The static initializers for entries in a struct will run before the static initializer for the struct itself.

----

    castedexp = __cast(from,to,exp)`

A _Lua_ function that can define conversions between your type and another type. `from` is the type of `exp`, and `to` is the type that is required.  For type `mystruct`, `__cast` will be called when either `from` or `to` is of type `mystruct` or type `&mystruct`. If there is a valid conversion, then the method should return `castedexp` where `castedexp` is the expression that converts `exp` to `to`. Otherwise, it should report a descriptive error using the `error` function. The Terra compiler will try any applicable `__cast` metamethod until it finds one that works (i.e. does not call `error`).

----

    __methodmissing(mymethod,myobj,arg1,...,argN)

When a method is called `myobj:mymethod(arg0,...,argN)` and `__getmethod` is not set, then the macro `__methodmissing` will be called if `mymethod` is not found in the method table of the type. It should return a Terra [quote](#quote) to use in place of the method call.

----

    __entrymissing(entryname,myobj)

If `myobj` does not contain the filed `entryname`, then `__entrymissing` will be called whenever the typechecker sees the expression `myobj.entryname`. It must be a macro and should return a Terra [quote](#quote) to use in place of the field.

Custom operators:

    __sub, __add, __mul, __div, __mod, __lt, __le, __gt, __ge,
    __eq, __ne, __and, __or, __not, __xor, __lshift, __rshift,
    __select, __apply

Can be either a Terra method, or a macro. These are invoked when the type is used in the corresponding operator. `__apply` is used for function application, and `__select` for `terralib.select`.  In the case of binary operators, at least one of the two arguments will have type `mystruct`. The interface for custom operators hasn't been heavily tested and is subject to change.

----

    __typename(self)

A _Lua_ function that generates a string that names the type. This name will be used in error messages and `tostring`.

### Syntax Sugar

---

    [local] struct mystruct

_Struct declaration_ If `mystruct` is not already a Terra struct, it creates a new struct by calling `terralib.types.newstruct("mystruct")` and stores it in the Lua variable `mystruct`. If `mystruct` is already a struct, then it does not modify it. If the optional `local` keyword is used, then `mystruct` is first defined as a new local Lua variable.  When used without the `local` keyword, `mystruct` can be a table specifier (e.g. `a.b.c`).

----

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

_Struct definition_. If `mystruct` is not already a Struct, then it creates a new struct with the behavior of struct declarations. It then fills in the `entries` table of the struct with the fields and types specified in the body of the definition. The `union` block can be used to specify that a group of fields should share the same location in memory. If `mystruct` was previously given a definition, then defining it again will result in an error.

----

    terra mystruct:mymethod(arg0 : type0,..., argN : typeN)
        ...
    end


_Method definition_. If `mystruct.methods.mymethod` is not a Terra function, it creates one. Then it adds the method definition. The formal parameter `self` with type `&mystruct` will be added to beginning of the formal parameter list.

Overloaded Functions
--------------------

Overloaded functions are separate objects from normal Functions and are created using an API call:

    local addone = terralib.overloadedfunction("addone",
                  { terra(a : int) return a + 1 end,
                    terra(a : double) return a + 1 end })


You can also add methods later:

    addone:adddefinition(terra(a : float) return a + 1 end)

Unlike normal functions overloaded functions cannot be called directly from Lua.

---

    overloaded_func:getdefinitions()

Returns the [List](#lists) of definitions for this function.

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

`[luaexpr]` is a single-expression escape. `luaexpr` is a single Lua expression that is evaluated to a Lua value when the function is _defined_. The resulting Lua expression is converted to a Terra object using the compilation-time conversion [rules](#converting-between-lua-values-and-terra-values). If the conversion results in a list of Terra values, it is truncated to a single value.

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


Using C Inside Terra
====================

Terra uses the [Clang](http://clang.llvm.org) frontend to allow Terra code to be backwards compatible with C. The current implementation of this functionality currently supports importing all functions, types, and enums from C header files. It will also import any macros whose definitions are a single number representable in a double such as:

    #define FOO 1

However, we currently do not support importing global variables or constants. This will be improved in the future.

---

    table = terralib.includecstring(code,[args,target])

Import the string `code` as C code. Returns a Lua table mapping the names of included C functions to Terra [function](#function) objects, and names of included C types (e.g. typedefs) to Terra [types](#types). The Lua variable `terralib.includepath` can be used to add additional paths to the header search. It is a semi-colon separated list of directories to search. `args` is an optional list of strings that are flags to Clang (e.g. `includecstring(code,"-I","..")`). `target` is a [target](#targets) object that makes sure the headers are imported correctly for the target desired.

---

    table = terralib.includec(filename,[args,target])

Similar to `includecstring` except that C code is loaded from `filename`. This uses Clangs default path for header files. `...` allows you to pass additional arguments to Clang (including more directories to search).

---

    terralib.linklibrary(filename)

Load the dynamic library in file  `filename`. If header files imported with `includec` contain declarations whose definitions are not linked into the executable in which Terra is run, then it is necessary to dynamically load the definitions with `linklibrary`. This situation arises when using external libraries with the `terra` REPL/driver application.

---

    local llvmobj = terralib.linkllvm(filename)
    local sym = llvmobj:extern(functionname,functiontype)

Link an LLVM bitcode file `filename` with extension `.bc` generated with `clang` or `clang++`:

    clang++ -O3 -emit-llvm -c mycode.cpp -o mybitcode.bc

The code is loaded as bitcode rather than machine code. This allows for more aggressive optimization (such as inlining the function calls) but will take longer to initialize in Terra since it must be compiled to machine code. To extract functions from this bitcode file, call the `llvmobj:extern` method providing the function's name in the bitcode and its Terra-equivalent type (e.g. `int -> int`).


Converting between Lua values and Terra values
==============================================

When compiling or invoking Terra code, it is necessary to convert values between Terra and Lua. Internally, we implement this conversion on top of LuaJIT's [foreign-function interface](http://luajit.org/ext_ffi.html), which makes it possible to call C functions and use C values directly from Lua. Since Terra type system is similar to that of C's, we can reuse most of this infrastructure.

### Converting Lua values to Terra values of known type ###

When converting Lua values to Terra, we sometimes know the expected type (e.g. when the type is specified in a `terralib.cast` or `terralib.constant` call). In the case, we follow LuaJIT's [conversion semantics](http://luajit.org/ext_ffi_semantics.html#convert-fromlua), substituting the equivalent C type for each Terra type.

### Converting Lua values to Terra values with unknown type ###

When a Lua value is used directly from Terra code through an [escape](#escapes), or a Terra value is create without specifying the type (e.g. `terralib.constant(3)`), then we attempt the infer the type of the object. If successful, then the standard conversion is applied. If the `type(value)` is:

* `cdata` -- If it was previously allocated from the Terra API, or returned from Terra code, then it is converted into the Terra type equivalent to the `ctype` of the object.
* `number` -- If `floor(value) == value` and value can fit into an `int` then the type is an `int` otherwise it is `double`.
* `boolean` -- the type is `bool`.
* `string` -- converted into a `rawstring` (i.e. a `&int8`). We may eventually add a special string type.
* otherwise -- the type cannot be inferred. If you know the type of the object, then you use a `terralib.cast` function to specify it.

### Compile-time conversions ###

When a Lua value is used as the result of an [escape](#escapes) operator in a Terra function, additional conversions are allowed:

* [Global Variable](#global-variable) -- value becomes a lvalue reference to the global variable in Terra code.
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

When converting Terra values back into Lua values (e.g. from the results of a function call), we follow LuaJIT's [conversion semantics](http://luajit.org/ext_ffi_semantics.html#convert-tolua) from C types to Lua objects, substituting the equivalent C type for each Terra type. If the result is a `cdata` object, it can be used with the Terra [Value API](#values).

Loading Terra Code
==================

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

    require(modulename)

Load the terra code `modulename`. Terra adds an additional code loader to Lua's `package.loaders` to handle the loading of Terra code as a module. `require` first checks if `modulename` has already been loaded by a previous call to `require`, returning the previously loaded results if available. Otherwise it searches `package.terrapath` for the module. `package.terrapath` is a semi-colon separated list of templates, e.g.:

    "lib/?.t;./?.t"

The `modulename` is first converted into a path by replacing any `.` with a directory separator, `/`. Then each template is tried until a file is found. For instance, using the example path, the call `require("foo.bar")` will try to load `lib/foo/bar.t` or `foo/bar.t`. If a file is found, then `require` will return the result of calling `terralib.loadfile` on the file. By default, `package.terrapath` is set to the environment variable `TERRA_PATH`. If `TERRA_PATH` is not set then `package.terrapath` will contain the default path (`./?.t`). The string `;;` in `TERRA_PATH` will be replaced with this default path if it exists.

Note that normal Lua code is also imported using `require`. There are two search paths `package.path` (env `LUA_PATH`), which will load code as pure Lua, and `package.terrapth` (env: `TERRA_PATH`), which will load code as Lua-Terra code.


Compilation API
===============

Saving Terra Code
-------------------

---

    terralib.saveobj(filename [, filetype], functiontable[, arguments, target, optimize])

Save Terra code to an external representation such as an object file, or executable. `filetype` can be one of `"object"` (an object file `*.o`), `"asm"` (an assembly file `*.s`), `"bitcode"` (LLVM bitcode `*.bc`), `"llvmir"` (LLVM textual IR `*.ll`), or `"executable"` (no extension).
If `filetype` is missing then it is inferred from the extension. `functiontable` is a table from strings to Terra functions. These functions will be included in the code that is written out with the name given in the table.
`arguments` is an additional list that can contain flags passed to the linker when `filetype` is `"executable"`. If `filename` is `nil`, then the file will be written in memory and returned as a Lua string.

To cross-compile objects for a different architecture, you can specific a [target](#targets) object, which describes the architecture to compile for. Otherwise `saveobj` will use the native architecture.

If `optimize` is `false` then LLVM optimizations are skipped when generating the output file. Otherwise optimizations are enabled.

Targets
-------

The functions `terralib.saveobj` and `terralib.includec` take an optional target object, that tells the compiler to compile the code for a different architecture. These targets  can be used for cross-compilation. For example, to use an x86 machine to to compile ARM code for a Raspberry Pi, you can create the following target object:

    local armtarget = terralib.newtarget {
        Triple = "armv6-unknown-linux-gnueabi"; -- LLVM target triple
        CPU = "arm1176jzf-s";,  -- LLVM CPU name,
        Features = ""; -- LLVM feature string
        FloatABIHard = true; -- For ARM, use floating point registers
    }

All entries in the table except the `Triple` field are optional. [Documentation](http://clang.llvm.org/docs/CrossCompilation.html) for `clang` includes more information about what these strings should be set to.

Debugging
=========

Terra provides a few library functions to help debug and performance tune code. Except for `currenttimeinseconds`,
these debugging facilities are only available on OSX and Linux.

---

    terralib.currenttimeinseconds()

A Lua function that returns the current time in seconds since some fixed time in the past. Useful for performancing tuning Terra code.

---

    terra terralib.traceback(uctx : &opaque)

A Terra function that can be called from Terra code to print a stack trace. If `uctx` is `nil` then this will print the current stack. `uctx` can also be a pointer to a `ucontext_t` object (see `ucontext.h`) and will print the stack trace for that context.
By default, the interpreter will print this information when a program segfaults.

---

    terra terralib.backtrace(addresses : &&opaque, naddr : uint64, ip : &opaque, frameaddress : &opaque)

A low-level interface used to get the return addresses from a machine stack. `addresses` must be a pointer to a buffer that can hold at least `naddr` pointers.
`ip` should be the address of the current instruction and will be the first entry in `addresses`, while `frameaddress` should be the value of the base pointer.
`addresses` will be filled with the return addresses on the stack. Requires debugging mode to be enabled (`-g`) for it to work correctly.

---

    terra terralib.disas(addr : &opaque, nbytes : uint64, ninst : uint64)

A low-level interface to the disassembler. Print the disassembly of instructions starting at `addr`. Will print `nbytes` of instructions or `ninst` instructions, whichever causes more instructions to be printed.

---

    terra terralib.lookupsymbol(ip : &opaque, addr : &&opaque, size : &uint64, name : &rawstring, namelength : &uint64) : bool

Attempts to look up information about a Terra function given a pointer  `ip` to any instruction in the function. Returns `true` if successful,
filling in `addr` with the start of the function and `size` with the size of the function in bytes. Fills in `name` with a pointer to a fixed-width string of to `namemax` characters holding the function name.

---

    terra terralib.lookupline(fnaddr : &opaque, ip : &opaque, filename : &rawstring, namelength : &uint64, line : &uint64) : bool

Attempts to look up information about a Terra instruction given a pointer `ip` to the instruction and a pointer `fnaddr` to the start of the function containing it.
Returns `true` if successful, filling in `line` with line on which the instruction occured and `filename` with a pointer to a fixed-width string of to `namemax` characters holding the filename.
Fills up to `namemax` characters of the function's name into `name`.

Embedding Terra inside C code
=============================

Like Lua, Terra is designed to be embedded into existing code.
The C API for Terra serves as the entry-point for running Terra-Lua programs.
In fact, the `terra` executable and REPL are just clients of the C API. The Terra C API extends [Lua's API](http://www.lua.org/manual/5.1/manual.html#3) with a set of Terra-specific functions. A client first creates a `lua_State` object and then calls `terra_init` on it to initialize the Terra extensions. Terra provides equivalents to the `lua_load` set of functions (e.g. `terra_loadfile`), which treat the input as Terra-Lua code.

---
    int terra_init(lua_State * L);

Initializes the internal Terra state for the `lua_State` `L`. `L` must be an already initialized `lua_State`.

---

    typedef struct { /* default values are 0 */
        int verbose; /* Sets verbosity of debugging output.
                        Valid values are 0 (no debug output)
                        to 2 (very verbose). */
        int debug;   /* Turns on debug information in Terra compiler.
                        Enables base pointers and line number
                        information in stack traces. */
    } terra_Options;
    int terra_initwithoptions(lua_State * L, terra_Options * options);

Initializes the internal Terra state for the `lua_State` `L`. `L` must be an already initialized `lua_State`. `terra_Options` holds additional configuration options.

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

    terra_dofile(L, file)

Loads and runs the file `file`. Equivalent to

    (terra_loadfile(L, fn) || lua_pcall(L, 0, LUA_MULTRET, 0))

---

    terra_dostring(L, s)

Loads and runs the string `s`. Equivalent to

    (terra_loadstring(L, s) || lua_pcall(L, 0, LUA_MULTRET, 0))

Embedding New Languages Inside Lua
=================================

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
The parser will then call `require` on the string literal to load the language extension file.
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

For names, strings, and numbers this is the specific value (e.g. `3.3`). Numbers are represented as Lua numbers when they would fit (floating point or 32-bit integers) and '[u]int64_t' cdata types for 64-bit integers.

---

    token.valuetype

For numbers this is the Terra type of the literal parsed. `3` will have type `int`, `3.3` is `double`, `3.f` is `float`, `3ULL` is `uint64`, `3LL` is `int64`, and `3U` is `uint`.

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


---

    lexer:luastats()

Parses a set of Lua statement from the token stream until it reaches an end of block keyword (`end`, `else`, `elseif`, etc.). This can be used to help build domain specific languages that are supersets of Lua without having to reimplement all of the Lua parser.

---

    lexer:terraexpr()

Parses a single Terra expression from the token stream. This can be used to help build domain specific languages that are supersets of Terra without having to reimplement all of the Terra parser.

---

    lexer:terrastats()

Parses a set of Terra statement from the token stream until it reaches an end of block keyword (`end`, `else`, `elseif`, etc.). This can be used to help build domain specific languages that are supersets of Terra without having to reimplement all of the Terra parser.

Intermediate Representations with Abstract Syntax Description Language
======================================================================

[Abstract Syntax Description Language (ASDL)](https://www.usenix.org/legacy/publications/library/proceedings/dsl97/full_papers/wang/wang.pdf) is a way of describing compiler intermediate representations (IR) and other tree- or graph-based data structures in a concise way. It is similar in many ways to algebraic data types, but offers a consistent cross-language specification. ASDL is used in the Python compiler to describe its grammer, and is also used internally in Terra to represent Terra code.

We provide a Lua library for parsing ASDL specifications that can be used to implement IR and other data-structures that are useful when building domain-specific languages. It allows you to parse ASDL specifications to create a set of Lua classes (actually specially defined meta-tables) for building IR. The library automatically sets up the classes with constructors for building the IR, and additional methods can be added to the classes using standard Lua method definitions. 

---

    local asdl = require 'asdl'
   
The ASDL package comes with Terra.

---

    context = asdl.NewContext()

ASDL classes are defined inside a context. Different contexts do not share anything. Each class inside a context must have a unique name.

---


Creating ASDL Classes
---------------------

    local Types = asdl.NewContext()

    Types:Define [[

       # define a simple record type with two members
       Real = (number mantissa, number exp)
       #       ^~~~ field type         ^~~~~ field name

       # define a tagged union (aka a variant, descriminated union, sum type)
       # with several optional data types.
       # Here the type Stm has three sub-types
       Stm = Compound(Stm head, Stm next)
           | Assign(string lval, Exp rval)
       # '*' specifies that a field is a List object 
       # '?' marks a field optional (may be nil as well as the type)
           | Print(Exp* args, string? format)
    


       Exp = Id(string name)
           | Num(number v)
           | Op(Exp lhs, BinOp op, Exp rhs)

       # Omitting () on a tagged union creates a singleton value
       BinOp = Plus | Minus
    ]]

Types can be Lua primitives returned by `type(v)` (e.g. number table function string boolean), other ASDL types, or checked with arbitrary functions registered with `context:Extern`.

---


External types can be used by registering a name for the type and a function that returns true for objects of that type:

    Types:Extern("File",function(v) 
       return io.type(obj) == "file" 
    end)
    
---


   
Using ASDL Classes
------------------

    local exp = Types.Num(1)
    local assign = Types.Assign("x",exp)
    local real = Types.Real(3,4)

    local List = require 'terralist'
    local p = Types.Print(List {exp})

Values are created by calling the Class as function. Arguments are checked to be the correct type on construction. Helpful warnings are emitted when the types are wrong.

Fields are initialized by the constructor:

    print(exp.v) -- 1

By default classes have a string representation

    print(assign) -- Assign(lval = x,rval = Num(v = 1))
   
And you can check for membership using :isclassof

    assert(Types.Assign:isclassof(assign))
    assert(Types.Stm:isclassof(assign))
    assert(Types.Exp:isclassof(assign) == false)
   
Singletons are not classes but values:
   
    assert(Types.BinOp:isclassof(Types.Plus))
   
Classes are the metatables of their values and have `Class.__index = Class`
   
    assert(getmetatable(assign) == Types.Assign)
   
Tagged unions have a string field .kind that identifies which variant in the union the value is

    assert(assign.kind == "Assign")
   
   
---


Adding Methods To ASDL Classes
---------------------------------

You can define additional methods on the classes to add additional behavior

    function Types.Id:eval(env)
      return env[self.name]
    end
    function Types.Num:eval(env)
      return self.v
    end
    function Types.Op:eval(env)
      local op = self.op
      local lhs = self.lhs:eval(env)    
      local rhs = self.rhs:eval(env)
      if op.kind == "Plus" then
         return lhs + rhs
      elseif op.kind == "Minus" then
         return lhs - rhs
      end
    end

    local s = Types.Op(Types.Num(1),Types.Plus,Types.Num(2))
    assert(s:eval({}) == 3)

You can also define methods on the super classes which will be defined for sub-classes as well:

    function Types.Stm:foo()
      print("foo")
    end

    assign:foo()
   
WARNING: To keep the metatable structure simple, this is not implemented with chained tables Instead definitions on the superclass also copy their method to the subclass because of this design YOU MUST DEFINE PARENT METHODS BEFORE CHILD METHODS. Otherwise, the parent method will clobber the child.
 
IF YOU NEED TO OVERRIDE AN ALREADY DEFINE METHOD LIKE __tostring SET IT TO NILFIRST IN THE SUPERCLASS:

    Types.Stm.__tostring = nil
    function Types.Stm:__tostring()
      return "<Stm>"
    end

Namespaces
----------

As an extension to ASDL, you can use the module keyword to define a namespace. This helps when you have many different kinds of Exp and Type in your compiler.

    Types:Define [[
       module Foo {
          Bar = (number a)
          Baz = (Bar b)
       }
       Outside = (Foo.Baz x)
    ]]
    local a = Types.Foo.Bar(3)

Unique
------
Another extension allows you to mark any concrete type 'unique'. Unique types are
memoized on construction so that if constructed with the same arguments (under Lua equality), the same Lua
object is returned again. This works for types containing Lists (*) and Options (?) as well

    Types:Define [[
       module U {
          Exp = Id(string name) unique
              | Num(number v) unique
       }
   
    ]]
    assert(Types.U.Id("foo") == Types.U.Id("foo"))


Getting Started with Terra
==========================

_Zach DeVito <zdevito@stanford.edu>_

Terra is a new low-level system programming language that is designed to interoperate seamlessly with the Lua programming language. It is also backwards compatible with (and embeddable in) existing C code. Like C, Terra is a monomorphic, statically-typed, compiled language with manual memory management. But unlike C, it is designed to make interaction with Lua easy. Terra code shares Lua's syntax and control-flow constructs. It is easy to call Lua functions from Terra (or Terra functions from Lua). 

Furthermore, you can use Lua to meta-program Terra code.  The Lua meta-program handles details like conditional compilation, namespaces, and templating in Terra code that are normally special constructs in low-level languages.  This coupling additionally enables more powerful features like function specialization, lisp-style macros, and manually controlled JIT compilation. Since Terra's compiler is also available at runtime, it makes it for libraries or embedded languages to generate low-level code dynamically.

This guide serves as an introduction for programming in Terra. A general understanding of the Lua language is very helpful, but not strictly required.

Rationale
---------

Programming languages make fundamental tradeoffs between productivity and performance.  While JIT compilers can make dynamic languages like Python, Javascript, or Lua run more efficiently, they rarely match the performance of a low-level language like C, and can be difficult to use in a embedded/power-constrained context. On the flip side, C can be a more difficult and error-prone programming environment.

Languages like Go, C++, D, Scala, Java, or, Cython try to strike a balance beween these constraints. But this can increase the total complexity of the language, restrict certain behaviors, and can create weird interactions between features.

An alternative approach popular in the game programming community is to use two programming languages. A performance language (typically C/C++) for rendering and simulation, and a dynamic language (often Lua) for scripting and configuration.  

Though Lua was designed from first principles to work with C, C was not designed to interoperate easily with dynamic languages.  Terra fills this gap.  It is a low-level language designed to work with Lua. In contrast to Lua, Terra is statically typed, monomorphic, and manually manages memory.  However, unlike C, Terra is specifically designed to make interaction with Lua seamless.  The result is a pair of languages that are individually simple, but combine in powerful ways.

Installation
------------

This section will walk you through installing Terra's dependencies, and building the library. Terra is being developed on Mac OS X. It should also run on Linux, but it has not been tested there yet, so there will be small issues like missing headers, and different locations for some libraries.

Terra uses LLVM 3.1, Clang 3.1 (the C/C++ frontend for LLVM), and LuaJIT 2.0 -- a tracing-JIT for Lua code.  Terra will download and compile LuaJIT for you, but you will need to install Clang and LLVM. The easiest way to do this is to the download the _Clang Binaries_ (which also include LLVM binaries) from the
[LLVM download](http://llvm.org/releases/download.html) page.

Unzip the tar ball and then copy it into `/usr/local`:

    $ tar -xf clang+llvm-3.1-x86_64-apple-darwin11.tar.gz
    $ cp -r clang+llvm-3.1-x86_64-apple-darwin11/ /usr/local

Clang should now report being version 3.1:

    $ clang --version
    clang version 3.1 (branches/release_31)
    Target: x86_64-apple-darwin10.8.0
    Thread model: posix

Type make in the `terra` directory to download LuaJIT and build Terra:

    $ make

Running Terra
-------------

Similar to the design of Lua, Terra can be used as a standalone interpreter/read-eval-print-loop (REPL) and also as a library embedded in a C program `libterra.a`. This design makes it easy to integrate with existing projects.

To run the REPL:
    
    $ ./terra
    
    Terra -- A low-level counterpart to Lua
    
    Stanford University
    zdevito@stanford.edu
    
    > 

Terra's REPL behaves similar to Lua's REPL. If you are familiar with other languages like Python, the one major difference is that expressions must be prefixed with `return` or `=` if you want to get their value:

    > 3        --ERROR! it is expecting a statement
    stdin:1: unexpected symbol near 3
    > return 3 -- OK!
    3
    > = 3      -- syntax sugar in the REPL for 'return 3'
    3
    
You can also run it on already written files:

    $ ./terra tests/hello.t
    hello, world
    
Terra can also be used as a library from C by linking against `libterra.a`. The interface is very similar that of the [Lua interpreter](http://queue.acm.org/detail.cfm?id=1983083).
A simple example initializes Terra and then runs code from the file specified in each argument:

    #include <stdio.h>
    #include "terra.h"
    
    int main(int argc, char ** argv) {
        lua_State * L = luaL_newstate(); //create a plain lua state
        luaL_openlibs(L);                //initialize its libraries
        terra_init(L);                   //initialize the terra state in lua
        for(int i = 1; i < argc; i++)
            if(terra_dofile(L,argv[i]))  //run the terra code in each file
                exit(1);
        return 0;
    }

In addition to these modes, Terra code can be compiled to `.o` files which can be linked into an executable, or even compiled directly to an executable.

For the remainder of the guide, we will assume that you are using the `terra` executable to run scripts. A bunch of example scripts can be found in the `tests/` directory.

Hello, World
------------

Hello world is simple:

    print("hello, world")

This program is actually a completely valid Lua program as well. In fact, the top-level declarations in a Terra source code file are always run as normal Lua code! This top-level Lua layer handles the details like conditional compilation, namespaces, and templating of terra code. We'll see later that it additionally allows for more powerful meta-programming features such as function specialization, lisp-style macros, and code quotations.

To actually begin writing Terra code, we introduce a Terra function with the keyword `terra`:

    terra addone(a : int)
        return a + 1
    end

    print(addone(2)) --this outputs: 3
    
Unlike Lua, arguments to Terra functions are explicitly typed. Terra uses a simple static type propagation to infer the return type of the `addone` function. You can also explicitly specify it:

    terra addone(a : int) : int
    
The last line of the example invokes the Terra function from the top level context. This is an example of the interaction between Terra and Lua.
Terra code is JIT compiled to machine code when it is first _needed_. In this example, this occurs when `addone` is called. In general, functions are _needed_ when then are called, or when they are referred to by other functions that are being compiled.

More information on the interface between Terra and Lua can be found in [Lua-Terra interaction](#interaction).

We can also print "hello, world" directly from Terra code like so:

    local c = terralib.includec("stdio.h")
    
    terra main()
        c.printf("hello, world\n")
    end
    
    main()
    
The function `terralib.includec` is a Lua function that invokes Terra's backward compatibility layer to import C code in `stdio.h` into the Lua table `c`. Terra functions can then directly call the C functions. Since both clang (our C frontend) and Terra target the LLVM intermediate representation, there is no additional overhead in calling a C function. Terra can even inline across these calls if the source of the C function is available!

The `local` keyword is a Lua construct. It introduces a locally scoped Lua variable named `c`. If omitted it would create a globally scoped variable.

If you want to avoid the overhead of compiling code at runtime, you can also compile code ahead of time and save it in a `.o`, or compile a stand-alone native executable.
We can instruct the Terra compiler to save an object file or executable:

    -- save a .o file you can link to normal C code:
    terralib.saveobj("hello.o",{ main = main })
    
    -- save a native executable
    terralib.saveobj("hello", { main = main }) 
    
The second argument is a table of functions to save in the object file and may include more than one function. The implementation of `saveobj` is still very primitive. It currently will not run initializers for global variables, or correctly save Terra functions that invoke Lua functions. This interface will become more robust over time.

Variables and Assignments
-------------------------

Variables in Terra code are introduced with the `var` keyword:
    
    terra myfn()
        var a : int = 3
        var b : double
    end

Unlike Lua, all Terra variables must be declared.  Initializers are optional. `b`'s value above is undefined until it is assigned. If an initializer is specified, then Terra can infer the variables type automatically:

    terra myfn()
        var a = 3.0 --a will have type double
    end

You can have multiple declarations on one line:

    terra myfn()
        var a : int, b : double = 3, 4.5
        var c : double, d       = 3, 4.5
    end

Lua and Terra are both whitespace invariant. However, there is no need for semicolons between statements. The above statement is equivalent to:

    terra myfn()
        var a : int, b : double = 3, 4.5 var c : double, d = 3, 4.5
    end

If you want to put a semicolon in for clarity you can:

    terra myfn()
        var a : int, b : double = 3, 4.5; var c : double, d = 3, 4.5
    end


Assignments have a similar form:

    terra myfn()
        var a,b = 3.0, 4.5
        a,b = b,a 
        -- a has value 4.5, b has value 3.0 
    end

As in Lua, the right-hand size is executed before the assignments are performed, so the above example will swap the values of the two variables.

Variables can be declared outside `terra` functions as well:

    var a = 3.0
    terra myfn()
        return a
    end
    
This makes `a` a _global_ variable that is visible to multiple Terra functions.

Variables in Terra are always lexically scoped. The statement `do <stmts> end` introduces a new level of scoping (for the remainder of this guide, the enclosing `terra` declaration will be omitted when it is clear we are talking about Terra code):
    
    var a = 3.0
    do
        var a = 4.0
    end
    -- a has value 3.0 now

Control Flow
------------

Terra's control flow is almost identical to Lua except for the behavior of `for` loops.

### If Statements ###

    if a or b and not c then
        c.printf("then\n")
    elseif c then
        c.printf("elseif\n")
    else
        c.printf("else\n")
    end

### Loops ###

    var a = 0
    while a < 10 do
        c.printf("loop\n")
        a = a + 1
    end

    repeat
        a = a - 1
        c.printf("loop2\n")
    until a == 0
    
    while a < 10 do
        if a == 8 then
            break
        end
        a = a + 1
    end

Terra also includes `for` loop. This example counts from 0 up to but not including 10:
    
    for i = 0,10 do
        c.printf("%d\n",i)
    end
    
This is different from Lua's behavior (which is inclusive of 10) since Terra uses 0-based indexing and pointer arithmetic in contrast with Lua's 1-based indexing. 

Lua also has a `for` loop that operates using iterators. This is not yet implemented (NYI) in Terra, but a version will be added eventually.

The loop may also specify an option step parameter:

    for i = 0,10,2 do
        c.printf("%d\n",i) --0, 2, 4, ...
    end
    
### Gotos ###

Terra includes goto statements. Use them wisely. They are included since they can be useful when generating code for embedded languages.

    ::loop::
    c.printf("y\n")
    goto loop

Functions Revisited
-------------------

We've already seen some simple function definitions. In addition to taking multiple parameters, functions in Terra (and Lua) can return multiple values:

    terra sort2(a : int, b : int, c : int) : {int,int} --the return type is optional
        if a < b then   
            return a, b
        else
            return b, a
        end
    end
    
    terra doit()
        var a,b = sort2(4,3)
        --now a == 4, b == 3
    end
    doit()
   
As mentioned previously, compilation occurs when functions are first _needed_. In this example, when `doit()` is called, both `doit()` and `sort2` are compiled because `doit` refers to `sort2`. 

### Mutual Recursion ###

Symbols such as variables and types are resolved and _compilation_ time. This makes it possible to define mutually recursive functions without first declaring them:

    terra iseven(n : uint32)
        if n == 0 then
            return true
        else
            return isodd(n - 1)
        end
    end
     
    terra isodd(n : uint32)
        if n == 0 then
            return false
        else
            return iseven(n - 1)
        end
    end

    print(iseven(3)) -- OK! isodd has been defined
    
When `iseven` is compiled on the last line, `isodd` has been defined. 

### Terra Functions Are Lua Objects ###

So far, we have been treating `terra` functions as special constructs in the top-level Lua code. In reality, Terra functions are actually just Lua values. In fact, the code:
    
    terra foo()
    end

Is just syntax sugar for:

    foo = terra()
        --this is an anonymous terra function
    end
    
The symbol `foo` is just a Lua _variable_ whose _value_ is a Terra function. Lua is Terra's meta-language, and you can use it to perform reflection on Terra functions. For instance, you can ask for the function's type:

    terra add1(a : double)
        return a + 1.0
    end
    
    --this is Lua code:
    > print(add1:gettype())
    "{double} -> {double}"

You can also force a function to be compiled:
    
    add1:compile()

Or look at the functions internal abstract syntax tree:

    > add1.untypedtree:printraw()
    function
      parameters: 
        1: entry
             linenumber: 1
             name: a
             type: type
                     linenumber: 1
                     expression: function: 0x00065930
      linenumber: 1
      is_varargs: false
      filename: =stdin
      body: block
              linenumber: 1
              statements: 
                1: return
                     linenumber: 1
                     expressions: 
                       1: operator
                            linenumber: 1
                            operands: 
                              1: var
                                   linenumber: 1
                                   name: a
                              2: literal
                                   value: 1
                                   linenumber: 1
                                   type: double
                            operator: + (enum 0)

### Symbol Resolution ###

When the Terra compiler looks up a symbol like `add1` it first looks in the local environment of the `terra` function. If it doesn't find the symbol, then it simply continues the search in the enclosing (Lua) environment. If the compiler resolves the symbol to a Lua value, then it converts it to a Terra value where possible. Let's look at a few examples:

    local N = 4
    terra powN(a : double)
        var r = 1
        for i = 0, N do
            r = r * a
        end
        return r
    end

Here `N` is a Lua value of type `number`. When `powN` is compiled, the value of `N` is looked up in the Lua environment and inlined into the function as a double literal. 

Since `N` is resolved at _compile_ time, changing `N` after `powN` is compiled will not change the behavior of `powN`.  For this reason, it is strongly recommended that you don't change the value of Lua variables that appear in Terra code once they are initialized.

Of course, a single power function is boring. Instead we might want to create specialized versions of 10 power functions:
    
    local math = {}
    for i = 1,10 do
        math["pow"..tostring(i)] = terra(a : double)
            var r = 1
            for i = 0, i do
                r = r * a
            end
            return r
        end
    end
    
    math.pow1(2) -- 2
    math.pow2(2) -- 4
    math.pow3(2) -- 8
    
Here we use the fact that in Lua the select operator on tables (`a.b`) is equivalent to looking up the value in table (`a["b"]`).

You can call these power functions from a Terra function:

    terra doit()
        return math.pow3(3) 
    end
    
Let's examine what is happens when this function is compiled. The Terra compiler will resolve the `math` symbol to the Lua table holding the power functions. It will then see the select operator (`math.pow3`). Because `math` is a Lua table, the Terra compiler will perform this select operator at compile time, and resolve `math.pow3` to the third Terra function constructed inside the loop.  It will then insert a direct call to that function inside `doit`. This behavior is a form of _partial execution_. In general, Terra will resolve any chain of select operations `a.b.c.d` on Lua tables at compile time. This behavior enables Terra to use Lua tables to organize code into different namespaces. There is no need for a Terra-specific namespace mechanism!

Recall how we can include C files:
    
    local c = terralib.includec("stdio.h")

`terralib.includec` is just a normal Lua function. It builds a Lua table that contains references to the Terra functions that represent calls to (in this case) the standard library functions. We can iterate through the table as well:

    for k,v in pairs(c) do
        print(k)
    end
    --output:
    fseek
    gets
    printf
    puts
    FILE
    ...
    
### Scoping ###
Additionally, you may want to declare a Terra function as a _locally_ scoped Lua variable. You can use the `local` keyword:

    local terra foo()
    end
    
Which is just sugar for:

    local foo; foo = terra()
    end()

Types and Operators
-------------------
Terra's type system closely resembles the type system of C, with a few differences that make it interoperate better with the Lua language.

### Primitive Types ###
We've already seen some basic Terra types like `int` or `double`. Terra has the usual set of basic types:

* Integers: `int` `int8` `int16` `int32` `int64`
* Unsigned integers: `uint` `uint8` `uint16` `uint32` `uint64`
* Boolean: `bool`
* Floating Point: `float` `double`

Integers are explicitly sized except for `int` and `uint` which should only be used when the particular size is not important. Most implicit conversions from C are also valid in Terra. The one major exception is the `bool` type. Unlike C, all control-flow explicitly requires a `bool` and integers are not explicitly convertible to `bool`.

    if 3 then end -- ERROR 3 is not bool
    if 3 == 0 then end -- OK! 3 == 0 is bool

You can force the conversion from `int` to `bool` using an explicit cast:

    var a : bool = (3):as(bool)

The `a:b(c)` syntax is a method invocation syntax borrowed from Lua that will be discussed later.

Primitive types have the standard operators defined:

* Arithmetic: `- + * / %`
* Comparison: `< <= > >= == ~=`
* Logical: `and or not`
* Bitwise: `and or not ^ << >>`

These behave the same C except for the logical operators, which are overloaded based on the type of the operators:

    true and false --Lazily evaluated logical and
    1 and 3        --Eagerly evaluated bitwise and
    
### Pointers ###

Pointers behave similarly to C, including pointer arithmetic. The syntax is slightly different to work with Lua's grammar:
    
    var a : int = 1
    var pa : &int = &a
    @a = 4
    var b = @a
    
You can read `&int` as a value holding the _address_ of an `int`, and `@a` as the value _at_ address `a`. To get a pointer to heap-allocated memory you can use stdlib's `malloc`:

    c = terralib.includec("stdlib.h")
    terra doit()
        var a = c.malloc(sizeof(int) * 2):as(&int)
        @a,@(a+1) = 1,2
    end

Indexing operators also work on pointers:

    a[3] --syntax sugar for @(a + 3)
    
Pointers can be explicitly cast to integers that are large enough to hold them without loss of precision. The `intptr` is the smallest integer that can hold a pointer. The `ptrdiff` type is the signed integer type that results from subtracting two pointers.

### Arrays ###

You can construct statically sized arrays as well:

    var a : int[4]
    a[0],a[1],a[2],a[3] = 0,1,2,3
    
In constrast to Lua, Terra uses 0-based indexing since everything is based on offsets. `&int[3]` is a pointer to an array of length 3. `(&int)[3]` is an array of three pointers to integers.

### Vectors (NYI) ###

Vectors are like arrays, but also allow you to perform vector-wide operations:

    terra diffuse(L : vec(float,3), V : vec(float,3), N : vec(float,3))
        var H = (L + V) / size(L + V)
        return dot(H,N)
    end

They serve as an abstraction of the SIMD instructions (like Intel's SSE or Arm's NEON ISAs), allowing you to write vectorized code.

### Structs ###

You can create aggregate types using the `struct` keyword. Structs must be declared outside of Terra code:

    struct Complex { real : float; imag : float; }
    terra doit()
        var c : Complex
        c.real = 4
        c.imag = 5
    end
    
Unlike C, you can use the select operator `a.b` on pointers. This has the effect of dereferencing the pointer once and then applying the select operator (similar to the `->` operator in C):

    terra doit(c : Complex)
        var pc = &c
        return pc.real --sugar for (@pc).real
    end
    
Like functions, symbols in struct definitions are resolved at compile time, allowing for recursive structural types:

    struct LinkedList { value : int; next : &LinkedList; } 
    
Terra has no explicit union type. Instead, you can declare that you want two or more elements of the struct to share the same memory:

    struct MyStruct { 
        a : int; --unique memory
        union { 
            b : double;  --memory for b and c overlap
            c : int;
        } 
    }
    
### Anonymous Structs ###

In Terra you can also create struct types that have no name:

    var a : struct { real : float, imag : float } 
    
These structs are similar to the anonymous structs found in languages like C-sharp.
They may also contain unnamed members:

    var a : struct { float, float }
    
Unnamed members will be given the names `_0`, `_1`, ... `_N`:

    a._0 + a._1
    
You can use a struct constructor syntax to quickly generate values that have an anonymous struct type:

    var a = { 1,2,3,4 } --has type struct {int,int,int,int}
    var b = { a = 3.0, b = 3 } --has type struct { a : double, b : int }
    
Terra allows you to implicitly convert any anonymous struct to a named struct that has a superset of its fields.
    
    struct Complex { real : float, imag : float}
    var a : Complex = { real = 3, imag = 1 }
    
If the anonymous struct has unnamed members, then it they will be used to initialize the fields of the named struct in order:
    
    var b : Complex = {1, 2}
    
Anonymous structs can also be implicitly converted to array and vector types:

    var a : int[4] = {1,2,3,4}
    var b : vec(int,4) = {1,2,3,4}
    
Since constructors like `{1,2}` are first-class values, they can appear anywhere a Terra expression can appear. This is in contrast to struct initializers in C, which can only appear in a struct declaration.

### Function Pointers ###

Terra also allows for function pointers:

    terra add(a : int, b : int) return a + b end
    terra sub(a : int, b : int) return a - b end
    terra doit(usesub : bool, v : int)
        var a : {int,int} -> int
        if usesub then
            a = sub
        else
            a = add
        end
        return a(v,v)
    end
    
Terra does not have a `void` type. Instead, functions may return zero arguments:

    terra zerorets() : {}
    end
    print(zerorets:gettype()) -- "{} -> {}"
    
### Terra Types as Lua Values ###

Earlier we saw how Terra functions were actually Lua values. The same is true of Terra's types. In fact, all type expressions -- expressions following a ':' in declarations -- are simply Lua expressions that resolve to a type. Any valid Lua expression (e.g. function calls) can appear as a type as long as it evaluates to a valid Terra type:

    function Complex(typ)
        return struct { real : typ, imag : typ }
    end
    
    terra doit()
        var intcomplex : Complex(int) = {1,2}
        var dblcomplex : Complex(double) = { 1.0, 2.0 }
    end
        
Since types are just Lua expressions they can occur outside of Terra code. Here we make a type alias for a pointer to an `int` that can be used in Terra code:

    local ptrint = &int
    
    terra doit(a : int)
        var : ptrint = &int
    end
    
In fact many primitive types are just defined as Lua variables:

    _G["int"] = int32
    _G["uint"] = uint32
    _G["long"] = int64
    _G["intptr"] = uint64 --these may be architecture specific
    _G["ptrdiff"] = int64

Yes, you could theoretically change these aliases. You could also dereference a null pointer. We don't recommend doing either.

Making types Lua objects enables powerful behaviors such as templating. Here we create a template that returns a constructor for a dynamically sized array:

    function Array(typ)
        return terra(N : int)
            var r : &typ = c.malloc(sizeof(typ) * N):as(&typ)
            return r
        end
    end
    
    local NewIntArray = Array(int)
    
    terra doit(N : int)
        var my_int_array = NewIntArray(N)
        --use your new int array
    end
    
Literals
--------

Here are some example literals:

* `3` is an `int`
* `3.` is a `double`
* `3.f` is a `float`
* `3LL` is an `int64`
* `3ULL` is a `uint64`
* `"a string"` or `[[ a multi-line long string ]]` is an `int8*`
* `nil` is the null pointer for any pointer type
* `true` and `false` are `bool`


Expression Lists
----------------

In cases where multiple expressions can appear in a list, functions that return multiple will append all of their values to the list if they are the final member of the list.
This behavior occurs in declarations, assignments, return statements, and struct initializers.

Here are some examples (adapted from the Lua reference manual):

     f()                -- adjusted to 0 results
     g(f(), x)          -- f() is adjusted to 1 result
     g(x, f())          -- g gets x plus all results from f()
     a,b = f(), x       -- f() is adjusted to 1 result
     a,b,c = x, f()     -- f() is adjusted to 2 results
     a,b,c = f()        -- f() is adjusted to 3 results
     return f()         -- returns all results from f()
     return x,y,f()     -- returns x, y, and all results from f()
     {f()}              -- creates a struct all results from f()
     {f(), nil}         -- f() is adjusted to 1 result
     {(f())}            -- f adjusted to 1 result

Methods
-------

Unlike languages like C++ or Scala, Terra does not provide a built-in class system that includes advanced features like inheritance or sub-typing. Instead, Terra provides the _mechanisms_ for creating systems like these, and leaves it up to the user to choose to user or build such a system. One of the mechanisms Terra exposes is a method invocation syntax sugar similar to Lua's `:` operator.

In Lua, the statement:
    
    reciever:method(arg1,arg2)
    
is syntax sugar for:

    reciever.method(reciever,arg1,arg2)

The function `method` is looked up on the object `reciever` dynamically. In contrast, Terra looks up the function statically at compile time. Since the _value_ of the `reciever` expression is not know at compile time, it looks up the method on its _type_. 

In Terra, the statement:

    reciever:method(arg1,arg2)
    
where `reciever` has type `T` is syntax sugar for:

    T.methods.method(reciever,arg1,arg2)

`T.methods` is the _method table_ of type `T`. Terra allows you to add methods to the method tables of named structural types:

    struct Complex { real : double, imag : double }
    Complex.methods.add = terra(self : &Complex, rhs : Complex) : Complex
        return {self.real + rhs.real, self.imag + rhs.imag}
    end
    
    terra doit()
        var a : Complex, b : Complex = {1,1}, {2,1}
        var c = a:add(b)
        var ptra = &a
        var d = ptra:add(b) --also works
    end
    
The statement `a:add(b)` will normally desugar to `Complex.methods.add(a,b)`. Notice that `a` is a `Complex` but the `add` function expects a `&Complex`. When invoking methods, Terra will insert one implicit address-of or implicit dereference operator. In this case `a:add(b)` will desugar to `Complex.methods.add(&a,b)`. 

Additionally, if a method does not appear in the method table for type `&Type`, Terra will look for the method in the method table of `Type`. Combined with implicit address-of/derefernece, this allows a single method definition to work sensibly on both a value and a pointer to that value. Those familiar with the Go language will notice these rules are similar to Go's method resolution rules.

Though not currently implemented, Terra will also support _meta-methods_ similar to Lua's operators like `__add`, which will allow you to overload operators like `+` on Terra types, or specify custom type conversion rules.
    
Terra provides syntax sugar to make declaring methods simpler:

    terra Complex:add(rhs : Complex) ... end
    
is sugar for:

    Complex.methods.add = terra(self : &Complex, rhs : Complex) ... end

Lua-Terra Interaction
---------------------
<a id="interaction"></a>

We've already seen examples of Lua code calling Terra functions. In general, you can call a Terra function anywhere a normal Lua function would go. When passing arguments into a terra function from Lua they are converted into Terra types. The current rules for this are not completely stable. Right now they match the behavior of [LuaJIT's FFI interface](http://luajit.org/ext_ffi_semantics.html). Numbers are converted into doubles, tables into structs or arrays, Lua functions into function pointers, etc. Here are some examples:

    struct A { a : int, b : double }

    terra foo(a : A)
	    return a.a + a.b
    end
    
    assert( foo( {a = 1,b = 2.3} )== 3.3 )
    assert( foo( {1,2.3} ) == 3.3)
    assert( foo( {b = 1, a = 2.3} ) == 3 )

More examples are in `tests/luabridge*.t`.  

It is also possible to call terra functions from Lua. Again, the translation from Terra objects to Lua uses LuaJITs conversion rules. Primtive types like `double` will be converted to their respective Lua type, while aggregate and derived types will be boxed in a LuaJIT _CType_ that can be modified from Lua:

    function add1(a)
        a.real = a.real + 1
    end
    struct Complex { real : double, imag : double }
    terra doit()
        var a : Complex = {1,2}
        add1(&a)
        return a
    end
    a = doit()
    print(a.real,a.imag) -- 2    1
    print(type(a)) -- cdata
    
The file `tests/terralua.t` includes more examples. The file `tests/terraluamethod.t` also demonstrate using Lua functions inside the method table of a terra object.

Currently, Lua functions cannot return values to Terra functions. This will change in the future. If you need to get return a result from Lua, you can pass a pointer to where you want the result as an argument:

    function insert1(a)
        a[0] = 1
    end
    terra doit()
        var a : int
        insert1(&a)
        --a has value 1
    end

Macros
------

By default, when you call a Lua function from Terra code, it will execute at runtime, just like a normal Terra function. It is sometimes useful for the Lua function to execute at compile time instead. Calling the Lua function at compile-time is called a _macro_ since it behaves similarly to macros found in Lisp and other languages.  You can create macro using the function `macro` which takes a normal Lua function and returns a macro:

    local times2 = macro(function(ctx,tree,a)
        return `a + a
    end)
    
    terra doit()
        var a = times2(3)
        -- a == 6
    end

Unlike a normal function, which works on Terra values, the arguments to Terra macros are data structures representing the code (i.e the abstract syntax tree, or AST). The example above constructs the AST node representing the addition of the AST node `a` to itself. To do this, it uses the backtick operator to create a _code quotation_ (similar to `quote` int LISP, or [those of F#](http://msdn.microsoft.com/en-us/library/dd233212.aspx)).  It will construct the appropriate AST nodes to perform the addition. 

The first argument to every macro is the compilation context `ctx`. It can be used to report an error if the macro doesn't apply to the arguments given, and is needed in certain API calls used in macros. The second argument to every macro (`tree`) is the AST node in the code that represents the macro call. It is typically used as the location at which to report an error in a macro call. The following code will cause the compiler to emit an error referring to the macro call with given error message:

    ctx:reporterror(tree, "something in the macro went wrong")
    

The remaining arguments to the macro are the AST nodes of the arguments to the macro function.

Since macros take AST nodes rather than values, they have different behavior than function calls. For instance:
    
    var c = 0
    terra up()
        c = c + 1
        return c
    end
    
    terra doit()
        return times2(up()) --returns 1 + 2 == 3
    end
    
The example returns `3` because `up()` is evaluated twice

Some built-in operators are implemented as macros. For instance the `sizeof` operator just inserts a special AST node that will calculate the size of a type:

    sizeof = macro(function(ctx,tree,typ)
        return terra.newtree(tree,{ kind = terra.kinds.sizeof, oftype = typ:astype(ctx)})
    end) 
    
`terra.newtree` creates a new node in this AST. For the most part, macros can rely on code quotations to generate AST nodes, and only need to fallback to explicitly creating AST nodes in special cases. 

If you want to take an argument passed to a macro and convert it into a Terra type you can call its `astype` method, as seen in the previous example. `typ:astype(ctx)` takes the AST `typ` and evaluates it as a Terra type. 

Macros can also be used to create useful patterns like a C++ style new operator:

    new = macro(function(ctx,tree,typquote)
        local typ = typquote:astype(ctx)
        return `c.malloc(sizeof(typ)):as(&typ)
    end)
    
    terra doit()
        var a = new(int)
    end
    
If you want to generate statements (not expressions) you can use the long-form `quote` operator, which creates an AST for multiple statements
    
    iamclean = macro(function(ctx,tree,arg)
        quote
            var a = 3
            c.printf("%d %d\n",a,arg)
        end
    end)
    
    terra doit()
        var a = 4
        iamclean(a)
    end
    -- prints 3 4

The above code will print `3 4` not `3 3` even though `a` is passed into a macro which defines another `a`.  This occurs because Terra code quotations are _hygienic_. Variables obey lexical scoping rules.

More Information
----------------

This concludes the getting started guide. The best place to look for more examples of Terra features is the `tests/` directory, which contains the set of up-to-date languages tests for the implementation. If you are interested in the implementation, you can also look at the source code.  The compiler is implemented as a mixture of Lua code and C/C++. Passing the `-v` flag to the interpreter will cause it to give verbose debugging output. 

* `lparser.cpp` is an extended version of the Lua parser that implements Terra parsing. It parsers Terra code, building the Terra AST for terra code, while passing the remaining code to Lua (use `-v` to see what is passed to Lua).

* `terralib.lua` contains the Lua infrastructure for the Terra compiler, which manages the Terra objects like functions and types. It also performs type-checking on Terra code before compilation.

* `tcompiler.cpp` contains the LLVM-based compiler that translates the Terra AST into LLVM IR that can then be JIT compiled to native code.

* `tcwrapper.cpp` contains the Clang-based infrastructure for including C code.

* `terra.cpp` contains the implementation of Terra API functions like `terra_init`

* `main.cpp` contains the Terra REPL (based on the Lua REPL).

    
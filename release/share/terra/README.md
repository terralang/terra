Getting Started with Terra
==========================

_Zach DeVito_ (zdevito at cs dot stanford dot edu)

[terralang.org](http://terralang.org)
[![Build Status](https://travis-ci.org/zdevito/terra.svg?branch=develop)](https://travis-ci.org/zdevito/terra)
[![Build Status](https://ci.appveyor.com/api/projects/status/github/zdevito/terra?branch=master&svg=true)](https://ci.appveyor.com/project/zdevito/terra/branch/master)

Terra is a new low-level system programming language that is designed to interoperate seamlessly with the Lua programming language. It is also backwards compatible with (and embeddable in) existing C code. Like C, Terra is a monomorphic, statically-typed, compiled language with manual memory management. But unlike C, it is designed to make interaction with Lua easy. Terra code shares Lua's syntax and control-flow constructs. It is easy to call Lua functions from Terra (or Terra functions from Lua).

Furthermore, you can use Lua to meta-program Terra code. The Lua meta-program handles details like conditional compilation, namespaces, and templating in Terra code that are normally special constructs in low-level languages. This coupling additionally enables more powerful features like function specialization, lisp-style macros, and manually controlled JIT compilation. Since Terra's compiler is also available at runtime, it makes it easy for libraries or embedded languages to generate low-level code dynamically.

This guide serves as an introduction for programming in Terra. A general understanding of the Lua language is very helpful, but not strictly required.

Installing Terra
================

Terra currently runs Mac OS X, Linux, and 64-bit Windows. Binary releases for popular versions of these systems are available [online](https://github.com/zdevito/terra/releases), and we recommend you use them if possible because building Terra requires a working install of LLVM and Clang, which can be difficult to get working.

Running Terra
=============

Similar to the design of Lua, Terra can be used as a standalone executable/read-eval-print-loop (REPL) and also as a library embedded in a C program. This design makes it easy to integrate with existing projects.

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

Terra can also be used as a library from C by linking against `libterra.a` (windows:  `terra.dll`). The interface is very similar that of the [Lua interpreter](http://queue.acm.org/detail.cfm?id=1983083).
A simple example initializes Terra and then runs code from the file specified in each argument:

    //simple.cpp
    #include <stdio.h>
    #include "terra.h"

    int main(int argc, char ** argv) {
        lua_State * L = luaL_newstate(); //create a plain lua state
        luaL_openlibs(L);                //initialize its libraries
        //initialize the terra state in lua
        terra_init(L);
        for(int i = 1; i < argc; i++)
        	//run the terra code in each file
            if(terra_dofile(L,argv[i]))  
                return 1; //error
        return 0;
    }

This program can then be compiled by linking against the Terra library

    # Linux
    c++ simple.cpp -o simple -I<path-to-terra-folder>/terra/include \
    -L<path-to-terra-folder>/lib -lterra -ldl -pthread

    # OSX
    c++ simple.cpp -o simple -I<path-to-terra-folder>/terra/include \
    -L<path-to-terra-folder>/lib -lterra \
    -pagezero_size 10000 -image_base 100000000

Note the extra `pagezero_size` and `image_base` arguments on OSX. These are necessary for LuaJIT to run on OSX.

In addition to these modes, Terra code can be compiled to `.o` files which can be linked into an executable, or even compiled to an executable directly.

A bunch of example scripts can be found in the `tests/` directory. The `run` script in the directory will run all of these languages tests to ensure that Terra is built correctly.

## Running Terra's Test Suite ##

Terra includes test suite to make sure all of its functionality is working. To run it:

    cd tests
    ../terra run

Expect it to print a lot of junk out. At the end it will summarize the results:

    471 tests passed. 0 tests failed.

Building Terra
==============

If the binary releases are not appropriate, then you can also build Terra from source. Terra uses LLVM, Clang (the C/C++ frontend for LLVM), and LuaJIT 2.0.5 -- a tracing-JIT for Lua code.  Terra will download and compile LuaJIT for you, but you will need to install Clang and LLVM.

### Supported LLVM Versions ###

The current recommended version of LLVM is **6.0**. The following versions are also supported:

  * LLVM 3.4
  * LLVM 3.5 (tested in Travis, supports debug info, supports CUDA)
  * LLVM 3.6
  * LLVM 3.7
  * LLVM 3.8 (used frequently, tested in Travis, supports CUDA)
  * LLVM 3.9 (used frequently)
  * LLVM 5.0 (tested in Travis)
  * LLVM 6.0 (used frequently, tested in Travis, supports CUDA)

### Windows ###

For instructions on installing Terra in Windows see this [readme](https://github.com/zdevito/terra/blob/master/msvc/README.md). You will need a built copy of LLVM and Clang, as well as a copy of the LuaJIT sources.


### Linux/OSX ###

The easiest way to get a working LLVM/Clang install is to download the _Clang Binaries_ (which also include LLVM binaries) from the
[LLVM download](http://llvm.org/releases/download.html) page, and unzip this package.

Now get the Terra sources:

    git clone https://github.com/zdevito/terra

To point the Terra build to the version of LLVM and Clang you downloaded, create a new file `Makefile.inc` in the `terra` source directory that points to your LLVM install by including the following contents:

    LLVM_CONFIG = <path-to-llvm-install>/bin/llvm-config

Now run make in the `terra` directory to download LuaJIT and build Terra:

    $ make

If you do not create a `Makefile.inc`, the Makefile will look for the LLVM config script and Clang using these values:

    LLVM_CONFIG ?= $(shell which llvm-config-3.5 llvm-config | head -1)
    LLVM_PREFIX ?= $(shell $(LLVM_CONFIG) --prefix)
    CLANG ?= $(shell which clang-3.5 clang | head -1)
    CXX ?= $(CLANG)++
    CC  ?= $(CLANG)

If your installation has these files in a different place, you can override these defaults in the `Makefile.inc` that you created in the `terra` directory.

Hello, World
============

Hello world is simple:

    print("hello, world")

This program is actually a completely valid Lua program as well. The top-level declarations in a Terra source code file are always run as normal Lua code! This top-level Lua layer handles the details like conditional compilation, namespaces, and templating of terra code. We'll see later that it additionally allows for more powerful meta-programming features such as function specialization, and multi-stage programming.

To actually begin writing Terra code, we introduce a Terra function with the keyword `terra`:

    terra addone(a : int)
        return a + 1
    end

    print(addone(2)) --this outputs: 3

Unlike Lua, arguments to Terra functions are explicitly typed. Terra uses a simple static type propagation to infer the return type of the `addone` function. You can also explicitly specify it:

    terra addone(a : int) : int
    	return a + 1
    end

The last line of the example invokes the Terra function from the top-level context. This is an example of the interaction between Terra and Lua.
Terra code is JIT compiled to machine code when it is first _needed_. In this example, this occurs when `addone` is called. In general, functions are _needed_ when then are called, or when they are referred to by other functions that are being compiled.

More information on the interface between Terra and Lua can be found in [Lua-Terra interaction](#lua-terra-interaction).

We can also print "hello, world" directly from Terra code like so:

    local C = terralib.includec("stdio.h")

    terra main()
        C.printf("hello, world\n")
    end

    main()

The function `terralib.includec` is a Lua function that invokes Terra's backward compatibility layer to import C code in `stdio.h` into the Lua table `C`. Terra functions can then directly call the C functions. Since both clang (our C frontend) and Terra target the LLVM intermediate representation, there is no additional overhead in calling a C function. Terra can even inline across these calls if the source of the C function is available!

The `local` keyword is a Lua construct. It introduces a locally scoped Lua variable named `C`. If omitted it would create a globally scoped variable.

You can also compile code into a `.o`, or compile a stand-alone native executable.
We can instruct the Terra compiler to save an object file or executable:

    -- save a .o file you can link to normal C code:
    terralib.saveobj("hello.o",{ main = main })

    -- save a native executable
    terralib.saveobj("hello", { main = main })

The second argument is a table of functions to save in the object file and may include more than one function. The implementation of `saveobj` is still very primitive. For instance, it won't correctly save Terra functions that invoke Lua functions. This interface will become more robust over time.

Variables and Assignments
=========================

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

As in Lua, the right-hand side is executed before the assignments are performed, so the above example will swap the values of the two variables.

Variables can be declared outside `terra` functions as well:

    a = global(double,3.0)
    terra myfn()
        return a
    end

This makes `a` a _global_ variable that is visible to multiple Terra functions. The `global` function is part of Terra's Lua-based [API](api.html#global-variables). It initializes `a` to the _Lua_ value `3.0`.

Variables in Terra are always lexically scoped. The statement `do <stmts> end` introduces a new level of scoping (for the remainder of this guide, the enclosing `terra` declaration will be omitted when it is clear we are talking about Terra code):

    var a = 3.0
    do
        var a = 4.0
    end
    -- a has value 3.0 now

Control Flow
============

Terra's control flow is almost identical to Lua except for the behavior of `for` loops.

### If Statements ###

    if a or b and not c then
        C.printf("then\n")
    elseif c then
        C.printf("elseif\n")
    else
        C.printf("else\n")
    end

### Loops ###

    var a = 0
    while a < 10 do
        C.printf("loop\n")
        a = a + 1
    end

    repeat
        a = a - 1
        C.printf("loop2\n")
    until a == 0

    while a < 10 do
        if a == 8 then
            break
        end
        a = a + 1
    end

Terra also includes `for` loop. This example counts from 0 up to but not including 10:

    for i = 0,10 do
        C.printf("%d\n",i)
    end

This is different from Lua's behavior (which is inclusive of 10) since Terra uses 0-based indexing and pointer arithmetic in contrast with Lua's 1-based indexing. Ideally, Lua and Terra would use the same indexing rules. However, Terra code needs to frequently do pointer arithmetic and interface with C code both of which are cumbersome with 1-based indexing. Alternatively, patching Lua to make it 0-based would make the flavor of Lua bundled with Terra incompatible with existing Lua code.

Lua also has a `for` loop that operates using iterators. This is not yet implemented (NYI) in Terra, but a version will be added eventually.

The loop may also specify an option step parameter:

    for i = 0,10,2 do
        c.printf("%d\n",i) --0, 2, 4, ...
    end

### Gotos ###

Terra includes goto statements. Use them wisely. They are included since they can be useful when generating code for embedded languages.

    ::loop::
    C.printf("y\n")
    goto loop

Functions
=========

We have already seen some simple function definitions. In addition to taking multiple parameters, functions in Terra (and Lua) can return multiple values:

    terra sort2(a : int, b : int) : {int,int} --the return type is optional
        if a < b then   
            return a, b
        else
            return b, a
        end
    end

    terra doit()
        -- the multiple returns are returned
        -- in a 'tuple' of type {int,int}:
        var ab : {int,int} = sort2(4,3)
        -- tuples can be pattern matched,
        -- splitting them into seperate variables
        var a : int, b : int = sort2(4,3)
        --now a == 3, b == 4
    end
    doit()

Multiple return values are packed into a [tuples](getting-started.html#tuples-and-anonymous-functions), which can be pattern matched in assignments, splitting them apart into multiple variables.

As mentioned previously, compilation occurs when functions are first _needed_. In this example, when `doit()` is called, both `doit()` and `sort2` are compiled because `doit` refers to `sort2`.

### Mutual Recursion ###

Symbols such as variables and types are resolved when a function is defined.
The following example results in an error because `isodd` is not declared when `iseven` is defined:

    terra iseven(n : uint32)
        if n == 0 then
            return true
        else
        	-- ERROR! isodd has not been defined
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

You solve this by connecting the definitions with an `and`. This causes both `isodd` and `iseven` to be defined at the same time:

    terra iseven(n : uint32)
        if n == 0 then
            return true
        else
        	-- OK! isodd defined at the same time.
            return isodd(n - 1)
        end
    end
    and terra isodd(n : uint32)
        if n == 0 then
            return false
        else
            return iseven(n - 1)
        end
    end

Alternatively, you can declare a function before defining it:

	terra isodd
	terra iseven(n : uint32)
        ...
    end
    terra isodd(n : uint32)
       ...
    end

Note that unlike C++ it is not necessary to give the type of `isodd` in the declaration -- though symbols like `isodd` are resolved eagerly, we only perform type-checking when a function is compiled.

Like Lua function definitions, Terra function defintions can insert directly into Lua tables.

    local mytable = {}
    terra mytable.myfunction()
    	C.printf("myfunction in mytable\n")
    end

### Terra Functions Are Lua Objects ###

So far, we have been treating `terra` functions as special constructs in the top-level Lua code. In reality, Terra functions are actually just Lua values. In fact, the code:

    terra foo()
    end

Is just syntax sugar for\*:

    foo = terra()
        --this is an anonymous terra function
    end

The symbol `foo` is just a Lua _variable_ whose _value_ is a Terra function. Lua is Terra's meta-language, and you can use it to perform reflection on Terra functions. For instance, you can ask to see the disassembly for the function:

    terra add1(a : double)
        return a + a
    end

    --this is Lua code:
    > add1:disas()
	definition 	{double}->{double}

	define double @add111(double) {
	entry:
	  %1 = fadd double %0, %0
	  ret double %1
	}

	assembly for function at address 0xa2ef030
	0:		vaddsd	XMM0, XMM0, XMM0
	4:		ret

You can also force a function to be compiled:

    add1:compile()

Or look at a textual representation of the type-checked code

    > add1:printpretty()
	add1 = terra(a : double) : {double}
    	return a + a
	end

\* The actual syntax sugar is slightly more complicated to support function declarations.
See the [API reference](api.html#function) for the full behavior.

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
    N = 3
    --powN still computes the 4th power

Here `N` is a Lua value of type `number`. When `powN` is defined, the value of `N` is looked up in the Lua environment and inlined into the function as an `int` literal.

Since `N` is resolved when `powN` is defined, changing `N` after `powN` is compiled will not change the behavior of `powN`.  For this reason, it is strongly recommended that you don't change the value of Lua variables that appear in Terra code once they are initialized.

Of course, a single power function is boring. Instead we might want to create specialized versions of 10 power functions:

    local mymath = {}
    for i = 1,10 do
        mymath["pow"..tostring(i)] = terra(a : double)
            var r = 1
            for i = 0, i do
                r = r * a
            end
            return r
        end
    end

    mymath.pow1(2) -- 2
    mymath.pow2(2) -- 4
    mymath.pow3(2) -- 8

Here we use the fact that in Lua the select operator on tables (`a.b`) is equivalent to looking up the value in table (`a["b"]`).

You can call these power functions from a Terra function:

    terra doit()
        return mymath.pow3(3)
    end

Let's examine what happens when this function is compiled. The Terra compiler will resolve the `mymath` symbol to the Lua table holding the power functions. It will then see the select operator (the dot in `mymath.pow3`). Because `mymath` is a Lua table, the Terra compiler will perform this select operator at compile time, and resolve `mymath.pow3` to the third Terra function constructed inside the loop. It will then insert a direct call to that function inside `doit`. This behavior is a form of _partial execution_. In general, Terra will resolve any chain of select operations `a.b.c.d` on Lua tables at compile time. This behavior enables Terra to use Lua tables to organize code into different namespaces. There is no need for a Terra-specific namespace mechanism!

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

Terra allows you to use many types of Lua values in Terra functions. Here we saw two examples: the use of a Lua number `N` into a Terra number, and the use of a Terra function `mymath.pow3` in body of `doit`. Many Lua values can be converted into Terra values at compile time. The behavior depends on the value, and is described in  the [compile-time conversions](api.html#compiletime-conversions) section of the API reference.

### Scoping ###
Additionally, you may want to declare a Terra function as a _locally_ scoped Lua variable. You can use the `local` keyword:

    local terra foo()
    end

Which is just sugar for:

    local foo; foo = terra()
    end

Types and Operators
===================

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

    var a : bool = [bool](3)

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
    @pa = 4
    var b = @pa

You can read `&int` as a value holding the _address_ of an `int`, and `@a` as the value _at_ address `a`. To get a pointer to heap-allocated memory you can use stdlib's `malloc`:

    C = terralib.includec("stdlib.h")
    terra doit()
        var a = [&int](C.malloc(sizeof(int) * 2))
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

The function `array` will construct an array from a variable number of arguments:

    var a = array(1,2,3,4) -- a has type int[4]

If you want to specify a particular type for the elements of the array you can use `arrayof` function:

    var a = arrayof(int,3,4.5,4) -- a has type int[3]
                               -- 4.5 will be cast to an int

### Vectors ###

Vectors are like arrays, but also allow you to perform vector-wide operations:

    terra saxpy(a :float,  X : vector(float,3), Y : vector(float,3),)
    	return a*X + Y
    end

They serve as an abstraction of the SIMD instructions (like Intel's SSE or Arm's NEON ISAs), allowing you to write vectorized code. The constructors `vector` and `vectorof` create vectors, and behave similarly to arrays:

    var a = vector(1,2,3,4) -- a has type vector(int,4)
    var a = vectorof(int,3,4.5,4) -- a has type vector(int,3)
                                  -- 4.5 will be cast to an int

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

Like functions, symbols in struct definitions are resolved when the struct is defined, and can be linked together using `and`.

	struct C --declaration
	struct A {
		b : &B
	--and is required since A refers to B
	} and struct B {
		a : &A
		c : &C
	--you can mix struct and function
	--definitions
	} and terra myfunc()
	end

	struct C { i : int }

Terra has no explicit union type. Instead, you can declare that you want two or more elements of the struct to share the same memory:

    struct MyStruct {
        a : int; --unique memory
        union {
            b : double;  --memory for b and c overlap
            c : int;
        }
    }

### Tuples and Anonymous Structs ###

In Terra you can also _tuples_, which are a special kind of struct that contain a list of elements:

    var a : tuple(float,float) -- a pair of floats

You can use a constructor syntax to quickly generate tuple values:

    var a = { 1,2,3,4 } --has type tuple(int,int,int,int)

Tuples can be cast to other struct types, which will initialize fields of the struct in order:

    var c = Complex { 3,4 }

You can also add names to constructor syntax to create _anonymous structs_, similar to those in languages such as C-sharp:

    var b = { a = 3.0, b = 3 }

Terra allows you to cast any anonymous struct to another struct that has a superset of its fields.

    struct Complex { real : float, imag : float}
    var c = Complex { real = 3, imag = 1 }

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


Terra Types as Lua Values
=========================

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
        var pa : ptrint = &a
    end

In fact many primitive types are just defined as Lua variables:

    _G["int"] = int32
    _G["uint"] = uint32
    _G["long"] = int64
    _G["intptr"] = uint64 --these may be architecture specific
    _G["ptrdiff"] = int64

Making types Lua objects enables powerful behaviors such as templating. Here we create a template that returns a constructor for a dynamically sized array:

    function Array(typ)
        return terra(N : int)
            var r : &typ = [&typ](C.malloc(sizeof(typ) * N))
            return r
        end
    end

    local NewIntArray = Array(int)

    terra doit(N : int)
        var my_int_array = NewIntArray(N)
        --use your new int array
    end

Literals
========

Here are some example literals:

* `3` is an `int`
* `3.` is a `double`
* `3.f` is a `float`
* `3LL` is an `int64`
* `3ULL` is a `uint64`
* `"a string"` or `[[ a multi-line long string ]]` is an `&int8`
* `nil` is the null pointer for any pointer type
* `true` and `false` are `bool`


Assignments and Expression Lists
================================

When a function returns multiple values, it implicitly creates a tuple of those values as the return type:

    terra returns2() return 1,2 end
    terra example()
        var a = returns2() -- has type tuple(int,int)
        C.printf("%d %d\n",a._0,a._1)
    end

To make it easier to use functions that return multiple values, we allow a tuple that is the last element of an expression list to match multiple variables on the left the left-hand size.

    terra example2()
        var a,b,c = 1,returns2()
        var a,b,c = returns2(),1 --Error: returns2 is not the last element
    end

Methods
=======

Unlike languages like C++ or Scala, Terra does not provide a built-in class system that includes advanced features like inheritance or sub-typing. Instead, Terra provides the _mechanisms_ for creating systems like these, and leaves it up to the user to choose to use or build such a system. One of the mechanisms Terra exposes is a method invocation syntax sugar similar to Lua's `:` operator.

In Lua, the statement:

    receiver:method(arg1,arg2)

is syntax sugar for:

    receiver.method(receiver,arg1,arg2)

The function `method` is looked up on the object `receiver` dynamically. In contrast, Terra looks up the function statically at compile time. Since the _value_ of the `receiver` expression is not know at compile time, it looks up the method on its _type_.

In Terra, the statement:

    receiver:method(arg1,arg2)

where `receiver` has type `T` is syntax sugar for:

    T.methods.method(receiver,arg1,arg2)

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

The statement `a:add(b)` will normally desugar to `Complex.methods.add(a,b)`. Notice that `a` is a `Complex` but the `add` function expects a `&Complex`. If necessary, Terra will insert one implicit address-of operator on the first argument of the method call. In this case `a:add(b)` will desugar to `Complex.methods.add(&a,b)`.

Like the `.` selection operator, the `:` method operator can also be used directly on pointers. In this case, the pointer is first dereferenced, and the normal rules for methods are applied. For instance, when using the `:` operator on a value of type `&Complex` (e.g. `ptra`), it will first insert a dereference and desugar to `Complex.methods.add(@a,b)`.  Then to match the type of `add`, it will apply the implicit address-of operator to get `Complex.methods.add(&@a,b)`.  This allows a single method definition to take as an argument either a type `T` or a pointer `&T`, and still work when the method is called on value of type `T` or type `&T`.

To make defining methods easier, we provide a syntax sugar.

	terra Complex:add(rhs : Complex) : Complex
		...
	end

is equivalent to

    terra Complex.methods.add(self : &Complex, rhs : Complex) : Complex
        ...
    end

Terra also support _metamethods_ similar to Lua's operators like `__add`, which will allow you to overload operators like `+` on Terra types, or specify custom type conversion rules. See the [API reference on structs](api.html#structs) for more information.

Lua-Terra Interaction
=====================

We've already seen examples of Lua code calling Terra functions. In general, you can call a Terra function anywhere a normal Lua function would go. When passing arguments into a terra function from Lua they are converted into Terra types. The [current rules](api.html##converting-between-lua-values-and-terra-values) for this conversion are described in the API reference. Right now they match the behavior of [LuaJIT's foreign-function interface](http://luajit.org/ext_ffi_semantics.html). Numbers are converted into doubles, tables into structs or arrays, Lua functions into function pointers, etc. Here are some examples:

    struct A { a : int, b : double }

    terra foo(a : A)
        return a.a + a.b
    end

    assert( foo( {a = 1,b = 2.3} )== 3.3 )
    assert( foo( {1,2.3} ) == 3.3)
    assert( foo( {b = 1, a = 2.3} ) == 3 )

More examples are in `tests/luabridge*.t`.  

It is also possible to call Lua functions from Terra. Again, the translation from Terra objects to Lua uses LuaJITs conversion rules. Primitive types like `double` will be converted to their respective Lua type, while aggregate and derived types will be boxed in a LuaJIT `ctype` that can be modified from Lua:

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

since we cannot determine the Terra types that function will return, Lua functions do not return values to Terra functions by default. To convert a Lua function into a Terra function that does return a value, you first need to `cast` it to a Terra function type:

	function luaadd(a,b) return a + b end
	terraadd = terralib.cast( {int,int} -> int, luaadd)

	terra doit()
		return terraadd(3,4)
	end

Meta-programming
================

In this guide we've already encountered instances of meta-programming, such as using a Lua loop to create an array of  Terra `pow` functions. In fact, Terra includes several operators that it make it possible to generate _any_ code at runtime. For instance, you can implement an entire compiler by parsing an input string and constructing the Terra functions that implement the parsed code.

The operators we provide are adapted from [multi-stage programming](https://pdfs.semanticscholar.org/1726/703918e320dff60e013f76fa2a3bd22bc7b8.pdf). An _escape_ allows you to splice the result of a Lua expression into Terra. A _quote_ allows you to generate a new Terra statement or expression which can then be spliced into Terra code using an escape. _Symbol_ objects allow you to create unique names at compile time. Finally, a _macro_ can be used like a function call in Terra code but will be evaluated at compile-time. We'll look at each of these operators in detail.

### Escapes ###

Escapes allow you to splice the result of a Lua expression into Terra code. Here is an example:

	function get5()
		return 5
	end
	terra foobar()
		return [ get5() + 1 ]
	end
	foobar:printpretty()
	> output:
	> foobar0 = terra() : {int32}
	> 	return 6
	> end

When the function is defined, the Lua expression inside the brackets (`[]`) is evaluated to the Lua value `6`  which is then used in the Terra code. The Lua value is converted to a Terra value based on the rules for [compile-time conversions](api.html#compiletime-conversions) in the API reference (e.g. numbers are converted to Terra constants, global variables are converted into references to that global).

Escapes can appear where any expression or statement normally appears. When they appear as statements or at the end of en expression list, multiple values can be spliced in place by returning a Lua array:

	terra return123()
		--escape appends 2 values:
		return 1, [ {2,3} ]
	end

You can also use escapes to programmatically choose fields or functions:

	local myfield = "foo"
	local mymethod = "bar"
	terra fieldsandfunctions()
		var fields = myobj.[myfield]
		var methods = myobj:[mymethod]()
	end

Lua expressions inside an escape can refer to the variables defined inside a Terra function. For instance, this example chooses which variable to return based on a Lua parameter:

	local choosefirst = true
	local function choose(a,b)
		if choosefirst then
			return a
		else
			return b
		end
	end
	terra doit(a : double)
		var first = C.sin(a)
		var second = C.cos(a)
		return [ choose(first,second) ]
	end

Since Lua and Terra can refer to the same set of variables, we say that they _share_ the same lexical scope.

What values should `first` and `second` have when used in an escape? Since escapes are evaluated when a function is _defined_, and not when a function is _run_, we don't know the results of the `sin(a)` and `cos(a)` expressions when evaluating the escape. Instead, `first` and `second` will be _symbols_, an abstract data type representing a unique name used in Terra code.  Outside of a Terra expression, they do not have a concrete value. However, when placed in a Terra expression they become references to the original variable.  Going back to the example, the function `doit` will return either the value of `C.sin(a)` or `C.cos(a)` depending on which symbol is returned from the `choose` function and spliced into the code.

Previously, we have seen that you can use Lua symbols directly in the Terra code. For example, we looked at this `powN` function:

    local N = 4
    terra powN(a : double)
        var r = 1
        for i = 0, N do
            r = r * a
        end
        return r
    end

This behavior is actually just syntax sugar for an escape expression.  In Terra, _any_ name used in an expression (e.g. `a` or `r`) is treated as if it were an escape. Here is the same function de-sugared:

    local N = 4
    terra powN(a : double)
        var r = 1
        for i = 0, N do
            r = [r] * [a]
        end
        return [r]
    end

 In this case `[a]` will resolve to the value `4` and then be converted to a Terra constant, while `[r]` will resolve to a _symbol_ and be converted to a reference to the variable definition of `r` on the first line of the function.

 The syntax sugar also extends to field selection expressions such as `a.b.c`. In this case, if both `a` and `b` are Lua tables, then the expression will de-sugar to `[a.b.c]`. For instance, the call to `C.sin` and `C.cos` are de-sugared to `[C.sin]` and `[C.cos]` since `C` is a Lua table.

### Quotes ###

A quote allows you to generate a single Terra expression or statement outside of a Terra function. They are frequently used in combination with escapes to generate code. Quotes create the individual expressions and escapes are used stitch them together.

	function addone(a)
		--return quotation that
		--represents adding 1 to a    
		return `a + 1
    end
	terra doit()
		var first = 1
		--call addone to generate
		--expression first + 1 + 1
		return [ addone(addone(first)) ]
	end


If you want to create a group of statements rather than expressions, you can using the `quote` keyword:

	local printit = quote
		C.printf("a quotestatement")
	end

	terra doit()
		--print twice
		printit
		printit
	end

The `quote` keyword can also include an optional `in` statement that creates an expression:

    myquote = quote
        var a = foo()
        var b = bar()
    in
        a + b
    end

When used as an expression this quote will produce that value.

    terra doit()
        var one,two = myquote
    end

When a variable is used in an escape, it is sometimes ambiguous what value it should have.
For example, consider what value this function should return:


    function makeexp(arg)
        return quote
            var a = 2
            return arg + a
        end
    end
    terra client()
        var a = 1;
        [ makeexp(a) ];
    end


The variable name `a` is defined twice: once in the function and once in the quotation. A reference to `a` is then passed the `makeexp` function, where it is used inside the quote after `a` is defined. In the return statement, should `arg` have the value `1` or `2`? If you were using C's macro preprocessor, the equivalent statement might be something like

    #define MAKEEXP(arg) \
        int a = 2; \
        return arg + a; \

    int scoping() {
        int a = 1;
        MAKEEXP(a)
    }

In C, the function would return `4`. But this seems wrong -- `MAKEEXP` may have been written by a library writer, so the writer of `scoping` might not even know that `a` is used in `MAKEEXP`. This behavior is normally call _unhygienic_ since it is possible for the body of the quotation to accidentally redefine a variable in the expression. It makes it difficult to write reusable functions that generate code and is one of the reasons macros are discouraged in C.

Instead, Terra ensures that variable references are _hygienic_. The reference to `a` in `makeexp(a)` refers uniquely to the definition of `a` in the same [lexical scope](http://en.wikipedia.org/wiki/Scope_%28computer_science%29#Lexical_scoping_and_dynamic_scoping) (in this case, the definition of `a` in the `client` function). This relationship is maintained regardless of where the symbol eventually ends up in the code, so the `scoping` function will correctly return the value `3`.

This hygiene problem occurs in all languages that have meta-programming.
Wikipedia has [more discussion](http://en.wikipedia.org/wiki/Hygienic_macro). By maintaining hygiene and using lexical scoping, we guarantee that you can always inspect a string of Terra code and match variables to their definitions without knowing how the functions will execute.

### Dynamically Generated Symbols ###

For the most part, hygiene and lexical scoping are good properties. However, you may want to occasionally violate lexical scoping rules when generating code.  For instance, you may want one quotation to introduce a local variable, and another separate quotation to refer to it. Terra provides a controlled way of violating lexical scoping using the `symbol()` function, which returns a unique variable name (a _symbol_) each time it is called (this is the Terra equivalent of Common Lisp's `gensym`).  Here is an example that creates a new symbol, defines the symbol in one quotation and then uses it in another.

    local a = symbol()

    defineA = quote
            var [a] = 3
        end

    twiceA = `2*a

    terra doit()
        defineA
        return twiceA
    end

The symbol function can also take a type as an argument `symbol(int)`. This has the same effect as when you write `var a : int` in a declaration. It is optional when the type of the definition can be inferred (e.g. when it is local variable with an initializer), but required when it cannot be inferred (e.g. when it is a parameter to a function).

Notice that the declaration of the symbol uses the escape `[a]` in place of `a`. Using just `a` would make a local variable with name `a` that is not in scope outside of that quotation. In this context, the escape instructs the Terra compiler to parse that part as a Lua expression, evaluate it, and drop the result in place. In this case, the result of evaluation `a`  is the symbol generated by the `symbol()` function. Similarly the reference to `a` in the expression `2*a` will evaluate to the same symbol object. If we had omitted the escape, then we would receive a compilation error reporting that `2*a` refers to an undefined variable.

 A list of symbols can also be spliced onto the end of parameter lists to generate functions with a configurable number of arguments:

    local rest = {symbol(int),symbol(int)}

    terra doit(first : int, [rest])
        return first + [rest[1]] + [rest[2]]
    end

### Macros ###

By default, when you call a Lua function from Terra code, it will execute at runtime, just like a normal Terra function. It is sometimes useful for the Lua function to execute at compile time instead. Calling the Lua function at compile-time is called a _macro_ since it behaves similarly to macros found in Lisp and other languages. You can create macro using the function `macro` which takes a normal Lua function and returns a macro:

    local times2 = macro(function(ctx,tree,a)
        return `a + a
    end)

    terra doit()
        var a = times2(3)
        -- a == 6
    end

Unlike a normal function, which works on Terra values, the arguments to Terra macros are passed to the macro as _quotes_.

The first argument to every macro is the compilation context `ctx`. It can be used to report an error if the macro doesn't apply to the arguments given, and is needed in certain API calls used in macros. The second argument to every macro (`tree`) is the AST node in the code that represents the macro call. It is typically used as the location at which to report an error in a macro call. The following code will cause the compiler to emit an error referring to the macro call with given error message:

    ctx:reporterror(tree, "something in the macro went wrong")

The remaining arguments to the macro are the AST nodes of the arguments to the macro function.

Since macros take quotes rather than values, they have different behavior than function calls. For instance:

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
        return terralib.newtree(tree,{ kind = terra.kinds.sizeof,
                                       oftype = typ:astype()})
    end)

`terra.newtree` creates a new node in this AST. For the most part, macros can rely on code quotations to generate AST nodes, and only need to fallback to explicitly creating AST nodes in special cases.

Macros can also be used to create useful patterns like a C++ style new operator:

    new = macro(function(ctx,tree,typquote)
        local typ = typquote:astype()
        return `[&typ](C.malloc(sizeof(typ)))
    end)

    terra doit()
        var a = new(int)
    end

You may be wondering why Terra includes both macros and escapes. They both allow you to splice Terra code into other expressions, and in some cases you can use either a macro or an escape to accomplish the same purpose.  Since macros look like function calls, they are normally used when it is not important for the end-user to know that the functionality is implemented by generating code.  For instance, in `myobj:mymethod(arg)`, `mymethod` can be implemented as a macros. Furthermore, while escapes are evaluated when a function is _defined_ (that is, when the surround Lua code executes), macros are run when a function is _compiled_, which only happens when a function is actually called. This means that macros have access to the types of expressions via the `myquote:gettype()` method call.

More Information
================

More details about the interaction of Terra and Lua can be found in the [API reference](api.html). The best place to look for more examples of Terra features is the `tests/` directory, which contains the set of up-to-date languages tests for the implementation. The `tests/libs` folder contains some examples of meta-programming such as class systems.

If you are interested in the implementation, you can also look at the source code.  The compiler is implemented as a mixture of Lua code and C/C++. Passing the `-v` flag to the interpreter will cause it to give verbose debugging output.

* `lparser.cpp` is an extended version of the Lua parser that implements Terra parsing. It parsers Terra code, building the Terra AST for Terra code, while passing the remaining code to Lua (use `-vv` to see what is passed to Lua).

* `terralib.lua` contains the Lua infrastructure for the Terra compiler, which manages the Terra objects like functions and types. It also performs type-checking on Terra code before compilation.

* `tcompiler.cpp` contains the LLVM-based compiler that translates the Terra AST into LLVM IR that can then be JIT compiled to native code.

* `tcwrapper.cpp` contains the Clang-based infrastructure for including C code.

* `terra.cpp` contains the implementation of Terra API functions like `terra_init`

* `main.cpp` contains the Terra REPL (based on the Lua REPL).

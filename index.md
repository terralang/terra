---
layout: post
title: Terra
---
__Terra__ is a new low-level system programming language that is designed to interoperate seamlessly with the __Lua__ programming language:

    -- This top-level code is plain Lua code.
    print("Hello, Lua!")
    
    -- Terra is backwards compatible with C
    -- we'll use C's io library in our example.
    C = terralib.includec("stdio.h")
    
    -- The keyword 'terra' introduces
    -- a new Terra function.
    terra hello(argc : int, argv : &rawstring)
        -- Here we call a C function from Terra
        C.printf("Hello, Terra!\n")
        return 0
    end
    
    -- You can call Terra functions directly from Lua
    hello(0,nil)

    -- Or, you can save them to disk as executables or .o
    -- files and link them into existing programs
    terralib.saveobj("helloterra",{ main = hello })

Like C, Terra is a simple, statically-typed, compiled language with manual memory management. But unlike C, it is designed from the beginning to interoperate with Lua. Terra functions are first-class Lua values created using the `terra` keyword. When needed they are JIT-compiled to machine code.

You can **use** Terra and Lua as...

**A scripting-language with high-performance extensions**. While the performance of Lua and other dynamic languages is always getting better, a low-level of abstraction gives you predicatable control of performance when you need it. Terra programs use the same LLVM backend that Apple uses for its C compilers. This means that Terra code performs similarly to equivalent C code. For instance, our translations of the `nbody` and `fannhakunen` programs from the [programming language shootout](http://benchmarksgame.alioth.debian.org) perform within 5% of the speed of their C equivalents compiled with Clang, LLVM's C frontend. Terra also includes built-in support for SIMD operations, and other low-level features like non-temporal writes and prefetches. You can use Lua to organize and configure your application, and then call into Terra code when you need controllable performance.

**An embedded JIT-compiler for building languages**. We use techniques from [multi-stage programming](http://www.cs.rice.edu/~taha/MSP/) to make it possible to **meta-program** Terra using Lua.  Terra expressions, types, functions, and variables are all first-class Lua values, making it possible to generate arbitrary programs at runtime. This allows you to **[compile domain-specific languages](#generative_programming)** (DSLs) written Lua into high-performance Terra code. Furthermore, since Terra is built on the Lua ecosystem, it is easy to **[embed](#embedding_and_interoperability)** Terra-Lua programs in other software as a library. This design allows you to add a JIT-compiler into your existing software. You can use it to add a JIT-compiled DSL to your application, or to auto-tune high-performance code dynamically.

**A stand-alone low-level language**. Terra was designed so that it can run independly from Lua. In fact, if your final program doesn't need Lua, you can also save Terra code into a .o file or executable. In addition to ensuring a clean sepearation between high- and low-level code, this design lets you use Terra a stand-alone low-level language. In this use-case, Lua serves as a powerful meta-programming language.  You can think of it as a replacement for C++ Template Meta-programming or C preprocessor X-Macros with better syntax and nicer properties such as [hygiene](http://en.wikipedia.org/wiki/Hygienic_macro). Since Terra exists *only* as code embedded in a Lua meta-program, features that are normally built into low-level languages can be implemented as Lua libraries. This design keeps the core of Terra simple, while enabling powerful behavior such as conditional compilation, namespaces, templating, and even **class systems** to be **[implemented as libraries](#simplicity)**.

For more information about using Terra, see the [getting started guide](getting-started.html), and [API reference](api.html). Our [publications](publications.html) have a more in-depth look at its design. 


Generative Programming
----------------------

What does it mean to be first class? Reference MetaOCaml for multi-stage programming. Show escape operator for simple Lua calculation to Terra value and mention LuaJIT FFI. Reveal that symbols and table lookups are actually always escaped. Discuss shared scope, and the fact that you can use Terra symbols in escapes. Introduce quotations.

BF compiler example.

All Terra entities are first-class Lua values, including types, functions, variables, and even statements/expressions. You can create a Terra expression in Lua using the quotation operator (backtick):
    
    local codeforprint = `C.printf("this is a print")

This can be spliced into a Terra function using the escape operator (`[]`)
    
    terra printtwice()
        [codeforprint];
        [codeforprint];
    end

With these two operators, you can use Lua to generate _arbitrary_ Terra code at compile-time. This makes the combination of Lua/Terra well suited for writing compilers for high-performance domain-specific languages. 


Embedding and Interoperability
------------------------------

You've seen the ability to call C.
You can also save the code so it works independently from Lua.
Or, you can embed it in other programs via the C API (show simple REPL).

Simplicity
----------

The combination of a simple low-level language with a simple dynamic programming language means that many built-in features of statically-typed low-level languages can be implemented as libraries in the dynamic language. Here are just a few examples:

### Conditional Compilation ###
   
Normally conditional compilation is accomplished using preprocessor directives (e.g., `#ifdef`),
or custom build systems. Using Lua-Terra, we can write Lua code to decide how to construct a Terra function.
Since Lua is a full programming language, it can do things that most preprocessors cannot, such as call external programs.
In this example, we conditionally compile a Terra function differently on OSX and Linux by first calling `uname` to discover
the operating system, and then using a `if` statement to instanciate a different version of the Terra function depending on the result: 

    --run uname to figure out what OS we are running
    local uname = io.popen("uname","r"):read("*a")
    local C = terralib.includec("stdio.h")

    if uname == "Darwin" then
        terra reportos()
            C.printf("this is osx\n")
        end
    elseif uname == "Linux" then
        terra reportos()
            C.printf("this is linux\n")
        end
    else
        error("OS Unknown")
    end

    --conditionally compiled to 
    --the right version for this os
    reportos()
    
### Namespaces ###

Statically-typed languages normally need constructs that specifically deal with the problem of namespaces (e.g., C++'s `namespace` keyword, or Java's `import` constructs). For Terra, we just use Lua's first-class tables as way to organize functions. When you use any "name" such as `myfunctions.add` inside a Terra function, the Terra will resolve it at _compile time_ to the Terra value it holds. Here is an example of placing a Terra function inside a Lua table, and then calling it from another Terra function:

    local myfunctions = {}
    -- terra functions are first-class Lua values
    
    -- they can be stored in Lua tables
    terra myfunctions.add(a : int, b : int) : int
        return a + b
    end

    -- and called from the tables as well
    terra myfunctions.add3(a : int)
        return myfunctions.add(a,3)
    end

    --the declaration of myfunctions.add is just syntax sugar for:

    myfunctions["add"] = terra(a : int, b : int) : int
        return a + b
    end

    print(myfunctions.add3(4))
    
In fact, you've already seen this behavior when we imported C functions:

    C = terralib.includec("stdio.h")

The function `includec` just returns a Lua table (`C`) that contains the C functions. Since `C` is a Lua table, you can iterate through it if you want:

    for k,v in pairs(C) do
        print(k,v)
    end

    > seek   <terra function>
    > asprintf    <terra function>
    > gets    <terra function>
    > size_t  uint64
    > ...

### Templating ###

Since Terra types and functions are first class values, you can get functionality similar to a C++ template by simply creating a Terra type and defining a Terra function _inside_ of a Lua function. Here is an example where we define the Lua function `MakeArray(T)` which takes a Terra type `T` and generates an `Array` object that can hold multiple `T` objects (i.e. a simple version of C++'s `std::vector`).

    
    C = terralib.includec("stdlib.h")
    function MakeArray(T)
        --create a new Struct type that contains a pointer 
        --to a list of T's and a size N
        local struct ArrayT {
            data : &T;
            N : int;
        } 
        --add some methods to the type
        terra ArrayT:init(N : int)
            self.data = [&T](C.malloc(sizeof(T)*N))
            self.N = N
        end
        terra ArrayT:get(i : int)
            return self.data[i]
        end
        terra ArrayT:set(i : int, v : T)
            self.data[i] = v
        end
        --return the type as a 
        return ArrayT
    end

    IntArray = MakeArray(int)
    DoubleArray = MakeArray(double)

    terra UseArrays()
        var ia : IntArray, da : DoubleArray
        ia:init(1) 
        da:init(1)
        ia:set(0,3)
        da:set(0,4.5)
        return ia:get(0) + da:get(0)
    end

As shown in this example, Terra allows you to define methods on `struct` types.
Unlike other statically-typed languages with classes, there are no built-in mechanisms for inheritance or dynamic dispatch.
Methods declarations are just a syntax sugar that associates table of Lua methods with each type. Here the `get` method is equivalent to:

    ArrayT.methods.get = terra(self : &T, i : int)
        return self.data[i]
    end

The object `ArrayT.methods` is a Lua table that holds the methods for type `ArrayT`.

Similarly an invocation such as `ia:get(0)` is equivalent to `T.methods.get(&ia,0)`.

### Specialization ###
    
By nesting a Terra function inside a Lua function, you can compile different versions of a function. Here we generate different versions
of the power function (e.g. pow2, or pow3):
    
    --generate a power function for a specific N (e.g. N = 3)
    function makePowN(N)
        return terra(a : double)
            var r = 1.0
            for i = 0, N do
                r = r * a
            end
            return r
        end
    end

    --use it to fill in a table of functions
    local mymath = {}
    for n = 1,10 do
        mymath["pow"..n] = makePowN(n)
    end
    print(mymath.pow3(2)) -- 8

    --use it to fill in a table of functions
    local mymath = {}
    for n = 1,10 do
        mymath["pow"..i] = makePowN(n)
    end
    print(mymath.pow3(2)) -- 8

### Class Systems ###

As shown in the templating example, Terra allows you to define methods on `struct` types but does not provide any built-in mechanism for inheritance or polymorphism. Instead, normal class systems can be written as libraries.  For instance, a user might write:

    J = terralib.require("lib/javalike")
    Drawable = J.interface { draw = {} -> {} }
    struct Square { length : int; }
    J.extends(Square,Shape)
    J.implements(Square,Drawable)
    terra Square:draw() : {}

    end

The functions `J.extends` and `J.implements` are Lua functions that generate the appropriate Terra code to implement a class system. More information is availiable in our [PLDI Paper](/publications.html) and the file [lib/javalike.t](https://github.com/zdevito/terra/blob/master/tests/lib/javalike.t) has one possible implementation.



    
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
    
    -- And you can call Terra functions directly from Lua
    hello(0,nil)

    -- Or, you can save them to disk as executables or .o
    -- files and link them into existing programs
    terralib.saveobj("helloterra",{ main = hello })

Like C, Terra is a simple, statically-typed, compiled language with manual memory management. But unlike C, it is designed from the beginning to interoperate with Lua. Terra functions are first-class Lua values created using the `terra` keyword. When needed they are JIT-compiled to machine code.

**Why** design a language this way?

**[Performance](#performance)** Terra programs are low-level. They use the same LLVM backend that Apple uses for its C compilers. This means that Terra code performs similarly to equivalent C code. For instance, our translations of the `nbody` and `fannhakunen` programs from the [programming language shootout](http://benchmarksgame.alioth.debian.org) perform within 5% of the speed of their C equivalents compiled with Clang. A low-level of abstraction doesn't guarantee performance, but it makes it possible to always extract performance when you need it.

**[Generative Programming](#generative_programming)** We use techniques from multi-stage programming to make it possible to meta-program Terra using Lua.  Terra expressions, types, functions, and variables are all first-class Lua values, making it possible to generate arbitrary programs. This allows you to **compile domain-specific languages** written Lua into high-performance Terra code. We're are already using Terra to create the Orion image processing language, and plan to port the [Liszt language](http://liszt.stanford.edu) to it soon.

**[Interoperability](#interoperability)** In fact, if your final program doesn't need Lua, you can also save Terra functions into .o files or executables and use it as a stand-alone low-level language.

**[Simplicity](#simplicity)** Features that are normally built into low-level languages can be expressed as meta-programmings using Lua-Terra. This design keeps the core of Terra simple, while enabling power behaviors such as conditional compilation, namespaces, templating, and even **class systems** to be **implemented as libraries**. 



Performance
-----------


Discussion of reasons for still wanting a low-level programming language. Especially as a target for DSLs.

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


Interoperability
----------------

You've seen the ability to call C.
You can also save the code so it works independently from Lua.
Or, you can embed it in other programs via the C API (show simple REPL).

Simplicity
----------

The combination of a simple low-level language with a dynamic programming languages means that many built-in features of statically typed low-level languages 

### Conditional Compilation ###
   
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

    print(myfunctions.add3(4))
    
### Templating ###
    
    --terra types are first-class Lua values as well
    --this Lua function creates a Terra add function
    --given the Terra type
    function makeadd(thetype)
        return terra(a : thetype, b : thetype) : thetype
            return a + b
        end
    end

    integeradd = makeadd(int)
    doubleadd = makeadd(double)

### Specialization ###
    
    --generate a power function for a specific N (e.g. N = 3)
    function makePowN(N)
        return terra(a : double)
            var r = 1.0
            for i = 0, i do
                r = r * a
            end
            return r
        end
    end

    --use it to fill in a table of functions
    local mymath = {}
    for n = 1,10 do
        mymath["pow"..i] = makePowN(n)
    end
    print(mymath.pow3(2)) -- 8


    
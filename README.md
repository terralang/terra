Getting Started with Terra
==========================

_Zach DeVito <zdevito@stanford.edu>_

Terra is a new low-level system programming language that is designed to interoperate seamlessly with the Lua programming language, while still being backwards compatible with (and embeddable in) existing C code. Like C, Terra is a monomorphic, statically-typed, compiled language with manual memory management. But unlike C, it is designed to make interaction with Lua easy. Terra code shares Lua's syntax and control-flow constructs. It is easy to call Lua functions from Terra (or Terra functions from Lua). 

Additionally, Lua serves as the meta-programming language for Terra code.  Lua handles details of Terra code like conditional compilation, namespaces, and templating that are normally special constructs in low-level languages.  Furthermore, this coupling enables more powerful features like function specialization, lisp-style macros, and manually controlled JIT compilation. Since Terra's compiler is available at runtime, it makes it easy to write libraries or embedded languages that need to generate low-level code dynamically.

This guide serves as an introduction for programming in Terra. A general understanding of the Lua language would be very helpful, but not strictly required.

Rationale
---------

Programming languages make fundamental tradeoffs between productivity and performance.  While JIT compilers can make dynamic languages like Python, Javascript, or Lua run more efficiently, they rarely match the performance of a low-level language like C, and can be difficult to use in a embedded/power-constrained context. On the flip side, C is much more difficult and error-prone to program in.

Other languages like Go, C++, D, Scala, Java, or, Cython try to strike a balance beween these constraints. But this can increase the total complexity of the language, and can create weird interactions between features.

An alternative popular in the game programming community is to use two programming languages. A performance language (typically C/C++) for rendering and simulation, and a dynamic language (often Lua) for scripting and configuration.  

Though Lua was designed from first principles to work with C, C was not designed to interoperate easily with dynamic languages.  Terra is fills this gap by being a low-level language designed to work with Lua. In contrast to Lua, Terra is statically typed, monomorphic, and manually manages memory.  However, unlike C, Terra is specifically designed to make interaction with Lua seamless.  The result is a pair of languages that are individually simple, but combine in powerful ways.

Installation
------------

This section will walk you through installing Terra's dependencies, and building the library. Terra is being developed on Mac OS X. It should also run on Linux, but it has not been tested on Linux yet, so there are probably small problems like missing headers, and different locations for some libraries.

Terra uses LLVM 3.1, Clang 3.1 (the C/C++ frontend for LLVM), and LuaJIT 2.0 -- a tracing-JIT for Lua code.  Terra will download and compile LuaJIT for you, but you will need to install Clang and LLVM. The easiest way to do this is to the download the _Clang Binaries_ (which also include LLVM binaries) from
[LLVM download](http://llvm.org/releases/download.html) page.

Unzip the tar ball and then copy it into `/usr/local`:

    $ tar -xf clang+llvm-3.1-x86_64-apple-darwin11.tar.gz
    $ cp -r clang+llvm-3.1-x86_64-apple-darwin11/ /usr/local

Clang should now report being version 3.1:

    $ clang --version
    clang version 3.1 (branches/release_31)
    Target: x86_64-apple-darwin10.8.0
    Thread model: posix

Type make in the `terra` directory to build Terra:

    $ make

Running Terra
-------------

Similar to the design of Lua, Terra can be used as a standalone interpreter/read-eval-print-loop (REPL) and also as a library embedded in a C program. `libterra.a`. This design makes it easy to integrate with existing projects.

To run the REPL:
    
    $ ./terra
    
    Terra -- A low-level counterpart to Lua
    
    Stanford University
    zdevito@stanford.edu
    
    > 
    
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

In addition to these modes, Terra code can be compiled to `.o` files which can be directly linked into an executable. This feature is not yet implemented. Features that are not implemented will be marked with _NYI_ in this guide when they come up.

For the remainder of the guide, we will assume that you are using the `terra` executable to run scripts. A bunch of example scripts can be found in the `tests/` directory.

Hello, World
------------

Hello world is simple:

    print("hello, world")

This program is actually a completely valid Lua program as well. In fact, the top-level declarations in a Terra source code file are always run as normal Lua code! This top-level Lua layer handles the details like conditional compilation, namespaces, and templating of terra code. We'll see later that it additionally allows for more powerful features such as function specialization, lisp-style macros, and code quotations.

To actually begin writing Terra code, we introduce a Terra function with the keyword `terra`:

    terra addone(a : int)
        return a + 1
    end

    print(addone(2)) --this outputs: 3
    
Unlike Lua, arguments to Terra functions are explicitly typed. Terra uses a simple static type propagation to infer the return type of the `addone` function. You can also explicitly specify it:

    terra addone(a : int) : int
    
The last line of the example invokes the Terra function from the top level context (which is Lua code). This is an example of the interaction between Terra and Lua.
Terra code is JIT compiled to machine code when it is first _needed_. In this example, this occurs when `addone` is called. In general, functions are _needed_ when then are called, or when they are referred to by other functions that are being compiled. If you want to avoid the overhead of compiling code at runtime, you can also compile code ahead of time and save it in a `.o` file (NYI).

More information on the interface between Terra and Lua can be found in [Lua-Terra interaction](#interaction).

We can also print "hello, world" directly from Terra like so:

    local c = terralib.includec("stdio.h")
    
    terra main()
        c.printf("hello, world\n")
    end
    
    main()
    
The function `terralib.includec` is a Lua function that invokes Terra's backward compatibility layeer to import C code in `stdio.h` into the Lua table `c`. Terra functions can then directly call the C functions. Since both clang (our C frontend) and Terra target the LLVM intermediate representation, there is no additional overhead in calling a C function. Terra can even inline across these calls if the source of the C function is available!

The `local` keyword is a Lua construct. It introduces a locally scoped Lua variable named `c`. If omitted it would create a globally scoped variable.

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
        if b then
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

    terra sort2(a : int, b : int, c : int) : (int,int) --the return type is optional
        if a < b then   
            return a, b
        else
            return b, a
        end
    end
    
    terra doit()
        var a,b = sort2(3,4)
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

Here `N` is a Lua value of type `number`. When `powN` is compiled, the value of `N` is looked up and inlined into the function. 

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

You can also call these power functions from a Terra function:

    terra doit()
        return math.pow3(3) 
    end
    
Let's examine what is happens when this function is compiled. The Terra compiler will resolve the `math` symbol to the Lua table holding the power functions. It will then see the select operator (`math.pow3`). Because `math` is a Lua table, the Terra compiler will perform this select operator at compile time, and resolve `math.pow3` to the third Terra function constructed inside the loop.  It will then insert a direct call to that function inside `doit`. This behavior is a form of _partial execution_. In general, Lua will resolve any chain of select operations `a.b.c.d` at compile time. This behavior enables Terra to use Lua tables to organize code into different namespaces. There is no need for a Terra specific namespace mechanism!

Revisiting including C files:
    
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

Additionally, you may want to declare a Terra function as a _locally_ scoped Lua variable. You can use the `local` keyword:

    local terra foo()
    end
    
Which is just sugar for:

    local foo; foo = terra()
    end()

Types
-----

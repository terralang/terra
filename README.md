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

    $ tar-xf clang+llvm-3.1-x86_64-apple-darwin11.tar.gz
    $ cp -r clang+llvm-3.1-x86_64-apple-darwin11/ /usr/local

Clang should now report being version 3.1

    $ clang --version
    Apple clang version 3.0 (tags/Apple/clang-211.10.1) (based on LLVM 3.0svn)
    Target: x86_64-apple-darwin10.8.0
    Thread model: posix

Type make in the terra directory to build terra:

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
A simple example initialized Terra subsystem inside a Lua state and then runs the code in each file:

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

In addition to these modes, terra code can be compiled to `.o` files which can be directly linked into an executable. This feature is not yet implemented. Features that are not implemented will be marked with _NYI_ in this guide when they come up.

For the remainder of the guide, we will assume that you are using the `terra` executable to run scripts. A bunch of example scripts can be found in the `tests/` directory.

Hello, World
------------

Hello world is simple:

    print("hello, world")
    
Note that this program is actually completely valid Lua program as well. In fact, the top-level declarations in a Terra source code file are actually run as normal Lua code! The top-level Lua layer handles the details like conditional compilation, namespaces, and templating of terra code. We'll see later that it additionally allows for more powerful features such as function specialization, lisp-style macros, and code quotations.

To actually introduce a Terra function we use the keyword `terra`:

    terra addone(a : int)
        return a + 1
    end

    print(addone(2)) --this outputs: 3
    
Note that unlike Lua, arguments to Terra functions are explicitly typed. Terra uses a simple static type propagation to infer the return type of the `addone` function. You can also explicitly specify it:

    terra addone(a : int) : int
    
Note that the last line of the example invokes the Terra function from the top level context (which is Lua code). This is an example of the interaction between Terra and Lua.
Terra code is JIT compiled to machine code when it is first _needed_. In this example, this occurs when `addone` is called. In general, functions are _needed_ when then are called, or when they are referred to by other functions that are being compiled. If you want to avoid the overhead of compiling code at runtime, you can also compile code ahead of time and save it in a `.o` file (NYI).

More information on the interface between Terra and Lua can be found in [Lua-Terra interaction](#interaction).

We can also print "hello, world" directly from Terra like so:

    local c = terralib.includec("stdio.h")
    
    terra main()
        c.printf("hello, world\n")
    end
    
    main()
    
The function `terralib.includec` is a Lua function that invokes Terra's backward compatibility later to import C code in `stdio.h` into the Lua table `c`. Terra functions can then directly call the C functions. Since both clang (our C frontend) and Terra target the LLVM intermediate representation, there is no additional overhead int calling a C function. Terra can even inline across these calls if the source of the C function is available!

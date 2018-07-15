---
layout: post
title: Terra
---
__Terra__ is a low-level system programming language that is embedded in and meta-programmed by the __Lua__ programming language:

    -- This top-level code is plain Lua code.
    function printhello()
        -- This is a plain Lua function
        print("Hello, Lua!")
    end
    printhello()

    -- Terra is backwards compatible with C, we'll use C's io library in our example.
    C = terralib.includec("stdio.h")
    
    -- The keyword 'terra' introduces a new Terra function.
    terra hello(argc : int, argv : &rawstring)
        -- Here we call a C function from Terra
        C.printf("Hello, Terra!\n")
        return 0
    end
    
    -- You can call Terra functions directly from Lua, they are JIT compiled 
    -- using LLVM to create machine code
    hello(0,nil)

    -- Terra functions are first-class values in Lua, and can be introspected 
    -- and meta-programmed using it
    hello:disas()
    --[[ output:
        assembly for function at address 0x60e6010
        0x60e6010(+0):		push	rax
        0x60e6011(+1):		movabs	rdi, 102129664
        0x60e601b(+11):		movabs	rax, 140735712154681
        0x60e6025(+21):		call	rax
        0x60e6027(+23):		xor	eax, eax
        0x60e6029(+25):		pop	rdx
        0x60e602a(+26):		ret
    ]]
    
    -- You can save Terra code as executables, object files, or shared libraries 
    -- and link them into existing programs
    terralib.saveobj("helloterra",{ main = hello })
{: id="introcode"}

Like C/C++, Terra is a  **statically-typed**, **compiled language** with manual memory management. 
But unlike C/C++, it is designed from the beginning to be **meta-programmed from Lua**. 

The design of Terra comes from the realization that C/C++ is really composed of multiple "languages." It has a core language of operators, control-flow, and functions calls, but surrounding this language is a meta-language composed of a mix of features such as the pre-processor, templating system, and struct definitions. Templates alone are Turing-complete and have been used to produce optimized libraries such as [Eigen](http://eigen.tuxfamily.org/index.php?title=Main_Page), but are horrible to use in practice. 

In Terra, we just gave in to the trend of making the meta-language of C/C++ more powerful and replaced it with a real programming language, Lua. 

The combination of a low-level language meta-programmed by a high-level scripting language allows many behaviors that are not possible in other systems. Unlike C/C++, Terra code can be JIT-compiled and run interleaved with Lua evaluation, making it easy to write software libraries that depend on runtime code generation. 

Features of other languages such as conditional compilation and templating simply fall out of the combination of using Lua to meta-program Terra:

    -- C++                    |  -- Lua/Terra
    int add(int a, int b) {   |  terra add(a : int,b : int) : int
        return a + b;         |      return a + b
    }                         |  end
                              |  
                              |  -- Conditional compilation is done
                              |  -- with  control-flow that 
                              |  -- determines what code is defined
    #ifdef _WIN32             |  if iswindows() then
    void waitatend() {        |      terra waitatend()
        getchar();            |          C.getchar()
    }                         |      end
    #else                     |  else
    void waitatend() {}       |      terra waitatend() end
    #endif                    |  end
                              |  
                              |  -- Templates become Lua functions
                              |  -- that take a terra type T and 
                              |  -- use it to generate new types 
                              |  -- and code
    template<class T>         |  function Array(T)
    struct Array {            |      struct Array {
        int N;                |          N : int
        T* data;              |          data : &T
                              |      }
        T get(int i) {        |      terra Array:get(i : int)
            return data[i];   |          return self.data[i]
        }                     |      end
                              |      return Array
    };                        |  end
    typedef                   |  
    Array<float> FloatArray;  |  FloatArray = Array(float)

---

You can **use** Terra and Lua as...

**An embedded JIT-compiler for building languages**. We use techniques from multi-stage programming[<sup>2</sup>](#footnote2) to make it possible to **[meta-program](#generative-programming)** Terra using Lua.  Terra expressions, types, and functions are all first-class Lua values, making it possible to generate arbitrary programs at runtime. This allows you to **[compile domain-specific languages](#compiling-a-language)** (DSLs) written in Lua into high-performance Terra code. Furthermore, since Terra is built on the Lua ecosystem, it is easy to **[embed](#embedding-and-interoperability)** Terra-Lua programs in other software as a library. This design allows you to add a JIT-compiler into your existing software. You can use it to add a JIT-compiled DSL to your application, or to auto-tune high-performance code dynamically.

**A scripting-language with high-performance extensions**. While the performance of Lua and other dynamic languages is always getting better, a low-level of abstraction gives you predictable control of performance when you need it. Terra programs use the same LLVM backend that Apple uses for its C compilers. This means that Terra code performs similarly to equivalent C code. For instance, our translations of the `nbody` and `fannhakunen` programs from the programming language benchmark game[<sup>1</sup>](#footnote1) perform within 5% of the speed of their C equivalents when compiled with Clang, LLVM's C frontend. Terra also includes built-in support for SIMD operations, and other low-level features like non-temporal writes and prefetches. You can use Lua to organize and configure your application, and then call into Terra code when you need controllable performance.


**A stand-alone low-level language**. Terra was designed so that it can run independently from Lua. In fact, if your final program doesn't need Lua, you can save Terra code into a .o file or executable. In addition to ensuring a clean separation between high- and low-level code, this design lets you use Terra as a stand-alone low-level language. In this use-case, Lua serves as a powerful meta-programming language.  Here it serves as a replacement for C++ template metaprogramming[<sup>3</sup>](#footnote3) or C preprocessor X-Macros[<sup>4</sup>](#footnote4) with better syntax and nicer properties such as hygiene[<sup>5</sup>](#footnote5). Since Terra exists *only* as code embedded in a Lua meta-program, features that are normally built into low-level languages can be implemented as Lua libraries. This design keeps the core of Terra simple, while enabling powerful behavior such as conditional compilation, namespaces, templating, and even **class systems** **[implemented as libraries](#simplicity)**.

For more information about using Terra, see the **[getting started guide](getting-started.html)** and **[API reference](api.html)**. Our **[publications](publications.html)** provide a more in-depth look at its design. 

---

\[1\] <a id="footnote1"> </a> <http://benchmarksgame.alioth.debian.org><br/>
\[2\] <a id="footnote2"> </a> <http://www.cs.rice.edu/~taha/MSP/><br/>
\[3\] <a id="footnote3"> </a> <http://en.wikipedia.org/wiki/Template_metaprogramming><br/>
\[4\] <a id="footnote4"> </a> <http://en.wikipedia.org/wiki/X_Macro><br/>
\[5\] <a id="footnote5"> </a> <http://en.wikipedia.org/wiki/Hygienic_macro><br/>

---

Generative Programming
----------------------

Terra entities such as functions, types, variables and expressions are first-class Lua values --- they can be stored in Lua variables and passed to or returned from Lua functions. Using constructs from multi-stage programming[<sup>2</sup>](#footnote2), you can write Lua code to programmatically generate arbitrary Terra code. 

### Multi-stage operators ###

Inside Terra code, you can use an _escape_ operator (`[]`) to splice the result of a Lua expression into the Terra code:
    
    local a = 5
    terra sin5()
        return [ math.sin(a) ]
    end

An escape is evaluated when a Terra function is _compiled_, and the result is spliced into the Terra code. In this example, this means that `math.sin(5)` will be evaluated _once_ and the code that implements the Terra function will return a constant. This can be verified by printing out the compiled version of the `sin5` function:

    --output a prettified representation of what this function does
    sin5:printpretty() 
    > output:
    > sin50 = terra() : {double}
    >    return -0.95892427466314
    > end

Escapes can also return other Terra entities such as a function: 

    add4 = terra(a : int) return a + 4 end

    terra example()
        return [add4](3) -- 7
    end

In this case, Terra will insert a call to the Terra function stored in the `add4` variable:

    example:printpretty()
    > output:
    > example4 = terra() : {int32}
    >   return <extract0> #add43(3)#
    > end

In fact, _any_ name used in Terra code such as `add4` or `foo.bar` is treated as if it were escaped by default.

Inside an escape, you can refer to variables defined in Terra:

    --a function to be called inside an escape
    function choosesecond(a,b)
        -- prints false, 'a' is not a number:
        print(a == 1) 
        -- prints true, 'a' is a Terra symbol:
        print(terralib.issymbol(a))
        return b
    end

    terra example(input : int)
        var a = input
        var b = input+1
        --create an escape that refers to 'a' and 'b'
        return [ choosesecond(a,b) ] --returns the value of b
    end
    example(1) --returns 2

Since escapes are evaluated before a Terra function is compiled, variables `a` and `b` will not have concrete integer values inside the escape. Instead, inside the Lua code `a` and `b` are Terra _symbols_ that represent references to Terra values. Since `choosesecond` returns the symbol `b`, the `example` function will return the value of Terra variable `b` when called. 

The _quotation_ operator (a backtick) allows you to generate Terra statements and expression in Lua. They can then be spliced into Terra code using the escape operator.

    function addtwo(a,b)
        return `a + b
    end
    terra example(input : int)
        var a = input
        var b = input+1
        return [ addtwo(a,b) ]
    end
    example(1) -- returns 3

To generate statements rather than expressions you can use the `quote` operator:

    local printtwice = quote
        C.printf("hello\n")
        C.printf("hello\n")
    end
    terra print4()
        [printtwice]
        [printtwice]
    end

---

### Compiling a Language ###

With these two operators, you can use Lua to generate _arbitrary_ Terra code at compile-time. This makes the combination of Lua/Terra well suited for writing compilers for high-performance domain-specific languages. For instance, we can implement a _compiler_ for [BF](http://en.wikipedia.org/wiki/Brainfuck), a minimal language that emulates a Turing machine. The Lua function `compile` will take a string of BF code, and a maximum tape size `N`. It then generates a Terra function that implements the BF code. Here is a skeleton that sets up the BF program:

    local function compile(code,N)
        local function body(data,ptr)
            --<<implementation of body>>
        end
        return terra()
            --an array to hold the tape
            var data : int[N]
            --clear the tape initially
            for i = 0, N do
                data[i] = 0
            end
            var ptr = 0
            --generate the code for the body
            [ body(data,ptr) ]
        end
    end
    

The function `body` is responsible for generating body of the BF program given the code string:

    local function body(data,ptr)
        --the list of terra statements that make up the BF program
        local stmts = terralib.newlist()

        --loop over each character in the BF code
        for i = 1,#code do
            local c = code:sub(i,i)
            local stmt
            --generate the corresponding Terra statement
            --for each BF operator
            if c == ">" then
                stmt = quote ptr = ptr + 1 end
            elseif c == "<" then
                stmt = quote ptr = ptr - 1 end
            elseif c == "+" then
                stmt = quote data[ptr] = data[ptr] + 1 end
            elseif c == "-" then
                stmt = quote data[ptr] = data[ptr] - 1 end
            elseif c == "." then
                stmt = quote C.putchar(data[ptr]) end
            elseif c == "," then
                stmt = quote data[ptr] = C.getchar() end
            elseif c == "[" then
                error("Implemented below")
            elseif c == "]" then
                error("Implemented below")
            else
                error("unknown character "..c)
            end
            stmts:insert(stmt)
        end
        return stmts
    end

It loops over the code string, and generates the corresponding Terra code for each character of BF (e.g. ">" shifts the tape over by 1 and is implemented by the Terra code `ptr = ptr + 1`). We can now compile a BF function:

    add3 = compile(",+++.")

The result, `add3`, is a Terra function that adds3 to an input character and then prints it out:

    add3:printpretty()
    > bf_t_46_1 = terra() : {}
    > var data : int32[256]
    > ...
    > var ptr : int32 = 0
    > data[ptr] = <extract0> #getchar()#
    > data[ptr] = data[ptr] + 1
    > data[ptr] = data[ptr] + 1
    > data[ptr] = data[ptr] + 1
    > <extract0> #putchar(data[ptr])#
    > end

We can also use `goto` statements (`goto labelname`) and labels (`::labelname::`) to implement BF's looping construct:


    local function body(data,ptr)
        local stmts = terralib.newlist()
        
        --add a stack to keep track of the beginning of each loop
        local jumpstack = {}
        
        for i = 1,#code do
            local c = code:sub(i,i)
            local stmt
            if ...
            elseif c == "[" then
                --generate labels to represent the beginning 
                --and ending of the loop
                --the 'symbol' function generates a globally unique
                --name for the label
                local target = { before = symbol(), after = symbol() }
                table.insert(jumpstack,target)
                stmt = quote 
                    --label for beginning of the loop
                    ::[target.before]:: 
                    if data[ptr] == 0 then
                        goto [target.after] --exit the loop
                    end
                end
            elseif c == "]" then
                --retrieve the labels that match this loop
                local target = table.remove(jumpstack)
                assert(target)
                stmt = quote 
                    goto [target.before] --loop back edge
                    :: [target.after] :: --label for end of the loop
                end
            else
                error("unknown character "..c)
            end
            stmts:insert(stmt)
        end
        return stmts
    end

We are using these generative programming constructs to implement domain-specific languages and auto-tuners. Our [PLDI paper](/publications.html) describes our implementation of Orion, a language for image processing kernels, and we are in the process of porting the [Liszt language](http://liszt.stanford.edu) for mesh-based PDE's to Terra.

---

Embedding and Interoperability
------------------------------

Programming languages don't exist in a vacuum, and the generative programming features of Terra can be useful even in projects that are primarily implemented in other programming languages. We make it possible to integrate Terra with other projects so you can use it to generate low-level code, while keeping most of your project in a well-established language. 

First, we make it possible to pass values between Lua and Terra. Our implementation is built on top of LuaJIT's [foreign fuction interface](http://luajit.org/ext_ffi_tutorial.html). You can call Terra functions directly from Lua (or vice-versa), and access Terra objects directly from Lua (more details in the [API reference](/api.html#converting-between-lua-values-and-terra-values)). 

Furthermore, Lua-Terra is backwards compatible with both pure Lua and C, which makes it easy to use preexisting code. In Lua-Terra, you can use `require` or `loadfile` and it will treat the file as a Lua program (use `terralib.loadfile` to load a combined Lua-Terra file). You can use `terralib.includec` to import C functions from already existing header files.

Finally, Lua-Terra can also be _embedded_ in pre-existing applications by linking the application against `libterra.a` and using Terra's C API. The interface is very similar to that of the [Lua interpreter](http://queue.acm.org/detail.cfm?id=1983083). A simple example initializes Terra and then runs code from the file specified in each argument:

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
                exit(1);
        return 0;
    }

---

Simplicity
----------

The combination of a simple low-level language with a simple dynamic programming language means that many built-in features of statically-typed low-level languages can be implemented as libraries in the dynamic language. Here are just a few examples:

### Conditional Compilation ###
   
Normally conditional compilation is accomplished using preprocessor directives (e.g., `#ifdef`),
or custom build systems. Using Lua-Terra, we can write Lua code to decide how to construct a Terra function.
Since Lua is a full programming language, it can do things that most preprocessors cannot, such as call external programs.
In this example, we conditionally compile a Terra function differently on OSX and Linux by first calling `uname` to discover
the operating system, and then using an `if` statement to instantiate a different version of the Terra function depending on the result: 

    --run uname to figure out what OS we are running
    local uname = io.popen("uname","r"):read("*a")
    local C = terralib.includec("stdio.h")

    if uname == "Darwin\n" then
        terra reportos()
            C.printf("this is osx\n")
        end
    elseif uname == "Linux\n" then
        terra reportos()
            C.printf("this is linux\n")
        end
    else
        error("OS Unknown")
    end

    --conditionally compiled to 
    --the right version for this os
    reportos()

---

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

---

### Templating ###

Since Terra types and functions are first class values, you can get functionality similar to a C++ template by simply creating a Terra type and defining a Terra function _inside_ of a Lua function. Here is an example where we define the Lua function `MakeArray(T)` which takes a Terra type `T` and generates an `Array` object that can hold multiple `T` objects (i.e. a simple version of C++'s `std::vector`).

    
    C = terralib.includec("stdlib.h")
    function MakeArray(T)
        --create a new Struct type that contains a pointer 
        --to a list of T's and a size N
        local struct ArrayT {
            --&T is a pointer to T
            data : &T;
            N : int;
        } 
        --add some methods to the type
        terra ArrayT:init(N : int)
            -- the syntax [&T](...) is a cast,
            -- the C equivalent is (T*)(...)
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
        var ia : IntArray
        var da : DoubleArray
        ia:init(1) 
        da:init(1)
        ia:set(0,3)
        da:set(0,4.5)
        return ia:get(0) + da:get(0)
    end

As shown in this example, Terra allows you to define methods on `struct` types.
Unlike other statically-typed languages with classes, there are no built-in mechanisms for inheritance or runtime polymorphism.
Methods declarations are just a syntax sugar that associates table of Lua methods with each type. Here the `get` method is equivalent to:

    ArrayT.methods.get = terra(self : &T, i : int)
        return self.data[i]
    end

The object `ArrayT.methods` is a Lua table that holds the methods for type `ArrayT`.

Similarly an invocation such as `ia:get(0)` is equivalent to `T.methods.get(&ia,0)`.

---

### Specialization ###
    
By nesting a Terra function inside a Lua function, you can compile different versions of a function. Here we generate different versions
of the power function (e.g. pow2, or pow3):
    
    --generate a power function for a specific N (e.g. N = 3)
    function makePowN(N)
        local function emit(a,N)
            if N == 0 then return 1
          else return `a*[emit(a,N-1)]
          end
        end
        return terra(a : double)
            return [emit(a,N)]
        end
    end

    --use it to fill in a table of functions
    local mymath = {}
    for n = 1,10 do
        mymath["pow"..n] = makePowN(n)
    end
    print(mymath.pow3(2)) -- 8

---

### Class Systems ###

As shown in the templating example, Terra allows you to define methods on `struct` types but does not provide any built-in mechanism for inheritance or polymorphism. Instead, normal class systems can be written as libraries.  For instance, a user might write:

    J = terralib.require("lib/javalike")
    Drawable = J.interface { draw = {} -> {} }
    struct Square { length : int; }
    J.extends(Square,Shape)
    J.implements(Square,Drawable)
    terra Square:draw() : {}
        --draw implementation
    end

The functions `J.extends` and `J.implements` are Lua functions that generate the appropriate Terra code to implement a class system. More information is available in our [PLDI Paper](/publications.html). The file [lib/javalike.t](https://github.com/zdevito/terra/blob/master/tests/lib/javalike.t) has one possible implementation of a Java-like class system, while the file [lib/golike.t](https://github.com/zdevito/terra/blob/master/tests/lib/golike.t) is more similar to Google's Go language.


# Release 1.0.0 (????-??-??)

This release recognizes what has already been true for quite some time: Terra
is mature and has been tested in a variety of production environments. As a
result, the version numbers are changing with this release to follow
[SemVer](https://semver.org/), starting with version number 1.0. Terra is
expected to remain at 1.x for the forseeable future.

The following changes are included in this release:

## Added features

  * Support for LLVM 3.8, 3.9, 5 and 6
  * Support for CUDA 9.2
  * Support for Visual Studio 2015 on Windows
  * Upgrade to LuaJIT 2.0.5 by default, experimental support for 2.1 betas
  * Added `terralib.linkllvmstring` to link bitcode modules directly from memory
  * Allow types defined via `ffi.cdef` to be used as Terra types as well
  * Support for "module" definitions in ASDL, which allow ASTs to be namespaced
  * Added command line flag `-e` to evaluate a Terra expression
  * Added `terralib.version` which contains the version string, or `unknown` if this can't be detected
  * Added `optimize` flag to `terralib.saveobj` to optionally disable LLVM optimizations for better compile times

## Changed behaviors

  * Errors are printed to stderr instead of stdout

## Infrastructure improvements

  * Automated tests with Travis (Linux, macOS) and AppVeyor (Windows)
  * Automated release build infrastructure

## Bug fixes

  * Fixes for nontemporal loads and stores
  * Fixes for link errors due to multiple definitions of internal functions in different modules
  * Fixes for Windows default include path handling
  * Fix errors in parsing constants from macros
  * Fix bugs in constant checking
  * Fix auto-detection of AVX support
  * Fixes for building on FreeBSD
  * Fix auto-detection of library type when file name ends in `[^.]bc`

## Experimental features

  * Experimental support for CMake-based build system

# Release 2016-03-25

This new release of Terra brings some changes to the language and APIs
designed to simplify the language and improve error reporting. These changes
were based on the experiences of developing DSLs with Terra such as
[Darkroom](http://darkroom-lang.org), [Ebb](http://ebblang.org), and
[Regent](http://regent-lang.org), which gave us a better idea of how the
language will be used and what problems crop up in larger systems.

In our experience, Terra code only requires minor changes to make it work with
this new release, but feel free to email this list if you run into a situation
where an update would not be trivial. Looking at the difference in the [unit
tests](https://github.com/zdevito/terra/tree/master/tests) is useful to see
where APIs and syntax have changed for particular features.

More detailed notes about the changes are below.

## 'Eager' Typechecking

### Change

This release changes when typechecking of Terra functions and quotations
occurs. Previously, typechecking was done 'lazily', that is, it ran right
before a Terra function was actually used. Instead, the current version
typechecks eagerly --- immediately when a function or quotation is
defined. This includes all meta-programming such as evaluating escapes and
running macros.

### Rationale

The original 'lazy' design had some advantages. For instance, it allowed for a
flexible order to when things were defined. A function could call a Terra
method before that method was declared by the struct being used. However, we
have found those advantages are outweighted by disadvantages. In lazy
typechecking, errors tended to get reported very far from the creation of the
statement that caused them, slowing debugging. It also complicated
meta-programming, a core aspect of Terra. When constructing Terra expressions
like the quotation `a + b, it could be useful to know what the type of the
resulting expression would be. With lazy typechecking, they type is not known
when the quote is constructed. It can be difficult to figure out the type of`a
+ b`from the types of`a`and`b` without duplicating much of Terra's
typechecking rules. While, we allowed a work-around that deferred
meta-programming to typechecking time by using a macro, it only complicated
the process.

These problems are resolved in the current release with eager
typechecking. Type errors are immediately reported when a function definition
or quotation is created, making it easier to debug. The type of a quotation is
also always availiable of use during metaprogramming:

```
local function genadd(a,b)
    local sum = `a + b
    print("the type of sum is",sum:gettype())
    -- use the type to do whatever you want
    return sum
end
terra foo()
    var d = 1.5
    var i = 1
    var d = [sum(d,i)] -- the type of sum is double
    var i = [sum(i,i)] -- the type of sum is int
end
```

### Ramifications to existing code

#### Function Declaration/Definition

The major ramification of this change is that functions must be declared with
a type before they are used in code, and that structs must be defined before
being used in code. This is similar to the behavior of C/C++. To prevent
everything from needing to be defined in a strict order, we allow continuous
declarations/definitions to be processed simultaneously. Any sequence of
declarations or definitions of terra structs and functions are now processed
simultaneously:

```
terra PrintReal(a : double)
    C.printf("%d ",a)
end
terra PrintComplex(c : Complex)
    C.printf("Complex ")
    PrintReal(c.real)
    PrintReal(c.imag)
end
struct Complex { real : double, imag : double }
print("lua code")
terra secondunit()
```

In this case the declarations of Complex, PrintComplex, and PrintReal are
processed first, followed by the definitions. Any interleaving Lua code, like
the 'print' statement breaks up a declaration block. Previously this behavior
was only possible using the 'and' keyword. Now this behavior is the default
and the 'and' syntax has been removed.

Since typechecking is eager, function _declarations_ now require types:

```
local terra PrintReal :: double -> {}
terra Complex:add :: {Complex,Complex} -> Complex
```

(The double colon, ::, is necessary to avoid a parser ambiguity with method definitions)

#### Symbols

Since typechecking is eager, Symbols must always be constructed with types so
their types are known when used in quotations. The `type` argument to the
`symbol(type,[name])` function is no longer optional and will report an error
if omitted. To get a unique label for struct members, method name, or goto
labels, the `label([name])` function has been added. Symbols and Labels are
now distinct concepts. Symbols always have types and represent a unique name
for a Terra expression, while Labels never have a type and represent a unique
name for a labels.

Furthermore, since Symbols always have types, the optional type annotations
for escaped variable declarations have been removed:

```
local a = symbol(int,"a")
terra foo([a]) --ok
end
terra foo([a]:int) -- syntax error, symbol 'a' always has a type making the annotation redundant
end
```

#### APIs

Certain APIs for handling the consequences of lazy typechecking such as
`:peektype` have been removed. `:printpretty` only takes a single argument
since expressions are always type.

## Improved Error Reporting

In addition to having type errors occur earlier, the quality of error
reporting has improved. Previously, if used-defined code such as an escape,
macro, or type annotation resulted in an error, the typechecker would try to
recover and continue generating type errors for the rest of a function. This
resulted in long inscrutable error messages.

The new error reporting system does not attempt to recover in these cases and
instead reports a more meaningful error message with a full stack trace that
includes what the typechecker was checking when the error occurred.

error.t:

```
local function dosomething(a)
    error("NYI - dosomething")
end
local function dosomethingmore(a)
    local b = dosomething(a)
    return `a + b
end

terra foo(d : int)
    var c = [dosomethingmore(d)]
    return c
end
```

message:

```
error.t:2: NYI - dosomething
stack traceback:
    [C]: in function 'error'
    error.t:2: in function 'dosomething'
    error.t:5: in function 'userfn'
    error.t:10: Errors reported during evaluating Lua code from Terra
        var c = [dosomethingmore(d)]
                               ^
    /Users/zdevito/terra/src/terralib.lua:1748: in function 'evalluaexpression'
    /Users/zdevito/terra/src/terralib.lua:2772: in function 'docheck'
    /Users/zdevito/terra/src/terralib.lua:2983: in function 'checkexp'
    /Users/zdevito/terra/src/terralib.lua:2510: in function 'checkexpressions'
    /Users/zdevito/terra/src/terralib.lua:3150: in function 'checksingle'
    /Users/zdevito/terra/src/terralib.lua:3184: in function 'checkstmts'
    /Users/zdevito/terra/src/terralib.lua:3079: in function 'checkblock'
    /Users/zdevito/terra/src/terralib.lua:3268: in function 'typecheck'
    /Users/zdevito/terra/src/terralib.lua:1096: in function 'defineobjects'
    error.t:9: in main chunk
```

The error reporting system also does a better job at accurately reporting line
numbers for code that exists in escapes.

## Constant Expressions and Initializers

Terra Constants generated with `constant([type],[value])` can now be defined
using Terra quotations of _constant expressions_:

```
local complexobject = constant(`Complex { 3, 4 })
```

Constant expressions are a subset of Terra expressions whose values are
guaranteed to be constant and correspond roughly to LLVM's concept of a
constant expression. They can include things whose values will be constant
after compilation but whose value is not known beforehand such as the value of
a function pointer:

```
terra a() end
terra b() end
terra c() end
-- array of function pointers to a,b, and c.
local functionarray = const(`array(a,b,c))
```

The global initializer to a `global()` variable can also be a constant
expression now and can be reassigned until the global is actually compiled
using `:setinitializer`.

## Separate Overloaded and non-Overloaded Functions

Previously, it was possible for any Terra function to have multiple
definitions, which would cause it to become an overloaded function. However,
there are many cases where a function with a single definition is needed such
as saving an object (.o) file, generating a function pointer, and
unambiguously calling a Terra function from Lua.

In this release, terra functions are single-defintion by default. Another
definition overrides the previous one.

Overloaded functions are still possible using a separate object:

```
local addone = terralib.overloadedfunction("addone",
               { terra(a : int) return a + 1 end,
                 terra(a : double) return a + 1 end })
-- you can also add methods later
addone:adddefinition(terra(a : float) return a + 1 end)
```

This fixes the worst problem caused by overloaded functions.  On the REPL,
defining a new version of a function simply added another definition to the
previous function rather than overwriting it:

```
> terra foo() return 1 end
> terra foo() return 2 end
> terra useit() foo() end --old behavior: function is ambiguously defined
                          --new behavior: returns 2
```

API changes reflect the fact that functions only have a single definition. For
flexibility, we allow the definition of an already defined function to be
changed using `:resetdefinition` as long as it has not already been output by
the compiler.

## Calling Lua Functions from Terra

A common inscrutable error was accidentally calling a a Lua function from
Terra when that function was meant to be escaped, or was intended to be a
macro. To avoid this situation, we reject attempts to call Lua functions
directly. Instead, they must now be cast to a terra function first with
`terralib.cast`:

```
local tprint = terralib.cast({int}->{},print)
terra foo()
    tprint(4)
end
```

If you want the old behavior, you can recreate it using macros:

```
local function createluawrapper(luafn)
    local typecache = {}
    return macro(function(...)
        local args = terralib.newlist {...}
        local argtypes = args:map("gettype")
        local fntype = argtypes -> {}
        if not typecache[fntype] then
            typecache[fntype] = terralib.cast(fntype,luafn)
        end
        local fn = typecache[fntype]
        return `fn([args])
    end)
end

local tprint = createluawrapper(print)
terra test()
    tprint(1,2,3.5)
    tprint(1)
    tprint(2)
end

test()
```

## Abstract Syntax Description Language (ASDL)

Compiler internals in Terra have been changed to use the Zephyr [Abstract
Syntax Description Language
(ASDL)](http://www.cs.princeton.edu/research/techreps/TR-554-97), which is
also used internally in the CPython implementation.

A require-able Lua package "asdl" provides this library to users so that they
can also use ASDL to create data-types to represent abstract-syntax trees and
intermediate representations in their own DSLs.

Using ASDL to represent Terra's internal ASTs will make it easier to write
backends in addition to LLVM that consume the AST.

## Other API Changes

`__for` meta-method behavior has been changed to be simpler.

# Release 2016-02-26

Bug fixes that resolve an issue with including C header files on some Linux
distributions

Support testing for NaN's with `a ~= a`

Additional tests for performance regression.

Implementation of `lexer:luastats()`, `lexer:terraexp()` and
`lexer:terrastats()` in parser extension interface.

# Release 2015-08-03

Bug fixes for including C header files and their interaction with cross
compilation.

Bug fix to avoid adding Clang resource directory on Windows builds.

# Release 2015-07-21

This release has two major changes.

  * Support for cross-compilation. Functions like `terralib.saveobj` can now
    emit code for non-native architectures see the documentation at
    http://terralang.org/api.html for more information.

  * Support for stand-alone static linking. It is now possible to link against
    a static `libterra.a` that includes everything you need to run Terra
    include the right LuaJIT and LLVM code. The library itself has no external
    dependencies on the filesystem.

# Release 2015-03-12

Added ability to compile CUDA code for offline use.

# Release 2015-03-03

Releases for OSX 10.10, Ubuntu 14.04, and Windows 8

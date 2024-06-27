# Release 1.2.0 (2024-06-25)

This release adds new LLVM versions and introduces experimental support for SPIR-V code generation. Note that as of the tested LLVM versions, LLVM's native SPIR-V backend is unable to generate correct SPIR-V code in all cases; but the LLVM SPIR-V target can still be used in combination with the [LLVM/SPIR-V Translator](https://github.com/KhronosGroup/SPIRV-LLVM-Translator) to generate valid code.

Users who generate code for AMD GPUs are strongly encouraged to upgrade to LLVM 18 and ROCm 6.0.0, as previous version combinations generate bad code to varying degrees.

## Added features

  * Support for LLVM 17 and 18
  * Experimental support for SPIR-V code generation (e.g., for Intel GPUs)

## Fixed Bugs

  * Updated LuaJIT to obtain fix for passing large arrays on macOS M1

## Removed features

  * Removed support for LLVM <= 10
  * Removed the long-deprecated Makefile build

# Release 1.1.1 (2023-08-22)

This is a bug fix release that addresses a miscompilation related to
globals imported from C.

## Fixed Bugs

  * Fixed miscompilation of nested arrays included via C headers.

# Release 1.1.0 (2023-05-05)

This release brings Terra up to date with LLVM releases and deprecates/removes
some older LLVM versions. No breaking changes are expected.

## Added features

  * Support for LLVM 15 and 16

## Improvements

  * Fixes for WASM calling convention
  * Fixes for tests on macOS 13
  * Fixes for 32-bit ARM on Linux (note this configuration is still experimental)
  * Verify SHA-256 hashsums of all downloads in CMake build

## Deprecated features

  * Deprecated support for LLVM <= 10

## Removed features

  * Removed support for LLVM <= 5

# Release 1.0.6 (2022-09-06)

This release stabilizes support for macOS M1 (AArch64). Terra now
passes 100% of the test suite on this hardware.

## Changed behaviors

  * Terra previously allowed `terralib.atomicrmw("xchg", ...)` to be
    used with pointers. This was a mistake; LLVM does not allow this
    and LLVM IR with this instruction is invalid. Terra now correctly
    issues a type error in this situation.

## Improvements

  * Fixes for macOS on M1 hardware, allowing Terra to pass 100% of the
    test suite.
  * Automated testing is now performed regularly on PPC64le hardware.

# Release 1.0.5 (2022-08-16)

This release stabilizes support for ARM (AArch64). On a variety of
hardware (Graviton, NVIDIA Jetson), Terra now passes 100% of the test
suite.

## Improvements

  * Fixes for multiple issues on AArch64, allowing Terra to pass 100%
    of the test suite.
  * Updated LuaJIT to obtain fixes for AArch64.

## Known Issues

  * On AArch64, Terra requires LLVM 11 or older. Newer LLVM versions
    result in segfaults on some tests.

# Release 1.0.4 (2022-07-08)

This release stabilizes support for PPC64le. On POWER9 hardware, Terra
now passes 100% of the test suite. This comes with one large caveat:
Terra relies on Moonjit, a fork of LuaJIT, for support for PPC64le. At
the time of this release, Moonjit is currently unsupported. Therefore,
while Terra provides comprehensive support for PPC64le, we are not in
a position to fix issues in the Moonjit implementation.

## Improvements

  * Fixes for multiple issues on PPC64le, allowing Terra to pass 100%
    of the test suite.

# Release 1.0.3 (2022-07-01)

This release contains no feature changes, but includes bug fixes for
the Terra calling convention on PPC64le for passing arrays by value.

## Improvements

  * Fixes for the Terra calling convention on PPC64le for passing
    arrays by value.

# Release 1.0.2 (2022-06-25)

This release includes improvements to make Terra better match Unix-like system
conventions, as well as substantial improvements to C calling convention
conformance on PPC64le.

## Changed behaviors

  * Terra historically installed its shared library as `terra.so` or
    `terra.dylib` on Unix-like systems. This is for compatibility with Lua,
    which allows a module be loaded as `require("terra")` if `terra.so` (or
    `terra.dylib`, depending on the system) is present. However, this
    conflicts with the Unix standard of having libraries prefixed with
    `lib`. In this release, Terra installs its shared library as `libterra.so`
    or `libterra.dylib`, and installs a symlink for `terra.so` or
    `terra.dylib` for backwards compatibility. (Behavior on Windows and with
    static libraries is unchanged.)

## Improvements

  * Substantially improved C calling convention conformance on PPC64le, along
    with a new conformance test that matches behavior against C for all
    primitive types (`uint8`, `int16`, `int32`, ...) and structs/arrays of
    those types, up to a bound. Successfully tested on POWER9 hardware up to
    `N` = 23. Current test suite pass rate on this hardware is 98.5%.

# Release 1.0.1 (2022-06-13)

This release includes no major Terra changes, but upgrades the LuaJIT
dependency and makes available (experimental) binaries for ARM64 and
PPC64le.

## Changed behaviors

  * The default Lua has been set back to LuaJIT for all platforms other than
    PPC64le (where it is still set to Moonjit). As before, this can be
    configured explicitly with the CMake flag `-DTERRA_LUA` with either
    `luajit` or `moonjit`

## Experimental features added

  * Binary builds for ARM64 and PPC64le. These platforms were already possible
    to build from source, but this makes them easier to try out. Note the test
    suite pass rate is about 96% for ARM64 and 98% for PPC64le. You mileage
    may vary depending on what features of Terra you use

# Release 1.0.0 (2022-06-08)

This release recognizes what has already been true for quite some
time: Terra is mature and has been tested in a variety of production
environments. As a result, the version numbers are changing with this
release to follow our [stability policy](STABILITY.md), starting with
version number 1.0.0. Terra is expected to remain at 1.x for the
forseeable future.

The following changes are included in this release:

## Added features

  * Support for LLVM 3.8, 3.9, 5, 6, 7, 8, 9, 10, 11, 12, 13 and 14
  * Support for CUDA 9, 10 and 11
  * Support for Visual Studio 2015, 2017, 2019 and 2022 on Windows
  * Support for FreeBSD
  * New CMake-based build system replaces Make/NMake on all platforms
  * Upgrade to LuaJIT 2.1 (from Git) by default
  * Added optional support for Moonjit, a LuaJIT fork that works on PPC64le
  * Added `terralib.linkllvmstring` to link bitcode modules directly from memory
  * Allow types defined via `ffi.cdef` to be used as Terra types as well
  * Support for "module" definitions in ASDL, which allow ASTs to be namespaced
  * Added command line flag `-e` to evaluate a Terra expression
  * Added `terralib.version` which contains the version string, or `unknown` if this can't be detected
  * Added `optimize` flag to `terralib.saveobj` to specify an optimization profile. Currently optimization profiles can be used to disable optimizations, or to enable fast-math flags
  * Added support for all fast-math optimizations supported by LLVM
  * Added support for `:setcallingconv()` on Terra functions to set the calling convention (with any supported LLVM calling convention)

## Experimental features added

  * Added `terralib.atomicrmw` to support atomic read-modify-write operations
  * Added `terralib.fence` to support fence operations
  * Added `switch` statement
  * Added support for AMD GPU code generation (with LLVM 13 and up)
  * Added support for Nix derivation, and merged upstream into NixOS

## Deprecated features

  * Deprecated support for Make (Linux, macOS, FreeBSD) build system
  * Deprecated support for LLVM 3.8, 3.9 and 5

## Removed features

  * Removed support for all LLVM versions 3.7 and prior
  * Removed support for NMake (Windows) build system

## Changed behaviors

  * Errors are printed to stderr instead of stdout

## Infrastructure improvements

  * Automated tests with GitHub Actions (Linux, macOS, Windows), Cirrus (FreeBSD) and AppVeyor (Windows)
  * Automated tests for various Linux distros (currently Ubuntu 18.04, 20.04, 22.04) via Docker
  * Automated Linux "compability" tests (cross-distro-version tests for binary compatibility)
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
  * Fixes for PPC64le
  * Fixes for AMD GPU
  * Fixes for performance regressions in NVIDIA CUDA code generation in LLVM 13 (as compared to LLVM 3.8, the last release that supported NVVM)

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
tests](https://github.com/terralang/terra/tree/release-2016-03-25/tests) is useful to see
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
    .../terra/src/terralib.lua:1748: in function 'evalluaexpression'
    .../terra/src/terralib.lua:2772: in function 'docheck'
    .../terra/src/terralib.lua:2983: in function 'checkexp'
    .../terra/src/terralib.lua:2510: in function 'checkexpressions'
    .../terra/src/terralib.lua:3150: in function 'checksingle'
    .../terra/src/terralib.lua:3184: in function 'checkstmts'
    .../terra/src/terralib.lua:3079: in function 'checkblock'
    .../terra/src/terralib.lua:3268: in function 'typecheck'
    .../terra/src/terralib.lua:1096: in function 'defineobjects'
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

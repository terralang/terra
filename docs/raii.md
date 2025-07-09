# Deterministic Automated Resource Management
Resource management in programming languages generally falls into one of the following categories:

1. **Manual allocation and deallocation**
2. **Automatic garbage collection**
3. **Automatic scope-bound resource management** (commonly referred to as [RAII](https://en.wikipedia.org/wiki/Resource_acquisition_is_initialization), or *Resource Acquisition Is Initialization*).

Traditionally, Terra has only supported manual, C-style resource management. While functional, this approach limits the full potential of Terra’s powerful metaprogramming capabilities. To address this limitation, the current implementation introduces **automated resource management**.

---

## Scope-Bound Resource Management (RAII)
The new implementation provides **scope-bound resource management (RAII)**, a method typically associated with systems programming languages like C++ and Rust. With RAII, a resource's lifecycle is tied to the stack object that manages it. When the object goes out of scope and is not explicitly returned, the associated resource is automatically destructed.

### Examples of Resources Managed via RAII:
- Allocated heap memory
- Threads of execution
- Open sockets
- Open files
- Locked mutexes
- Disk space
- Database connections

---

## Experimental Implementation Overview
The Terra implementation supports the [Big Five](https://en.wikipedia.org/wiki/Rule_of_three_(C++_programming)#Rule_of_five)
1. **Object destruction**
2. **Copy assignment**
3. **Copy construction**
4. **Move assignment**
5. **Move construction**

However, we use a simpler model compared to C++11 with convenient and efficient defaults at the expense of some flexibility. For example, **rvalue references** (introduced in C++11) are not supported in Terra. The implementation is much closer to that of Rust.

### Design Overview
* No Breaking Changes: This implementation does not introduce breaking changes to existing Terra code. No new keywords are required, ensuring that existing syntax remains compatible.
* Type Checking Integration: These methods are introduced during the type-checking phase (handled in `terralib.lua`). They can be implemented as either macros or Terra functions.
* Composability: The implementation follows simple, consistent rules that ensure smooth compatibility with existing Terra syntax for construction, casting, and function returns.
* Heap resources: Heap resources are allocated and deallocated using standard C functions like malloc and free, leaving memory allocation in the hands of the programmer. The idea here is that remaining functionality, such as allocators, are implemented as libraries.

RAII is currently an experimental feature and thus must be enabled explicitly. In a future version of Terra, this may be enabled by default.

### Core Concepts:
Compiler support is provided for the following methods:
| Feature                                      | Description                                                                 |
|----------------------------------------------|-----------------------------------------------------------------------------|
| `A.methods.__init(self : &A)`                  | Optionally user-implemented, auto-generated with memory zero-initialized. |
| `A.methods.__dtor(self : &A)`                  | User-implemented, auto-generated for aggregates with managed fields.                |
| `(A or B).methods.__copy(from : &A, to : &B)`  | User-implemented, auto-generated for aggregates with copyable fields.               |
| `A.methods.__move(from : &A, to : &A)`         | Auto-generated to handle move semantics for resource transfer.        |
| `__move__`                                     | Prefer `__move` over `__copy` for efficient resource transfer.               |
| `__handle__`                                   | Get a handle to a managed object without transferring ownership. Performs an allocation.             |

These methods facilitate the implementation of smart containers and pointers, such as `std::string`, `std::vector` and `std::unique_ptr`, `std::shared_ptr` in C++.

#### Managed types
A struct is managed if it implements `__dtor`. Managed types require explicit resource cleanup (e.g., freeing heap memory). Without `__dtor`, a type behaves as a regular stack-allocated object with no special management.

#### Copyable types
A type is copyable if:
1. It is a primitive type (e.g., `int`, `double`), a `vector` type or a function pointer.
2. An unmanaged struct with copyable fields.
3. It is a managed struct with a `__copy` method that is either:
    * User-defined;
    * Auto-generated for aggregates where all fields are copyable.
4. An array with a copyable element type.

It's easier to remember the types that are not copyable:
1. Pointer types, excluding function pointers.
2. Managed struct types that do not implement a `__copy` method, with at least one non-copyable field.

#### Movable types
Unmanaged types are generally moveable: the auto-generated implementation invokes `memcpy`. A managed type is movable if it can be transferred via a move. Key rules:
1. All managed types (those with `__dtor`) are movable by default.
2. A type `T` can be made immovable by deleting the (auto-generated) `__move` method.

For managed types the move from a source to a receiver is implemented as follows: (1) the reciever's `__dtor` is called first, followed by (2) a memcopy from source to receiver and (3) subsequent re-initialization of the source.

### Ownership model
The new ownership model ensures every resource has exactly one owner at any time, akin to Rust’s single-ownership principle, preventing data races, dangling pointers, and double-free errors. This model guarantees safety in sequential and shared memory parallel contexts through strict resource transfer and access rules.

#### L-values, R-values, and B-values
Similar to other languages, Terra provides several distinct kinds of values.
* L-values: values explicitly allocated with a `var` statement (e.g., `var x : T` or `var x = ...`). They represent named, persistent objects with a defined lifetime.
* R-values: Temporary objects, typically resulting from function calls. They are short-lived and exist only within their expression.
* B-values: Reference objects (`&T`), enabling borrowing. They allow the caller to retain ownership while the callee operates on the resource without transferring it.

#### Passing by value or by reference
Passing managed objects to functions or in an assignment can be done in two ways:
1. By value: Transfers ownership to the receiver.
    - L-values: Use the `__copy` method if defined, duplicating the resource. If `__copy` is not defined, or the `__move__` directive, e.g. `__move__(a)`, is used then ownership is transferred via the (auto-generated) `__move`. 
    - R-values: Always transfer ownership using the (auto-generated) `__move`.
2. By reference (B-values): Grants temporary access via `&T`. No ownership transfer occurs; the original owner retains responsibility for cleanup via `__dtor`.

#### Planned safety features
The single-ownership model opens the door to future compile-time verification of resource safety for sequential and parallel programs. The following enhancements are planned to strengthen this model:

1. **Initialization Tracking:**
    - Tracks variable initialization at compile time.
    - Flags use of uninitialized variables (e.g., after a move) as compile errors.
    - Skips `__dtor` for uninitialized objects, improving safety and efficiency.

2. **Constant References (`const&`):** 
    - Enforces read-only access (`const& T`) recursively at compile time.
    - Allows safe, unsynchronized sharing in parallel programs.

---

## Details about Implementation with Examples
A managed type is one that implements at least `__dtor` and optionally `__init` and `__copy` or, by induction, has fields or subfields that are of a managed type. In the following we assume `struct A` is a managed type.

To enable RAII, import the library `lib/terralibext.t` using:
```terra
require "terralibext"
```
The compiler only checks for `__init`, `__dtor` and `__copy` in case this library is loaded.

### Object initialization
`__init` is used to initialize managed variables:
```
A.methods.__init(self : &A)
```
The compiler checks for an `__init` method in any variable definition statement that does not have an explicit initializer, and emits the call right after the variable definition. E.g.:
```
var a : A
```
becomes
```
var a : A
a:__init()    --generated by compiler
```
Managed types, like `A`, alsways invoke a call to `__init`. If `A.methods.__init` is not implemented then the method will be auto-generated with zero-initialization of all fields. In contrast, non-managed struct types (i.e. those that don't implement `__dtor`) only schedule a call to `__init` in case `__init` is user-implemented.

#### Array initialization
If you have an array with an element type that is managed and implements a (possibly auto-generated) `__init` method, then the compiler will schedule an initializer call function that loops over the entries in the array and initializes the elements one-by-one.

### Copy assignment / construction
`__copy` enables specialized copy-assignment and, combined with `__init`, copy construction. `__copy` takes two arguments, which can be different, as long as one of them is a managed type. E.g.:
```
A.metamethods.__copy(from : &A, to : &B)
```
and / or
```
A.metamethods.__copy(from : &B, to : &A)
```
If `a : A` is a managed type, then the compiler will replace a regular assignment by a call to the implemented `__copy` method:
```
b = a   ---->   A.methods.__copy(&a, &b) 
```
or 
```
a = b   ---->   A.methods.__copy(&b, &a)
```
`__copy` can be a (overloaded) terra function or a macro.

The programmer is responsible for managing any heap resources associated with the arguments of the `__copy` method. This means that the destination variable's destructor should probably be called before copying data over from the source variable.

In object construction, `__copy` is combined with `__init` to perform copy construction. For example,
```
var b : B = a
```
is replaced by the following statements
```
var b : B
b:__init()                --generated by compiler
A.methods.__copy(&a, &b)  --generated by compiler
```

#### Call prioritization
If both `A` and `B` implement their own `__copy` method then the compiler will prioritize the method implementation associated with the left-hand-side in the assignment. Hence, for the assignment
```
a = b
```
where `a : A` and `b : B`, the compiler will look for all available implementations from the various options:
* `A.methods.__copy(from : &B, to: &A)` is a regular method
* `B.methods.__copy(from : &B, to: &A)` is a regular method
* `A.methods.__copy(from, to)` is a macro
* `B.methods.__copy(from, to)` is a macro
* `A.methods.__copy(from, to)` is an overloaded method
* `B.methods.__copy(from, to)` is an overloaded method
and will prioritize implementations associated with the type of the left-hand-side `A`. 

Normal casting rules apply to regular and overloaded methods. For example, if `methods.__copy(from : &B, to: &A)` is not implemented but `methods.__copy(from : &A, to: &A)` is and there exists a valid cast `&B -> &A`, then the compiler schedules the cast and a call to `__copy(from : &A, to: &A)`.

#### Array copy assignment / construction
If you have an array with a managed element type, then the compiler will schedule a function that loops over the entries in the array and copies the elements one-by-one.

### Move construction / assignment
If a `__copy` method is not implemented then resources are moved by default. So move construction:
```
var b : B = a
```
is replaced by
```
var b : B
b:__init()                  --generated by compiler
A.methods.__move(&a, &b)    --generated by compiler
```
Similarly, move-assignment:
```
b = a
```
is simply replaced by
```
A.methods.__move(&a, &b)    --generated by compiler
```
In contrast to `__copy`, which can be manually implemented (and thus customized) by the user, the `__move` method is always auto-generated by the compiler. This permits moves to be performed with `memcpy` in all cases and thus they have predictable performance and implementation characteristics.

#### Array move assignment / construction
If you have an array with a managed element type, then the compiler will schedule a function that loops over the entries in the array and moves the elements one-by-one.

#### Avoiding unnecessary copies
At times, when `__copy` is implemented, it may be useful to force a move to avoid unnecessary copies at specific statements. This can be achieved with the `__move__` compiler directive:
```
    b = a               -- `__copy` will be invoked
    b = __move__(a)     -- `__move` will be invoked
```

#### Avoiding ownership transfer
Sometimes it's useful to get a bitcopy of an object without any ownership transfer. We call this a handle. This is especially useful in the context of meta-programming using Terra macros. Here is an example:
```
local f = macro(function(x)
    return quote
        var z = __handle__(x) --provides a handle to x, no __dtor is scheduled.
        --hence, we can do some operations on the resource without a destructor
        --for `z` being called.
        ...
        ...
    end
end)
```
Oftentimes we can operate directly on `x`, but this is not always possible e.g. when `x` is an R-value. We can use `__handle__` to get an L-value that we can then use to modify the underlying resource, without taking ownership.

Use `__handle__` with caution and always check the generated code by compiling the macro within a function and using `printpretty()`.

### Object destruction
`__dtor` can be used to free heap memory:
```
A.methods.__dtor(self : &A)
```
The implementation adds a deferred call to `__dtor ` near the end of a scope, right before a potential return statement, for all variables local to the current scope that are not returned. Hence, `__dtor` is tied to the lifetime of the object. For example, for a block of code the compiler would generate
```
do
    var x : A, y : A
    ...
    ...
    defer x:__dtor()    --generated by the compiler
    defer y:__dtor()    --generated by the compiler
end
```
or in case of a terra function
```
terra foo(x : A)
    var y : A, z : A
    ...
    ...
    defer x:__dtor()    --generated by the compiler
    defer z:__dtor()    --generated by the compiler
    return y
end
```
Since `x` is passed by value it owns a resource and therefore needs to be destructed. By scheduling the deferred destructor calls before the return statement, rather then after a `var` statement, it's easy to schedule calls only for those values that are not returned. Also note that destructors will be called in reverse order of object creation, that is, first-in-last-out. 

Destructors are called in reverse order of object creation, that is, last-in, first-out (LIFO). Note that this is a property of the `defer` statement and thus the statements are shown above in first-in, first-out (FIFO) order, but they execute in the opposite order.
#### Destructor calls and return statements in nested scopes
In nested scopes with return statements all resources need to be cleaned up before the return. Consider the following contrived example. Note that deferred destructor calls are scheduled in order of object creation. When the stack is unwound in the return of the `if` block, first `f` is destroyed, then `e`, then `d`, etc. (Note: also recall that `defer` order execution is the reverse of its declaration, so innermost variables are destroyed first.)
```
terra f(x : A)
    var a : A
    var b : A
    var k = 0
    while true do
        var c : A
        var d : A
        if k == 5 then
            var e : A
            var f : A
            defer x:__dtor()    --generated by the compiler
            defer a:__dtor()    --generated by the compiler
            defer b:__dtor()    --generated by the compiler
            defer c:__dtor()    --generated by the compiler
            defer d:__dtor()    --generated by the compiler
            defer e:__dtor()    --generated by the compiler
            defer f:__dtor()    --generated by the compiler
            return k
        end
        var g : A
        var h : A
        defer c:__dtor()    --generated by the compiler
        defer d:__dtor()    --generated by the compiler
        defer g:__dtor()    --generated by the compiler
        defer h:__dtor()    --generated by the compiler
    end
    defer x:__dtor()    --generated by the compiler
    defer a:__dtor()    --generated by the compiler
    defer b:__dtor()    --generated by the compiler
    return 0
end
```

#### Destructor calls and break statements
Additionally, `__dtor` needs to behave correctly in a `break` statement in order to clean up resources from the current scope and any resources defined prior in the enclosing loop:
```
terra g(x : A)
    var a : A
    var b : A
    var k = 0
    while true do
        var c : A
        var d : A
        if k > 2 then
            var e : A
            var f : A
            defer c:__dtor()    --generated by the compiler
            defer d:__dtor()    --generated by the compiler
            defer e:__dtor()    --generated by the compiler
            defer f:__dtor()    --generated by the compiler
            break
        end
        var g : A
        var h : A
        k = k + 1
        defer c:__dtor()    --generated by the compiler
        defer d:__dtor()    --generated by the compiler
        defer g:__dtor()    --generated by the compiler
        defer h:__dtor()    --generated by the compiler
    end
    defer x:__dtor()    --generated by the compiler
    defer a:__dtor()    --generated by the compiler
    defer b:__dtor()    --generated by the compiler
end
```

#### Array destructors
If you have an array with an element type that is managed, then the compiler will schedule a destructor function that loops over the entries in the array and destructs the elements one-by-one.

## Compositional APIs
If a struct has fields that are managed types, but do not implement `__init`, `__copy` or `__dtor`, then the compiler will generate default methods that inductively call existing `__init`, `__copy` or `__dtor` methods for its fields. This enables compositional APIs like `vector(vector(int))` or  `vector(string)`. This is implemented as an extension to `terralib.lua` in `lib/terralibext.t`.

## Examples
The following files have been added to the Terra testsuite:

| File Name                     | Description                                                                   |
|-------------------------------|-------------------------------------------------------------------------------|
| raii-compose.t                | Tests composition of RAII objects.                                            |
| raii-copy-generation.t        | Verifies automatic generation of copy methods in RAII classes.                |
| raii-copy-vs-move-arrays.t    | Verifies copy and move semantics of RAII-array objects.                       |
| raii-copy-vs-move.t           | Verifies copy and move semantics of RAII objects.                             |
| raii-copyctr-cast.t           | Tests casting behavior in RAII copy constructors.                             |
| raii-copyctr.t                | Validates behavior of explicitly defined RAII copy constructors.              |
| raii-dtor-generation.t        | Checks automatic generation of destructors for RAII objects.                  |
| raii-dtor.t                   | Tests explicit destructor implementation for RAII resource cleanup.           |
| raii-init-generation.t        | Verifies automatic generation of initializers for RAII objects.               |
| raii-initializers.t           | Tests explicit initializer implementation in RAII classes.                    |
| raii-integration-copy.t       | Integration tests of RAII classes with focus on value semantics.              |
| raii-integration-move.t       | Integration tests of RAII classes with focus on move semantics.               |
| raii-meta.t                   | Tests use of RAII objects in macros.                                          |
| raii-shared_ptr.t             | Validates RAII with `shared_ptr` for shared resource ownership.               |
| raii-unique_ptr.t             | Tests RAII with `unique_ptr` for unique resource ownership.                   |
| raii-offset_ptr.t             | Tests RAII with offset-based pointer implementations.                         |
| raii.t                        | General tests for core RAII principles and functionality.                     |
| fails/raii-tuple-default-copy.t | Checks if tuple assignment is prohibited for managed moveable types         |
| fails/raii-tuple-custom-copy.t | Checks if tuple assignment is prohibited for managed copyable types          |

You can have a look there for some common code patterns. Useful, in particular, are the integration tests in `raii-integration-copy.t` and `raii-integration-move.t`.

## Current limitations
* The implementation is not aware of when an actual heap allocation is made and therefore assumes that a managed variable always carries a heap resource. It is up to the programmer to properly initialize pointer variables to `nil` to avoid calling `free` on uninitialized pointers.
* Destructors are called in reverse order of object definition, a `var x : A` or `var x = ...` statement. 
* Currently, `__init` is used to fully initialize an object, in a copy- and move-construction. This is convenient but not optimal, since some fields will be assigned to twice.
* Destructors are sometimes called even if the object has been initialized to `nil`. This is not optimal.
* Tuple (copy) assignment (regular or using `__copy`) are prohibited by the compiler in case of managed variables. This is done to prevent memory leaks or unwanted deletions in assignments such as
```
a, b = b, a
```

## ToDo:
The following two items will alleviate the first four limitations completely and will provide safety and efficiency.
1. Track (field) initialization and add compiler-checks
2. Add field-based initializers directly in struct definition.
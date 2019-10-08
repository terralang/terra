---
layout: post
title: About Us
---

**[Terra: A Multi-Stage Language for High-Performance Computing](pldi071-devito.pdf)** <br/>
_Zachary DeVito, James Hegarty, Alex Aiken, Pat Hanrahan, and Jan Vitek_<br/>
PLDI '13

High-performance computing applications, such as auto-tuners and
domain-specific languages, rely on generative programming techniques to
achieve high performance and portability. However, these systems are often
implemented in multiple disparate languages and perform code generation in a
separate process from program execution, making certain optimizations
difficult to engineer. We leverage a popular scripting language, Lua, to
stage the execution of a novel low-level language, Terra. Users can
implement optimizations in the high-level language, and use built-in
constructs to generate and execute high-performance Terra code. To simplify
meta-programming, Lua and Terra share the same lexical environment, but, to
ensure performance, Terra code can execute independently of Lua's
runtime. We evaluate our design by reimplementing existing multi-language
systems entirely in Terra. Our Terra-based auto-tuner for BLAS routines
performs within 20% of ATLAS, and our DSL for stencil computations runs
2.3x faster than hand-written C.

**[First-class Runtime Generation of High-performance Types using Exotypes](pldi083-devito.pdf)** <br/>
_Zachary DeVito, Daniel Ritchie, Matt Fisher, Alex Aiken, and Pat Hanrahan_<br/>
PLDI '14

We introduce *exotypes*, user-defined types that combine the flexibility of meta-object protocols in dynamically-typed languages with the performance control of low-level languages. Like objects in dynamic languages, exotypes are defined programmatically at runtime, allowing behavior based on external data such as a database schema. To achieve high performance, we use staged programming to define the behavior of an exotype during a runtime compilation step and implement exotypes in Terra, a low-level staged programming language.

We show how exotype constructors compose, and use exotypes to implement high-performance libraries for serialization, dynamic assembly, automatic differentiation, and probabilistic programming. Each exotype achieves expressiveness similar to libraries written in dynamically-typed languages but implements optimizations that exceed the performance of existing libraries written in low-level statically-typed languages. Though each implementation is significantly shorter, our serialization library is 11 times faster than Kryo, and our dynamic assembler is 3--20 times faster than Google's Chrome assembler.

**[The Design of Terra: Harnessing the best features of high-level and low-level languages](snapl-devito.pdf)** <br/>
_Zachary DeVito and Pat Hanrahan_<br/>
SNAPL '15

Applications are often written using a combination of high-level and low-level languages since it allows performance critical parts to be carefully optimized, while other parts can be written more productively. This approach is used in web development, game programming, and in build systems for applications themselves. However, most languages were not designed with interoperability in mind, resulting in glue code and duplicated features that add complexity. We propose a two-language system where both languages were designed to interoperate. Lua is used for our high-level language since it was originally designed with interoperability in mind. We create a new low-level language, Terra, that we designed to interoperate with Lua. It is embedded in Lua, and meta-programmed from it, but has a low level of abstraction suited for writing high-performance code. We discuss important design decisions — compartmentalized runtimes, glue-free interoperation, and meta-programming features — that enable Lua and Terra to be more powerful than the sum of their parts.
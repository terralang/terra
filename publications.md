---
layout: post
title: About Us
---
Publications
============


**[Terra: A Multi-Stage Language for High-Performance Computing](pldi071-devito.pdf)** <br/>
_Zachary DeVito, James Hegarty, Alex Aiken, Pat Hanrahan, and Jan Vitek_<br/>
To appear in PLDI '13

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



    
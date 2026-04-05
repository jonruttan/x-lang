Title:       X-Lang Project Notes  
Description: Development notes for X-Lang.  
Keywords:    [#X, #X-Lang, #Project, #Notes]  
Author:      "[Jon Ruttan](jonruttan@gmail.com)"  
Date:        2021-10-06  
Revision:    6 (2026-03-21)  

# X-Lang Project Notes

## Sub-projects

### X-Expressions (x-expr) -- Computational Expressions Library

**Status: Implemented** (`ext/x-expr/`)

- Simple, minimalist, thread-safe
- Dynamic type system with type-specific evaluators
- Multiple independent environments
- Metacircular evaluator, reflective
- ANSI / Standard C, no external dependencies


### X-Lang (xe/xenon) -- Minimalist Dialect

**Status: Implemented** (v0.2.0)

- Foundational / Scripting
- Lisp1 with fexpr evaluation model
- 50+ modular library files
- Module system (provide/import)
- JIT compiler (x86_64, ARM64)
- Numeric tower (bignum, float, rational, complex)
- POSIX via FFI, regex, vectors, hash tables
- Self-hosted tools (lint, fmt, cov, profile, doc)
- Three dialects: x-lang (core), x/and (stable), x/or (experimental)
- Language personalities: R5RS, R7RS, Kernel, ASH, Sweet
- ANSI / Standard C, no external dependencies


### Neon (ne/neon) -- Midsize/Unstable Dialect

**Status: Aspirational**

Experimental / Hacking

- Built on X-Lang
- Unstable
- Full Dialect
- Kernel access
- Compiler
- Modules


### Helium (he/helium) -- Maximal/Stable X-Lang Dialect

**Status: Aspirational**

Hardened / Full Stack

- Built on X-Lang
- Stable
- Lisp1
- Full Dialect
- Kernel access
- Compiler
- Modules
- Hardened


### X-Tools System Tools

**Status: Partially Implemented**

- Document generator (implemented: `lib/x/doc/`)
- Linter (implemented: `lib/x/tool/lint.x`)
- Formatter (implemented: `lib/x/tool/fmt.x`)
- Coverage analyzer (implemented: `lib/x/tool/cov.x`)
- Profiler (implemented: `lib/x/tool/profile.x`)
- Package manager(s) (aspirational)
- Editor (aspirational)
- Make (aspirational)
- C Compiler (aspirational)
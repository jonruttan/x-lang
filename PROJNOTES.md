Title:       x-lang Project Notes  
Description: Development notes for x-lang.  
Keywords:    [#x-lang, #Project, #Notes]  
Author:      "[Jon Ruttan](jonruttan@gmail.com)"  
Date:        2021-10-06  
Revision:    7 (2026-07-10)  

# x-lang Project Notes

## Sub-projects

### X-Expressions (x-expr) -- Computational Expressions Library

**Status: Implemented** (`ext/x-expr/`)

- Simple, minimalist, thread-safe
- Dynamic type system with type-specific evaluators
- Multiple independent environments
- Metacircular evaluator, reflective
- ANSI / Standard C, no external dependencies


### x-lang (xe/xenon) -- Minimalist Dialect

**Status: Implemented** (v0.2.0)

- Foundational / Scripting
- Lisp1 with fexpr evaluation model
- ~100 modular library files
- Module system (provide/import)
- JIT assembler (x86_64, ARM64); automatic native compiler (ARM64 only)
- Numeric tower (bignum, float, rational, complex)
- POSIX via FFI, regex, vectors, hash tables
- Self-hosted tools (lint, fmt, cov, profile, doc)
- Three dialects: helium (light/default), xenon (stable full-stack), radon (experimental)
- Language personalities: R5RS, R7RS, Kernel, ASH, Sweet
- ANSI / Standard C, no external dependencies


### Neon (ne/neon) -- Midsize/Unstable Dialect

**Status: Aspirational**

Experimental / Hacking

- Built on x-lang
- Unstable
- Full Dialect
- Kernel access
- Compiler
- Modules


### Helium (he/helium) -- Maximal/Stable x-lang Dialect

**Status: Aspirational**

Hardened / Full Stack

- Built on x-lang
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
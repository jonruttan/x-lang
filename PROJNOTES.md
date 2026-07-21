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


### x-lang -- The Language

**Status: Implemented** (v0.3.0)

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


### Noble-gas dialects (he/xe/rn)

**Status: Shipped** (v0.3.0, #95 — supersedes the old aspirational
Neon/Helium notes, whose meanings did not survive the adjudication:
helium shipped as the LIGHT dialect, not "maximal/stable", and
stability-channel dialects were ruled out entirely — a release channel
is not a dialect. See docs/dialects.md for the ruling.)

- **helium** (`he`) — light, fast boot, interactive, no tower; the default
- **xenon** (`xe`) — full numeric tower, POSIX, compiler; stable
- **radon** (`rn`) — xenon's surface + experimental/raw APIs; volatile

Atomic weight = library weight; radioactivity = instability. Dialects
never re-mean a shared spelling.


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
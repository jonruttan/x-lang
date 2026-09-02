Title:       x-lang Project Notes  
Description: Development notes for x-lang.  
Keywords:    [#x-lang, #Project, #Notes]  
Author:      "[Jon Ruttan](jonruttan@gmail.com)"  
Date:        2021-10-06  
Revision:    9 (2026-09-01)  

# x-lang Project Notes

## Sub-projects

### Engines

The engine is no longer part of this repository. It is acquired as a pinned,
verified artifact and held to `docs/engine-contract.md`.

- **x-engine-c** ([repo](https://github.com/jonruttan/x-engine-c)) --
  **Status: Implemented.** The C89 engine: evaluator, primitive surface,
  tokenizer. What `tools/engine/engine.pin.xon` names.
- **x-engine-rust** ([repo](https://github.com/jonruttan/x-engine-rust)) --
  **Status: In progress.** A second engine. Its core forbids `unsafe`; the
  foreign door is a separate crate.

Shared engine properties: dynamic type system with type-specific evaluators,
multiple independent environments, a metacircular reflective evaluator, and no
external dependencies.


### x-lang -- The Language

**Status: Implemented** (v0.5.2)

- Foundational / Scripting
- Lisp1 with fexpr evaluation model
- ~100 modular library files
- Module system (provide/import)
- JIT assembler (x86_64, ARM64); automatic native compiler (ARM64 only)
- Numeric tower (bigint, float, rational, complex)
- POSIX via FFI, regex, vectors, hash tables
- Self-hosted tools (lint, fmt, cov, profile, doc)
- Three dialects: helium (light/default), xenon (stable full-stack), radon (experimental)
- Langs: R5RS, R7RS, Kernel, ASH, Sweet
- Engine-agnostic: the interpreter is a pinned artifact behind a published contract


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
- Make (implemented as a lang: [x-make](https://github.com/jonruttan/x-make))
- C Compiler (implemented as a lang: [x-cc](https://github.com/jonruttan/x-cc))
- awk, grep, sed, coreutils (implemented as langs — the self-hosting arc; see docs/bootstrap-closure.md)
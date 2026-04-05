# x-lang Reference

Generated from source by `make doc-x`.

## Bootstrap

- [x/boot/data](boot/data.md)
- [x/boot/module](boot/module.md)
- [x/boot/operatives](boot/operatives.md)
- [x/boot/string](boot/string.md)

## Core

- [x/core/alist](core/alist.md) — Association list operations.
- [x/core/arithmetic](core/arithmetic.md) — Variadic addition. Returns the sum of all arguments.
- [x/core/banner](core/banner.md)
- [x/core/boolean](core/boolean.md) — Short-circuit logical AND and OR operatives, plus timing.
- [x/core/control](core/control.md) — Conditional: evaluate test, then branch.
- [x/core/fn](core/fn.md) — Higher-order function combinators.
- [x/core/hash](core/hash.md) — FNV-1a hash function for strings.
- [x/core/list](core/list.md) — List processing: map, filter, fold, sort, and 60+ functions.
- [x/core/logic](core/logic.md) — Boolean logic, structural equality, and derived comparisons.
- [x/core/math](core/math.md) — Integer arithmetic utilities.
- [x/core/predicates](core/predicates.md) — Test if a value is nil (the empty list).
- [x/core/quasi](core/quasi.md) — Quasiquote: template with unquote and splicing.
- [x/core/repl](core/repl.md) — Start the read-eval-print loop.
- [x/core/syntax](core/syntax.md) — Derived syntax forms: cond, case, when, unless, let*, letrec.

## Types

- [x/type/char](type/char.md) — Character classification and case conversion.
- [x/type/promise](type/promise.md) — Lazy evaluation with delay/force.
- [x/type/regex](type/regex.md) — Regular expressions with literal syntax.
- [x/type/string](type/string.md) — String manipulation, searching, and transformation.
- [x/type/vector](type/vector.md) — Fixed-size indexed vectors.

## System

- [x/sys/convert](sys/convert.md)
- [x/sys/file](sys/file.md) — File I/O via POSIX syscalls with symbolic mode flags.
- [x/sys/gc](sys/gc.md) — Run a full garbage collection cycle.
- [x/sys/intrinsics](sys/intrinsics.md) — Return the next character from stdin without consuming it.
- [x/sys/posix](sys/posix.md) — POSIX system call wrappers via FFI.
- [x/sys/token](sys/token.md) — Composable tokenizer state machine builders.
- [x/sys/type](sys/type.md)

## Numeric Tower

- [x/num/bignum](num/bignum.md) — Arbitrary-precision integers.
- [x/num/complex](num/complex.md) — Complex number arithmetic with rectangular and polar forms.
- [x/num/float](num/float.md) — IEEE 754 floating-point arithmetic.
- [x/num/rational](num/rational.md) — Exact rational number arithmetic.
- [x/num/tower](num/tower.md) — Numeric tower helpers for building type-promoting operators.

## Documentation

- [x/doc/doc-gen](doc/doc-gen.md) — Markdown documentation generator from x-lang source tokens.
- [x/doc/doc-prims](doc/doc-prims.md) — Retroactive documentation for C primitives, boot forms, and type system functions.
- [x/doc/doc](doc/doc.md) — Inline documentation system.

## Tools

- [x/tool/asm-compile](tool/asm-compile.md) — JIT compiler: x-lang to native code via assembler.
- [x/asm](tool/asm.md) — Data-driven assembler with JIT execution via mmap.
- [x/tool/compile](tool/compile.md) — Native code compiler: JIT assembler (default) with C compiler fallback.
- [x/tool/cov](tool/cov.md) — Library coverage analysis for x-profile instrumented code.
- [x/tool/fmt](tool/fmt.md) — Comment-preserving s-expression formatter.
- [x/tool/lint](tool/lint.md) — AST linter: def/use analysis for x-lang source.
- [x/tool/profile](tool/profile.md) — Performance profiling and smart garbage collection.

## Platform

- [x/platform/arm64](platform/arm64.md)
- [x/platform/socket](platform/socket.md) — Socket constant lookup tables for Linux socketcall, protocol families, and socket types.
- [x/platform/syscall](platform/syscall.md) — Syscall number tables for x86_64 and i386/BSD. Maps symbolic names to syscall numbers.
- [x/platform/x86_64](platform/x86_64.md)

## Top-level

- [x/and](and.md) — x/and: Stable full-stack dialect built on x-lang.
- [constructs](constructs.md)
- [x/or](or.md) — x/or: Experimental hacking dialect built on x-lang.
- [x-core](x-core.md)


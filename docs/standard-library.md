# x-lang Standard Library

*x-lang: computational expressions over a minimal, type-agnostic engine.*

The library is written in x-lang, in about 140 modules under `lib/x/`, one
module to a file. Every function, class and method in it carries a `(doc …)`
form beside its definition, and that form is the reference: the
[x-lang API Reference](https://jonruttan.github.io/x-lang/docs/ref/x/index.html)
is generated from them, module by module, and `make doc-x` writes the same
pages to `docs/ref/x/` offline. The man pages (`make doc-man`) come from the
same forms. This page says how the library is laid out and how to find a name
in it; it does not repeat the reference.

## How it is laid out

| Directory | Contents |
|---|---|
| `lib/x/boot/` | the files the module system itself stands on: the catalog protocol, the printer, byte strings, the loader |
| `lib/x/core/` | combinators, lists and association lists, logic, arithmetic, `match`, `let` and the other core forms, quasiquote |
| `lib/x/type/` | the classes: `List`, `Str`, `Char`, `Vector`, `Array`, `Dict`, `Hash`, `Assoc`, `Deque`, `Path`, `Promise`, `Regex`, `Iter`, the object system, records, traits, generics |
| `lib/x/protocol/` | the sequence and string protocols a class implements to join those families |
| `lib/x/num/` | the numeric tower: bigint, float, rational, complex, decimal, and the mixed-type policy in `x/num/tower` |
| `lib/x/sys/` | POSIX, files, streams, processes, sockets, the collector, dates, command-line options |
| `lib/x/codec/` | JSON, XON, CSV, base64, hex, UTF-8, SHA-1 and SHA-256, zlib, structs |
| `lib/x/reader/` | the tokenizer's intrinsics, the lexer, the analyser, and the literal, quasiquote and indentation readers |
| `lib/x/repl/` | the line editor, colour, the banner and the loop a lang hands its session to |
| `lib/x/tool/` | the linter, formatter, highlighter, coverage, profiler, assembler and compiler, the state-image walk, the pin tool |
| `lib/x/doc/` | the `doc` form, the registry behind `help` and `apropos`, the generators |
| `lib/x/platform/` | the syscall tables, directory entries and socket constants per platform |

Which modules a session has depends on its dialect: helium loads the core,
the types and the REPL; xenon adds POSIX, hash tables, the JIT and the
numeric tower; radon adds the raw syscall layer. [Dialects](dialects.md) has
the composition, and `(modules)` lists every module with a `[loaded]` mark
beside those the running session has.

## The shape of a call

A function homes on a class and dispatches **subject-last**: the thing
operated on is the last argument.

```x-repl
(List length (list 1 2 3)) -> 3
(Str8 split "," "a,b,c") -> ("a" "b" "c")
```

A value is callable and dispatches to its class with the same spelling, so
`("a,b,c" split ",")` is the same call. To pass a method as a value, take a
reference to it:

```x-repl
((method-ref Num inc) 41) -> 42
(List map (method-ref Num inc) (list 1 2)) -> (2 3)
```

A name that starts with `%` is private to its module and is not part of the
reference. [Modules](modules.md#module-scope) says what leaves a module and
how.

## Finding a name

The library documents itself, and three calls reach all of it:

```x
(apropos "split")        ; every documented name that mentions it
(help Str8/split)        ; one method: signature, each argument, the return, an example
(help x/core/math)       ; one module: its exports
```

`(help Name/method)` is the one to reach for. It answers from the same
`(doc …)` form the reference is built from, so the two cannot disagree. A
missed method names its nearest matches.

## Writing to the reference

The `(doc …)` form beside a definition is the entry. Change the behaviour and
the form in the same edit; [Contributing](contributing.md) has the vocabulary
the gates hold the forms to (`INTEGER`, `BOOL`, `CALLABLE`, …), and
`make doctest` runs every example the forms carry.

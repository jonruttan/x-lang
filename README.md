# Computational Expressions in C

```
    ., .,
    {O,O}
    (   )
     " "
```

A minimal, type-agnostic expression interpreter written in C89. The core provides atom/pair primitives, an adaptive type system, and fexpr-based evaluation. Everything else — including the standard library, language semantics, and safety — is built on top.

## Architecture

The system is layered. Each layer expands capabilities without modifying those below it.

1. **Atom/pair bootstrap** — Intrinsic types sufficient for evaluation and data construction.
2. **Adaptive type system** — Runtime type definitions with dispatch methods (call, eval, write, length, etc.). Types and the base object share the same nested-list contract structure, extensible by appending pairs.
3. **Standard library** (`lib/x.x`) — ~80 functions (combinators, list operations, sorting, association lists, strings, vectors) written in x-lang itself.
4. **Language personalities** — R5RS Scheme, Kernel, and SL semantics as alias libraries loaded at startup. The interpreter knows nothing about any of these languages.

See [docs/](docs/) for complete reference documentation.

## Build

```sh
make clean && make
```

Requires a C89-compatible compiler. Produces the `x` binary.

## Run

The interpreter reads from stdin. Libraries are loaded by concatenation:

```sh
# Bare interpreter (primitives only)
./x

# With standard library
cat lib/x.x - | ./x

# With R5RS Scheme personality
cat lib/x.x lang/r5rs/lib/r5rs.x - | ./x

# With Kernel personality
cat lib/x.x lang/krn/lib/krn.x - | ./x

# With SL personality (syscall-capable)
cat lib/x.x lang/sl/lib/sl.x - | ./x

# Evaluate a file
cat lib/x.x program.x | ./x
```

The `-` in `cat ... - | ./x` connects stdin for interactive use after library loading.

## Test

```sh
sh tests/x/spec-runner.sh        # x-lang:  474 tests
sh tests/r5rs/spec-runner.sh     # R5RS:   108 tests
sh tests/krn/spec-runner.sh      # Kernel:   72 tests
sh tests/sl/spec-runner.sh       # SL:      tests
```

## Documentation

- [Architecture](docs/architecture.md) — System design, evaluation model, the contract pattern
- [Type System](docs/type-system.md) — Objects, types, the base, dispatch, extensibility
- [Primitives](docs/primitives.md) — All C-level primitive operations
- [Standard Library](docs/standard-library.md) — lib/x.x function reference
- [Personalities](docs/personalities.md) — R5RS Scheme, Kernel, and SL layers

## License

MIT No Attribution (MIT-0)

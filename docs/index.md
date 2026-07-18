# x-lang Documentation

## Getting Started

- [Tutorial](tutorial.md) — Build, run, and write your first x-lang programs
- [README](../README.md) — Project overview, build instructions, feature summary

## Language

- [Specification](spec.md) — Normative language specification (maps 1:1 to test files)
- [Glossary](glossary.md) — One name per concept: the settled cross-layer vocabulary
- [Architecture](architecture.md) — System design, evaluation model, the contract pattern
- [Type System](type-system.md) — Objects, types, the base object, dispatch, extensibility
- [Object System](object-system.md) — Message-passing classes, single inheritance, encapsulated members, `super`
- [Dialects](dialects.md) — x-lang, x/and, and x/or dialect layers
- [Modules](modules.md) — The provide/import module system

## Reference

- [C Primitives](primitives.md) — All C-level primitive operations (hand-written)
- [Standard Library](standard-library.md) — Core library functions (hand-written)
- x-lang API Reference — complete library reference, auto-generated from `(doc ...)` forms and not committed: run `make doc-x`, then open `ref/x/index.md`
- C API Reference — Doxygen: run `make doc-c`, then open `ref/c/html/index.html`

## Tools

- [Linter](../tools/README-lint.md) — AST linter for x-lang source
- [Formatter](../tools/README-fmt.md) — Comment-preserving s-expression formatter
- [Coverage](../tools/README-cov.md) — Library coverage analysis

## Project

- [Contributing](contributing.md) — Build prerequisites, code style, testing, commit conventions
- [Changelog](../CHANGELOG.md) — Version history
- [License](../LICENSE) — MIT No Attribution (MIT-0)

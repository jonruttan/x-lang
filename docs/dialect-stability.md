# What stays stable

*Which operatives, primitives and types a program or a hosted language may
build on, by layer, and the gate that holds each one.*

A name is listed here only where a gate fails when it changes. Anything not
listed may change between releases.

## The evaluator: every dialect, every engine

The conformance suite (`tests/x/conformance`, run by `make conformance`) loads
no library and defines what a correct evaluator is. Each case names what it
covers, and `make check-conformance-coverage` fails when a row that was
covered no longer is. `X_BIN` aims the suite at any engine.

| group | covered |
|---|---|
| binding and evaluation | `def` `set!` `fn` `op` `eval` `eval!` `lit` `match` `apply` `wrap` `unwrap` `include` `atomic` `tail-eval` |
| conditions and control | `guard` `error` `call/cc` |
| pairs and identity | `pair` `first` `rest` `eq?` `same?` |
| integers | `+` `-` `*` `/` `%` `<` `=` `&` `\|` `^` `~` `<<` `>>`, and the same operations under `int/` |
| strings, symbols, characters | `str/append` `str/byte-len` `str/byte-ref` `str/byte-sub` `str/make` `str/->sym` `sym/->str` `char/->int` `int/->char` `bytes/->str` |
| types | `type/of` `type/?` `type/make` `type/make-instance` |
| objects and memory | `obj/eq?` `obj/same?` `obj/make` `obj/make-callable` `obj/->ptr`, and the `ptr/` and `mem/` words |
| iterators | `iter/make` `iter/next` `iter/step` `iter/empty?` |
| bases | `%base` `base/make` `base/eval` `base/bind` |
| the reader | `base/make-tok` `base/make-type` `tok/read-str` `buf/read` `buf/tok` `buf/last-char` `buf/retain` |

`fn` builds an applicative and `op` an operative: an operative receives its
operands unevaluated, with the caller's environment. A name with a slash is a
catalogue primitive, fetched with `(prim-ref 'NAMESPACE 'NAME)`.

The reader rows are what a hosted language's tokenizer stands on: a token
type registered on a base of its own, with an `analyse` handler that scores
the input and a `read` handler that builds the token.
[Crafting a lang](crafting-a-lang.md) describes the protocol.

## helium

The default dialect. Its surface is the library `lib/x-core.x` loads, and it
is held by the spec suite (`make test-x`), the doctests in each module
(`make doctest`) and the worked examples of [the specification](spec.md)
(`make spec-examples`).

- Operatives: `if` `cond` `case` `when` `unless` `let` `letrec` `do`
  `quasi` `provide` `import` `def-class`.
- Types: integer, character, string, symbol, pair, vector, promise.
- No numeric tower: an integer is a machine word.

## neon

helium's surface, unchanged, plus what a language built on x-lang stands on:

- The assembler and the compiler (`compile-asm`, `compile`), and the
  function compiler.
- The Lexer, and `Dict`.

Neon adds no reader syntax and loads no numeric tower. It is held by its
smoke spec (`tests/x/specs/dialects/smoke-ne.spec.md`) and, through xenon,
by everything that holds xenon.

## xenon

neon's surface, unchanged, plus:

- Types: `Set`, regular expressions, and the numeric tower: bigint, float,
  rational, complex, decimal, with the literals that write them.

Xenon is the stable full surface. A spelling shared with helium means the
same thing in both: a dialect may differ in what is loaded and never in what
a loaded name means.

## radon

neon's surface and everything xenon adds, plus the names `lib/x/rn.x`
defines: character and I/O constants, the `cadr` family, `list-ref` and
`list-tail`, `system`, `do-loop`. Nothing radon adds is promised. Its
additions may change or be removed in any release.

## What a hosted language is promised

Beyond the evaluator rows above, a lang may rely on the seam: the names
`tools/contract/seam.x` declares, held in every dialect by `make check-seam`.
They are the REPL's seams (`%repl-prompt`, `%repl-print`, `%repl-paint`,
`%repl-marks`, `%repl-complete`, `%repl-eval-line`), the `Lang` registry and
the `lang` switch, `import-path!`, `eval!`, and the names that say where a
bundle is. [The Lang Contract](lang-contract.md) lists each with its meaning.

A change to the library, the engine pin or the wrapper also runs the Python,
Logo and Scheme suites against the changed tree in CI (`make check-bundles`,
with the budgets of `tools/contract/bundles.x`).

## What is not promised

- A name that begins with `%` and is not in the seam: it is private to the
  module that defines it.
- radon's additions.

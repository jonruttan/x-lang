# Contributing

## Build Prerequisites

- A C89-compatible compiler (gcc, clang, tcc, c89, c99)
- POSIX shell (`sh`) for test runners
- Make
- The git submodules (`ext/x-expr` — the expression engine the build
  requires — and `tests/c/test-runner`): clone with `--recursive`, or run
  `git submodule update --init` in an existing clone

```sh
make clean && make
```

## Code Style

### C Code

- **C89 standard** — no C99 features. Variables declared at the top of the FUNCTION (house rule, stricter than C89's top-of-block); hoist via guarded initializers or assign-in-place
- **`x_` prefix** — All exported symbols use the `x_` prefix
- **Naming** — Use `pair`/`first`/`rest`, never cons/car/cdr. Use `fn`/`def`/`set!`/`do`/`op`/`lit`/`quasi`/`match`
- **Accessor families** — `x_first`/`x_rest`* are the canonical pair accessors;
  the `x_0`/`x_1` bit-path family is blessed for dense field plumbing (the
  base layout); x-lisp.h's `x_car`/`x_cdr` are embedder-compat shims only —
  never used in this repo's own code
- **No globals** — All interpreter state belongs on `p_base`. Never use static or global variables for state
- **Stack-allocated pairs** — Prefer `x_satom_t`/`x_spair_t` over heap allocation where possible
- **Doxygen comments** — All public functions and macros documented with `@brief`, `@param`, `@return`. File headers include `@file`, `@brief`, `@author`, `@copyright`, `@license`, and the ASCII owl

### x-lang Code

- **Module structure** — Dependencies via `(import ...)`, exports via `(provide ...)` at file bottom
- **Documentation** — Wrap definitions in `(doc ...)` forms with `(param ...)`, `(returns ...)`, description string
- **No `cond`/`convert` in tokenizer callbacks** — Use nested `if` and direct C primitives to avoid GC corruption
- **Quote spelling** — `'x` in all post-boot code (#45 R2). `(lit x)` is the
  boot-layer mechanism spelling, used only in files that parse before the
  quote reader exists: `x-core.x`, its includes through `lit-reader.x`, and
  the files those pull in via mid-boot `import` (`codec/utf8.x`,
  `platform/syscall.x`) — plus `tools/isa.x`, a data manifest. Strings and
  comments inside those files may still show `'x`. See [syntax.md](syntax.md)
- **File extension** — `.x`

### Method Naming (adjudicated — one name per concept)

- **Element access is `ref`** on every class (`List ref`, `Vector ref`, `Str8 ref`,
  `Gen ref`, `Obj ref`, `Ptr ref`). `Str8 index` survives as a documented alias;
  don't add new `nth`/`index` methods.
- **`length` is the property; `count` is the action** (see the [glossary](glossary.md)).
  Every finite collection exposes `length` — List, Vector, Array, Str8, StrUTF8,
  Seq, Dict, Set (Dict/Set store it, O(1)). `count` names genuine tallying acts
  only: `Gen count` (consumes the stream — a lazy stream has no length
  property), `Seq count` (the cursor-walk the default `length` delegates to),
  `Heap count` (walks the heap chain), and the verb-compounds `count-if`
  (List), `match-count` (Regex), `count-from` (Gen). Never add a `count` that
  merely reads a size — that's a `length`.
- **Predicates are `any?` / `all?` / `none?`**; iteration for side effects is
  `for-each`. (Not `every?`, not `each`.)
- **Conversions are `->x` / `from-x`** as class methods (`Dict ->alist`,
  `Hash ->hex`, `Vector ->list` / `from-list`). The bare `X->Y` globals
  (`list->str`, `str->number`) are the pre-class boot layer only — don't add new ones.
- **Association vocabulary** (see the [glossary](glossary.md)): an **assoc** is one
  dotted `(key . val)` pair; an **alist** is a list of assocs; a **plist** is the
  flat `(k v k v ...)` shape, legal ONLY in option stores (the `%opt-cell`
  family: `let-opts`, `Assoc opt-get-or`/`opt-get-or-else`, `new`, `new-from`);
  a **bindings list** is `((key value) ...)` two-element lists, the `let` shape.
  The word "pairs" appears in NO method name — pairing producers (`List zip`,
  `Gen zip`/`enumerate`, `List group-by`) emit alists; the converters are
  `Dict from-alist`/`->alist` and `Assoc from-bindings`/`->bindings`. Equality:
  the alist layer (`Assoc get`, `assoc-get`) compares keys with `eq?`;
  `List assoc` (`equal?`) and `List assq` (`eq?`) return the assoc itself and
  are the presence-unambiguous entry doors.
- **Constructor-style counts come first**: `(List repeat n x)`, `(Str8 repeat n s)`,
  `(Str8 make k ch)`, `(Vector make n fill)`.
- **Trailing optionals are positional**: `(Dict make 32)`, `(Array make 32)`,
  `(Str8 make k ch)` — a constructor's optional tail rides `(. opt)`
  positionally. Option STORES (alist-or-plist) are for *named* config only
  (`let-opts`, `new`/`new-from`); don't mix the two styles in one signature.
- **Mutator returns have two tiers**: container bangs return the receiver
  for chaining (`Dict put!`, `Array set!`, `Set add!`); raw-tier bangs
  return `()` per the C side-effect rule (`Obj set!`, `Ptr set!`); removers
  return the removed element (`Array pop!`). Crossing tiers? Check which
  one you're on before chaining.
- **Two blessed value sentinels, no third**: `raised`'s `%no-raise` (test
  layer only — distinguishes a raised nil from no-raise) and OS-domain
  `-1` (boundary vocabulary, like JSON's `null` symbol). Everything else
  misses with nil behind a presence door.
- **Positional edits clamp, never error**: `insert` at ≥ length appends;
  `update`/`adjust` past the end are no-ops; `remove` clamps — the same
  clamp discipline as `take`/`drop`/`slice`. (Element *access* — `ref` —
  errors instead; reading a hole is a bug, editing past the end is a no-op.)
- **Scalar operators are variadic; collection consumers take the
  collection**: `(Num min a b c)` vs `(List min lst)` — the same split as
  `+` vs `fold`. Not drift; don't "unify" them.
- **Two documented data-position exceptions**: `Convert to (val target
  . args)` reads value→target (the conversion dispatcher's natural order),
  and Regex methods are subject-last on the COMPILED REGEX — `(rx match
  str)` ⇒ `(Regex match str rx)`; the string is an argument, the regex is
  the subject.
- **Keyed lookup follows the dispatch tiers** (no signature to memorize):
  containers speak `(store get k)` (Dict, Set — instance dispatch); value
  classes speak `(Class get key store)` (Assoc — data-last static);
  registries speak `(Class get name)` (Pact — module-state singleton).
  Every `get` pairs with eager `get-or` (default first) and lazy
  `get-or-else` (thunk first).
- **Associative callbacks: transformers get the value, selectors get the
  assoc.** `map`/`evolve` rewrite values (keys preserved) so their fn
  receives the VALUE; `filter`/`pick`/`omit`/`for-each` decide on or consume
  entries so their fn receives the whole `(key . val)` assoc. No key+value
  two-arg form exists; don't add one without a driving use.
- **Principled triads, not synonyms** — positional update: `update` (n, new
  value) / `adjust` (n, function) / `evolve` (per-key function alist);
  membership: `has?` (keyed presence) / `includes?` (element of a sequence)
  / `contains?` (subsequence of a string). Never add a fourth spelling
  (`member?`, `nth-set`, ...).
- **The name is the range contract**: `slice` always means (start,
  end-exclusive); `sub` always means (start, length) — on every class
  (`List slice`/`sub`, `Str8`/`StrUTF8 slice`/`sub`; `substring` is the
  byte-level slice-convention primitive). Never add a range method whose
  name doesn't declare its convention.
- **Constructor verbs — one meaning each**: `make` = build from parts/config
  (`Dict make`, `Gen make step state`); `of` = variadic literal, on every
  element container (`List`/`Vector`/`Array`/`Set`/`Gen of ...`; Dict excluded —
  flat values can't spell pairs; strings' variadic literal is `str`);
  `from-X` = conversion from another shape (`from-list`, `from-alist`,
  `from-bindings`, `from-seq`); `build` = generate elements by function
  (`Vector build n f`); `new`/`new-from` = allocate an instance over
  something (object system; `Iter new v` boxes a value into a cursor).
  C side: `x_make_X(base, flags, ...)` is the flag-taking function,
  `x_mkX(...)` its default-flags macro — a ladder, not duplication.
- **member / field / slot are three tiers, not synonyms**: a class instance
  has **members** (`def-class` members, `(member 'name)`, `set-member!`,
  `own-members`) — the only word user-facing docs use; a **field** is a
  named leaf of the base tree (field cells, `x_base_field_*` /
  `x_eval_field_*`); a **slot** is a raw object position (`Obj ref`, type
  slots, the vector's backing slots). Same ladder as the storage tiers.
- **The `%` sigil means private**, in four flavors (all legitimate): a
  module-private helper (`%opt-cell`), a cached raw C prim behind a class
  method (`%str-append`, the prim-caching pattern), a macro-expansion
  runtime hook referenced from `op` expansions (`%opts`), and type-system
  plumbing (`%make-type`, `%class-call-handler`). The sigil promises
  "not API"; it does not say which flavor — the defining comment should.
- **Doc type vocabulary** — one token per concept in `(param ...)`/`(returns ...)`:
  `INT` (not INTEGER), `BOOL` (not BOOLEAN), `CALLABLE` (not FUNCTION), plus
  `ANY STRING SYMBOL LIST PAIR CHAR NUMBER VECTOR REGEX FLOAT BIGNUM RATIONAL
  COMPLEX ITER OBJECT CLASS PTR BUF`. `PROCEDURE`/`OPERATIVE` are reserved for
  the fn/op constructors' returns. Class names (`Dict`, `Array`, `Random`, ...)
  are legitimate returns types as-is. `make check-doc-vocab` enforces the
  banned aliases.
- **Absence discipline** (normative; the full statement is spec.md's "Nil,
  false, and truthiness"): falsy = {nil, `#f`} only; predicates answer
  `#t`/`#f`; misses return nil (never `#f`) — index-search misses included;
  nil-storable slots need a presence door (`has?` / presence-based `-or`),
  never a value sentinel; boundaries carry foreign null as the symbol `null`
  (and OS-domain tables keep the OS's own `-1` invalid marker).
- **Indexes are 0-based; negatives count from the end** on strict indexed
  collections (`List ref`, `Vector`, `Array`, `Str8`/`StrUTF8 ref`, the bare
  `(s i)`; `Gen ref` excepted — a lazy stream has no end). Index-search
  misses return `()` (the old `-1` exception is repealed).
- **Count/index seats coerce to INT implicitly** through the conversion
  catalog (N5): an already-INT argument costs one cached type-handle `eq?`;
  anything else converts (a float truncates per the tower's converter), and
  only an UNCONVERTIBLE value errors ("… not convertible to INT") — which is
  how a piped nil miss fails loudly. Coercion runs ONCE per public entry;
  self-recursive walks live in inner `go` fns so loops never re-probe.
  Explicit control: pre-convert (`(Convert to x %int)`) or test with
  `(Num int? x)`. Exception: the bare `(s i)` boot door stays INT-only —
  it can run under reader constraints where conversion dispatch is illegal.
- **Generators and iterators** (see the [glossary](glossary.md)): a *generator*
  is the pure step contract — `(step state) -> (value . next-state)` or `()` —
  and an *iterator* is a generator boxed with a cursor cell; `Iter next` owns
  the write-back, steps never mutate. `Gen` is the one lazy-pipeline class.
  Dispatch rule: def-class instances speak message-send; raw typed values get
  static data-last methods (fluent via value-call). Counted-vs-infinite rule:
  strict classes take counts (`List repeat n x`, `List iterate f n x`); lazy
  streams are infinite and bounded with `take` (`Gen repeat x`, `Gen iterate f x`).
- **Arguments are subject-LAST** (the dispatched value is the final parameter),
  matching value-call dispatch: `("a,b" split ",")` → `(Str split "," "a,b")`.
  Deliberate exception: the `File`/`Sys` OS layer mirrors POSIX and stays
  handle-first (`(File write fd data)`); fds are ints and never value-dispatch.

## Testing

### Test Structure

Tests are markdown spec files in `tests/x/specs/` organized by category:

- `core/` — Language fundamentals (evaluation, forms, closures, logic, arithmetic, strings, etc.)
- `applicative/` — Higher-order function tests
- `ext/` — Extension types (bignum, float, rational, complex, regex, compile, POSIX)
- `lib/` — Standard library functions
- `e2e/` — End-to-end integration tests
- `tools/` — Tool tests (lint, fmt)

### Running Tests

```sh
make test-x          # x-lang spec suite
make test-c          # C unit tests
make test            # all tests (the full gate)
make test-asan       # both suites under AddressSanitizer (memory-safety net)
```

### Adding Tests

Tests use a markdown format where each `###` heading is a test:

```markdown
## section-name

### test description

\`\`\`scheme
(expression)
\`\`\`
---
    expected output
```

The spec runner evaluates the `scheme` code block and compares stdout against the indented expected output after the `---` separator.

> **Last line only (default).** By default the runner compares only the **last non-empty stdout line**, and stderr is discarded. To assert a single multi-value result this way, put it on one line (e.g. `(display a)(display " ")(display b)`).
>
> **Multi-line output (`` ```output ``).** Fence the expected block as `` ```output `` to compare the **full multi-line stdout** instead — for formatters, pretty-printers, and any multi-line render. Leading blank lines are ignored and the trailing newline is trimmed; interior blank lines are significant. Errors are catchable too: the runner prints an uncaught error to stdout as `Error: <value>`, so a `` ```output `` block can assert it (or use `raised`/`throws?`). See `tests/x/specs/meta/multiline.spec.md`.
>
> A spec can swap in a custom support library with a `# @lib ../tests/x/lib/NAME.x` header — it *replaces* the default lib, so the support file must `(include "lib/x-core.x")` first (see `tests/x/lib/token.x`).

### The test-with-fix rule

**Every bug fix ships with a regression test in the same commit**, written so it **fails before the fix and passes after** — confirm both. A fix without a test that proves it is incomplete: nothing stops the bug from returning. This is the project's main defense against recurring "should-have-been-caught" regressions. A `fix:` commit that touches no `tests/` file is the smell to avoid.

### Error-path assertions

`tests/x/lib/assert.x` names the "this must raise" pattern, so the silent-failure class (a form that should raise but returns nil) can't read as a pass. Add `# @lib ../tests/x/lib/assert.x` to a spec, then:

- `(throws? (fn (_) EXPR))` → `#t` if `EXPR` raises, else `#f`
- `(raised  (fn (_) EXPR))` → the value `EXPR` raised, or the symbol `%no-raise`

### Memory safety (AddressSanitizer)

`make test-asan` runs both suites against an ASan build. It catches the crash class that is silently wrong on 64-bit but faults on 32-bit/Pi (e.g. an unchecked read past an object) — run it before pushing C or eval-core changes. The baseline is **clean** (since 2026-07-13) and CI hard-gates it: a red ASan run is a real regression. Note the pinned `ASAN_OPTIONS` in the Makefile — leak detection is off (the GC does not free at exit) and so is the fake stack (incompatible with stack-copying call/cc).

### Pre-push gate

```sh
make install-hooks   # sets core.hooksPath=.githooks
```

The hook hard-gates on `make test` (both suites) and blocks the push if it fails (bypass a single push with `git push --no-verify`). `make test-asan` is green at HEAD but slow (~2-3x), so locally it stays opt-in — `RUN_ASAN=1` runs it non-blocking; CI hard-gates it on every push regardless.

### CI

GitHub Actions (`.github/workflows/ci.yml`) hard-gates every push and pull request on `make test` (macOS + Linux) **and** `make test-asan` (Linux). The pre-push hook remains the first line of defence: it catches a red suite before it leaves the machine.

## Commit Conventions

This project follows [AngularJS commit conventions](CONVENTIONS.md):

```
<type>(<scope>): <subject>
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`

Only `feat` and `fix` appear in changelogs.

## Documentation

### Generating Docs

```sh
make doc-c           # C API reference (Doxygen → docs/ref/c/)
make doc-x           # x-lang library reference (doc-gen → docs/ref/x/)
make doc             # both
```

### Adding Library Documentation

Wrap function definitions in `(doc ...)`:

```scheme
(doc (def my-function
  (fn (_ x y)
    (+ x y)))
  (param x INTEGER "First operand")
  (param y INTEGER "Second operand")
  (returns INTEGER "Sum of x and y")
  "Add two integers.")
```

The `(doc ...)` form is transparent — it evaluates the inner `def` normally, then registers metadata for the doc generator.

## License

MIT No Attribution (MIT-0)

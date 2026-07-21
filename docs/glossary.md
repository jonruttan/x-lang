# Glossary

One name per concept. This page owns the cross-layer vocabulary; the normative
anchors it defers to are the absence discipline (spec.md, "Nil, false, and
truthiness") and the method-naming adjudications in
[contributing.md](contributing.md). Terms are added here as naming decisions
are settled (tracked in issue #42 and #44).

## Association vocabulary

- **assoc** — one dotted `(key . val)` pair: a single association. `List assoc`
  / `List assq` return the assoc itself.
- **alist** — a list of assocs: `((k1 . v1) (k2 . v2) ...)`. The associative
  wire format of the library: pairing producers (`List zip`, `Gen zip`,
  `Gen enumerate`, `List group-by`, `Dict ->alist`) emit alists, and the keyed
  consumers (`Assoc` API, `Dict from-alist`) take them. Keys in the alist layer
  compare with `eq?`.
- **plist** — the flat `(k v k v ...)` shape. Legal only in **option stores**.
- **option store** — an argument accepting an alist *or* a plist, walked by
  `%opt-cell`: `let-opts`, `Assoc get-or`/`opt-get-or`/`opt-get-or-else`, and
  object initialization (`new`, `new-from`). Everything else — including
  `Dict` and JSON — is alist-only.
- **bindings list** — `((key value) ...)` two-element lists, the shape `let`
  uses. Bridged to alists by `Assoc from-bindings` / `Assoc ->bindings`.

## the layers

- **x-expr** (`ext/x-expr/`) — the expression engine submodule: objects,
  storage, GC, the base tree. Below the language.
- **the C core** — the interpreter's instruction set (the ISA, cataloged in
  `tools/isa.x`): evaluator, tokenizer driver, primitives. Deliberately
  "just enough"; unchecked by design — guards live in x-lang.
- **the type system** — runtime type structs with dispatch methods; types
  and the base share one nested-list contract pattern.
- **the library** (`lib/`) — everything else, written in x-lang, composed
  into **dialects** (helium, xenon, radon); whole surface languages load as
  **personalities**.

## the dialects (noble gases)

Atomic weight = library weight; radioactivity = instability. Dialects may
differ in what surface is *loaded*, never in what a shared spelling *means*
(same-spelling-different-meaning is personality territory).

- **helium** (`he`, `lib/he.x`) — light: fast boot, interactive, no numeric
  tower. The default; `lib/x.x` is a pointer to it.
- **xenon** (`xe`, `lib/xe.x`) — heavy and inert: the full numeric tower,
  POSIX, the compiler; the stable full-stack surface.
- **radon** (`rn`, `lib/rn.x`) — heavy and radioactive: xenon's surface
  plus the experimental/raw APIs (syscalls, opt-in file I/O and sockets);
  explicitly volatile.
- **x-lang** — the *language's* name only, never a dialect's. Retired
  dialect spellings `x-and`/`x-or` shim to xenon/radon for one release.

## combiners

One concept per register; don't mix registers within a document:

- **surface**: `fn` / `op` — what programs say.
- **C types**: `procedure` / `operative` — what the implementation says.
- **theory** (docs, comments): `applicative` / `fexpr` — what papers say.
- **combiner** is the umbrella for anything callable; **`wrap`** turns an
  operative into an applicative.

## nil and null

Prose says **nil**, always. The word "null" survives in exactly three
registers: `null?` (the nil predicate — historical, spec'd API), the
`null` **symbol** (a boundary's foreign null, e.g. JSON), and "the null
byte" (`\0`). None of them is a fourth falsy value: falsy is {nil, `#f`}.

## sentinel (two senses — always qualify)

- **value sentinel** — a stand-in *inside the value domain* (`-1` for a
  miss, a magic string). FORBIDDEN by the absence discipline; misses are
  nil behind presence doors. (Two blessed exceptions: `raised`'s `%no-raise`,
  OS-domain `-1` — see contributing.)
- **identity sentinel** — a unique *object* compared by `eq?` to mark a
  mechanism's own state (the TCO tag). Blessed internal technique.

## scoped words (same spelling, different domains — deliberate)

- **head / tail** in C are always *chain-position* words (the front or end
  pointer of a linked chain: `p_head`, `p_tail`) — never element accessors
  (those are `first`/`rest`); *tail call* / TCO is a separate compound.
- **table** in C is a static array of entries (a bind table,
  `x_callable_entry_t[]`); the hash container is `Dict`; keyed pair-lists
  are alists. Three structures, three words.
- **signal** means OS signals (`x_signal`, SIGINT) — errors are *raised*
  and *propagated*, never "signaled".
- **init** on List is Haskell's all-but-last (the `last` twin) — unrelated
  to constructor initialization. **reject** on List is the filter
  complement; in the tokenizer protocol it is the no-match terminator
  (accept / accept-inclusive / reject) — each is coherent in its domain.
- **Utf8** names exactly one thing: the byte↔code-point *codec* class
  (`x/codec/utf8` — `decode`/`encode`/`width`). The string classes are
  `Str8`/`StrUTF8` with ambient `Str`; the old `Utf8` *string-class alias*
  is retired and must not come back.

## core and base

- **core** carries three senses — the C interpreter core, `lib/x/core/`,
  and the bootstrap core (`x-core.x`, the module manifest every dialect
  loads first; internal, not a user-facing dialect); say which.
- **base** — the interpreter's root context object (`p_base`): execution
  context only. Not nil (`()` is `NULL`), and not the environment — the
  binding structure (`env`) lives *on* the base.

## symbol (a cross-layer trap)

From the C layer up, a **symbol** is the interned name type. Inside
x-expr, every `SYMBOL`-named macro (`X_TYPE_*_SYMBOL`, `X_OBJ_TRUE_SYMBOL`)
means *a C string* — the interned type doesn't exist down there. Read
x-expr's "symbol" as "name text".

## vector, atom, pair — and Array

- **vector** — the fundamental fixed-size structural shape: N contiguous
  object slots. Everything is a vector. The **atom** is the one-slot vector;
  the **pair** is the two-slot vector; the user-facing `Vector` type is the
  same shape with the length exposed. Structural tier: plain values,
  data-last static methods.
- **Array** — NOT a vector: a growable stateful *container* (Dict/Set tier,
  instance dispatch) wrapping a vector backing store that doubles on
  overflow. Fixed extent and value semantics → `Vector`; growth and
  in-place mutation → `Array`.

## generator vs iterator

- **generator** — the pure step contract: `(step state) -> (value . next-state)`,
  or `()` when exhausted. THE iteration concept of the tower: Seq's cursor
  triad speaks it per type, `Gen` is the composable lazy pipeline over it, and
  the C layer's per-type steps implement it allocation-free (the cell ABI).
  A `Gen` is persistent: driving it consumes nothing, so it can be re-driven.
- **iterator** — a specific form of generator: a generator boxed with a cursor
  cell, `[step . state]`, driven by `(Iter next)` — which owns the single
  mutation (the box write-back; steps themselves never mutate). Ephemeral and
  drain-once by nature. `(Iter step it)` is the functional door back to the
  generator view: `(value . next-iterator)` with the source untouched.
- Corollary conventions: def-class instances (like `Gen`) speak message-send;
  raw typed values (like iterators) get static data-last methods and are
  fluent anyway through value-call dispatch. And as with length/count: strict
  collections take counts (`List repeat n x`), lazy streams are infinite and
  you `take` (`Gen repeat x`).

## length vs count

- **length** — the element count as a *property*: the noun you ask of any
  finite collection (List, Vector, Array, Str8, StrUTF8, Seq, Dict, Set). The
  interface word describes the meaning, not the cost — `StrUTF8 length` is
  O(n) under the hood, `Dict length` O(1).
- **width** — display columns, exclusively. Never byte counts: `str-length`
  is bytes, `Str length` is code points, and neither is a column count for
  double-width or combining glyphs. Column math (Fmt) counts code points —
  correct except for those glyph classes; true wcwidth-style tables are a
  known gap. Padding (`pad-left`/`pad-right`) is by *elements*, not columns.
- **count** — the *action* of tallying. Reserved for genuine acts: `Gen count`
  (consumes the stream; a lazy stream has no length property — strict
  collections have a `length`, lazy streams you `count`), `Seq count` (the
  cursor-walk that the default `length` is implemented by), `Heap count`
  (walks the heap chain), and the verb-compounds `count-if`, `match-count`,
  `count-from`.

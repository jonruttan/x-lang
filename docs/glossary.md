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
  finite collection (List, Vector, Vec, Str8, StrUTF8, Seq, Dict, Set). The
  interface word describes the meaning, not the cost — `StrUTF8 length` is
  O(n) under the hood, `Dict length` O(1).
- **count** — the *action* of tallying. Reserved for genuine acts: `Gen count`
  (consumes the stream; a lazy stream has no length property — strict
  collections have a `length`, lazy streams you `count`), `Seq count` (the
  cursor-walk that the default `length` is implemented by), `Heap count`
  (walks the heap chain), and the verb-compounds `count-if`, `match-count`,
  `count-from`.

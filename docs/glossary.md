# Glossary

The names shared across engines. The contract's files are the authority
on what things are called: a name used in `tools/contract/`, the
conformance suite, or this glossary is THE name, and every engine's
identifiers use these nouns under its own affix conventions (`x_` and
snake case in C; modules and snake case in Rust). A word that appears in
neither the contract nor this file is engine-private, and stays out of
contract prose, commit messages and reviews.

Choosing a name: the contract's existing name wins; failing that, the
name the library already uses; failing that, the clearer word, whichever
implementation coined it. A name states what a thing IS, not what
structure it takes; "spine" and "tree" belong only in sentences about
layout. The type-system words below carry their standard meanings
(Pierce, *Types and Programming Languages*; ISO C; the Common Lisp
HyperSpec), and a classifying noun not listed here has no meaning in
this tree.

## Values and types

- **value** — what evaluating an expression yields: the meaning of an
  object's contents under its type. A value is represented by an object;
  it is not one.
- **type** — a classification of values: the set of values it admits and
  the operations valid on them. A class is a type; a doc annotation names
  a type. `42 : INTEGER`.
- **runtime type** — the object a value's type label points to and a
  handle resolves to: its name, its units, and its handlers. Registered
  in the base's **type-alist**, keyed by handle; the engine dispatches
  eval, call, read and write on it. Not "tree", "struct" or
  "descriptor".
- **kind** — the type of a type. `CLASS`, the runtime type of every
  class, is one. The word means nothing else here.
- **handle** — the key a runtime type is filed and looked up under. Its
  text is the type's **name**.
- **handler** — behaviour registered on a runtime type: `eval`, `call`,
  `analyse`, `read`, `write`, `display`, and the rest of the families the
  `type-*` routes name.
- **family** — one handler name across every runtime type: the `eval`
  family, the `write` family. Nothing else is called a family.
- **stack** — a handler family's slot holds a stack; the head is the
  active handler, and pushing shadows without destroying.
- **variant** — one alternative of a type whose values are each exactly
  one of several: an io error is a variant of ERR; a decimal token is a
  variant of what the integer analyser accepts.
- **label** — the value a variant carries that says which variant it is:
  an error's `'io`, read by `(Err label e)`; the alternative an analyser
  state accepted, written by `%score-label!`; the type label in an
  object's header; a unit's `ref`. Never "tag", never "kind". An
  assembler's label, a named position in emitted code, is the word's
  other use, in the JIT and in x-cc.
- **conversion** — an operation yielding a value of one type from a value
  of another: a runtime type's `from` and `to` handlers, `(Convert to v
  target)`. A **coercion** is a conversion the language inserts unasked
  (count and index seats coerce to INTEGER). A **promotion** is a
  conversion to a type holding every value of the source type (the
  numeric tower promotes).
- **annotation** — the type a `(param x T ...)` or `(returns T ...)` doc
  form states. T is a runtime type's name (`INTEGER`, `STRING`,
  `CHARACTER`, `POINTER`, ...), a class's name as spelled (`Dict`,
  `Gen`), or one of `ANY` (every value), `NUMBER` and `CALLABLE`
  (unions), `ALIST`, `TYPE` (a runtime type's handle). Unions are written
  `INTEGER|BIGINT`. Documentation only.

## Objects and classes

- **object** — two meanings, scoped by layer. In the engines, the
  contract and the reflection layer (`x_obj_t`, `obj-layout.x`, `Obj`,
  `%obj-*`): a storage object, a vector of units laid out as a header
  (heap link, type label, flags) and data units; an atom has one data
  unit, a pair two. Its contents represent a value, read through its
  type label. In the class system (`object?`, OBJECT): an instance of a
  class. Where a passage needs both, it says "storage object" and
  "class instance".
- **unit** — one word of a storage object. A runtime type declares how
  many data units its instances have.
- **unit label** — which of four variants a unit is, which decides who
  may touch it: `ref` (a heap object pointer; the collector traces it),
  `word` (an immediate; nothing dereferences it), `bytes` (a pointer to
  bytes the type can measure), `foreign` (an address C owns). Declared
  with `(type set-unit-labels!)`.
- **layout** — the positional arrangement of a data structure: which
  unit or element sits where. `obj-layout.x` and `base-layout.x` declare
  the engine's.
- **class** — a definition of the fields and methods its instances share,
  made by `def-class`. A class is a type, and is itself a value of
  runtime type CLASS.
- **instance** — a value of a class (`new`), or of a runtime type
  (`Type make-instance`).
- **field** — a named component of a record or object: an instance's
  data (`(field 'n)`, `set-field!`), a def-record's components, a leaf of
  the base tree or of a runtime type (`x_eval_field_*`,
  `x_type_field_*`). A class's own data, declared in `(static ...)`, is
  a **static field**.
- **member** — a field or a method. A **static member** is a static
  field or a static method.
- **slot** — a raw position in a storage object: `Obj ref`, a runtime
  type's units.
- **method** — a function chosen by dispatch on a class or a type; a
  **generic function** (`def-generic`, `on`) chooses by the types of
  several arguments.
- **subclass** — a class declared with `(extends Other)`; `instance-of?`
  answers membership along the chain.
- **visibility** — who may reach a member: `private`, `protected` or
  public.

## Guest languages

- **C type, Python type, awk type, ...** — a lang bundle's guest language
  has types of its own, named with the guest standard's word and always
  qualified by the language, in identifiers and prose: "C type",
  `c-type-size`, `%cc-c-type-of`. The head symbol of a C type (`ptr`,
  `array`, `struct`, or the scalar itself) is its type category
  (C11 6.2.5).
- **file type** — POSIX's classification of a file: `'file 'dir 'link
  'char 'block 'fifo 'socket 'unknown`, the `'file-type` key of
  `(File stat p)`.

## The context

- **base** — the execution context: one self-describing structure
  carrying the interpreter's state. There is nothing above it; "engine"
  names an implementation, never a value.
- **route** — a committed path through the base, declared in
  `base-paths.x` and resolved by name. The steps are the engine's; the
  names are the contract's.
- **cell** — what a route ends at: the pair whose first is the value.
- **catalogue** — the base's registry of instructions,
  `((ns . ((method . instruction) ...)) ...)`, reached by the `prims`
  route.
- **frame** — one environment's bindings; frames chain outward to
  enclosing scopes. The current environment is part of the evaluation,
  however an engine spells it.
- **save stack** — the environments a closure body holds over its
  non-tail forms, one pointer each; operatives and sequences hold none.
  It used to decide whether a `def` is top-level, which made a def in tail
  position global; a `def` now binds in the current environment, whatever
  the stack says, and `eval!` evaluates its form in the root whatever
  frame called it.
- **environment** — a first-class value, one pair `(bindings . parent)`:
  the root's bindings are a tree and its parent nil; every other
  environment keeps an alist and the environment it was made in. A call
  makes a child; an operative receives the caller's as a value; `eval`
  with one makes it current.
- **tco-expr, tco-env** — the deferred tail: the expression a body left
  for its caller's loop, and the restore that travels with it. Base
  fields, named by their rows.

## The platform

- **layer** — a level of the architecture, built on the levels below
  it. `architecture.md` names four.
- **group** — a capability group: a set of instructions an engine offers
  together, declared in `features.x`. The groups partition the ISA.
  Nothing else is called a group.
- **profile** — a named set of capability groups an engine can aim at:
  `core`, `gc`, `posix`, `full`, each including the one before it.
- **mode** — a configuration the program runs in: batch or interactive,
  a repository or an installed tree, the JIT's analyser or integer
  calling convention. A stored symbol that names one alternative is a
  label.

## Callables

- **entry** — slot 0 of every callable: where applying it begins. An
  instruction's entry is itself; a closure's names the code that binds
  and runs it. The C stores a function pointer; Rust stores an
  instruction index.
- **state** — slot 1 of a callable: what its entry uses.
  `(params body env . bst)` for a closure, `(params envname body . env)`
  for an operative, the combiner for a wrap.
- **instruction** — one row of the ISA: a bare name and/or a catalogue
  coordinate, and one function behind it. Arguments arrive as written;
  an instruction that wants values evaluates them itself.
- **shape** — the signature of a block-form callback, which says what
  the names in its binding list receive: `element`, `pair`, `fold`,
  `binary` or `thunk`. Nothing else is called a shape.

## Reading

- **buffer** — the reader's window: `(val . (read . write))` cells over
  a text, with byte-offset marks.
- **token** — what a read handler answers for a span the competition
  awarded it.
- **competition** — how the reader chooses: every registered type's
  analyse handlers score a position, and the best claim wins. A type
  with no read handler discards its span.

## Text

- **width** — how much horizontal room a rendered form takes, counted in
  **code points**. Not bytes: `(Str8 length s)` counts bytes and overstates
  any non-ASCII text, so a byte count wraps lines that would have fit. Not
  true display columns either — double-width CJK and zero-width combining
  marks need a wcwidth-style table, a known gap (#44 N3). So "width" names
  the code-point count wherever the library says it, and the other two
  measures are named outright when they are meant. `(Fmt width form)`
  measures a form, `(Str length s)` a string.

## Collections

- **length** — the element count as a property, asked of any finite
  collection (List, Vector, Array, Str8, StrUtf8, Seq, Dict, Set). The
  word describes the meaning, not the cost: `StrUtf8 length` is O(n),
  `Dict length` O(1).
- **count** — the act of tallying, reserved for genuine acts: `Gen count`
  (consumes the stream; a lazy stream has no length), `Seq count` (the
  cursor walk the default `length` delegates to), `Heap count` (walks the
  heap chain), and the verb compounds `count-if`, `match-count`,
  `count-from`.
- **assoc** — one dotted `(key . val)` pair. `Assoc find` and
  `Assoc entry` answer the assoc itself.
- **alist** — a list of assocs, `((k1 . v1) (k2 . v2) ...)`: the
  associative wire format. Pairing producers (`List zip`, `Gen zip`,
  `Gen enumerate`, `List group-by`, `Dict ->alist`) emit alists; keyed
  consumers (`Assoc`, `Dict from-alist`) take them. Keys compare with
  `eq?`.
- **plist** — the flat `(k v k v ...)` form, legal only in option stores.
- **option store** — an argument accepting an alist or a plist, walked by
  `%opt-cell`: `let-opts`, `Assoc get-or`/`opt-get-or`/`opt-get-or-else`,
  and object initialisation (`new`, `new-from`). Everything else,
  `Dict` and JSON included, is alist-only.
- **bindings list** — `((key value) ...)` two-element lists, the form
  `let` uses; `Assoc from-bindings` / `Assoc ->bindings` bridge it.
- **generator** — the pure step contract: `(step state) -> (value .
  next-state)`, or `()` when exhausted. `Gen` is the lazy pipeline over
  it, persistent: driving it consumes nothing.
- **iterator** — a generator boxed with a cursor cell, `[step . state]`,
  driven by `(Iter next)`, which owns the one mutation. Ephemeral,
  drained once. `(Iter step it)` is the functional door back to the
  generator view.
- **vector** — the fixed-size structural form: N contiguous slots. The
  atom is the one-slot vector, the pair the two-slot vector, and the
  `Vector` type the same form with the length exposed.
- **Array** — a growable container (instance dispatch) over a vector
  backing store. Fixed extent and value semantics: `Vector`; growth and
  in-place mutation: `Array`.

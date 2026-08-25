# Glossary

The names shared across engines. The contract's files are the authority
on what things are called: a name used in `tools/contract/`, the conformance suite, or this
glossary is THE name, and every engine's identifiers use these nouns
under its own affix conventions (`x_` and snake case in C; modules and
snake case in Rust). A word that appears in neither the contract nor
this file is engine-private, and stays out of contract prose, commit
messages and reviews.

Choosing a name: the contract's existing name wins; failing that, the
name the library already uses; failing that, the clearer word, whichever
implementation coined it. A name states what a thing IS, not what shape
it takes; "spine" and "tree" belong only in sentences about layout.

## The context

- **base** — the execution context: one self-describing structure
  carrying the interpreter's state. There is nothing above it; "engine"
  names an implementation, never a value.
- **route** — a committed path through the base, declared in
  `base-paths.x` and resolved by name. The steps are the engine's; the
  names are the contract's.
- **cell** — what a route ends at: the pair whose first is the value.
- **catalog** — the base's registry of instructions,
  `((ns . ((method . instruction) ...)) ...)`, reached by the `prims`
  route.
- **frame** — one environment's bindings; frames chain outward to
  enclosing scopes. The current environment is part of the evaluation,
  however an engine spells it.
- **save stack** — what decides whether a definition is top-level: a
  `def` made while it is empty binds globally. Closure bodies hold a
  save over their non-tail forms; operatives and sequences hold none.
- **tco-expr, tco-env** — the deferred tail: the expression a body left
  for its caller's loop, and the restore that travels with it. Base
  fields, named by their rows.

## Types

- **type** — the object a value carries and a handle resolves to: its
  name, its units, and its handlers. Registered in the base's
  **type-alist**, keyed by handle. Not "tree", "struct" or "descriptor".
- **handle** — the key a type is filed and looked up under. Its text is
  the type's **name**.
- **handler** — behaviour registered on a type: `eval`, `call`,
  `analyse`, `read`, `write`, `display`, and the rest of the families
  the `type-*` routes name.
- **stack** — a handler family's slot holds a stack; the head is the
  active handler, and pushing shadows without destroying.

## Callables

- **entry** — slot 0 of every callable: where applying it begins. An
  instruction's entry is itself; a closure's names the code that binds
  and runs it. The C stores a function pointer; Rust stores an
  instruction index.
- **state** — slot 1 of a callable: what its entry uses.
  `(params body env . bst)` for a closure, `(params envname body . env)`
  for an operative, the combiner for a wrap.
- **instruction** — one row of the ISA: a bare name and/or a catalog
  coordinate, and one function behind it. Arguments arrive as written;
  an instruction that wants values evaluates them itself.

## Reading

- **buffer** — the reader's window: `(val . (read . write))` cells over
  a text, with byte-offset marks.
- **token** — what a read handler answers for a span the competition
  awarded it.
- **competition** — how the reader chooses: every registered type's
  analyse handlers score a position, and the best claim wins. A type
  with no read handler discards its span.

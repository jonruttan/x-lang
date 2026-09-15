# First-Class Environments

*x-lang: computational expressions over a minimal, type-agnostic engine.*

This is a design proposal for the engine's environment model. Nothing in it
is implemented. It sits beside [The Engine Contract](engine-contract.md)
because it changes the base-layout contract, and the language owns the
terms an engine is judged by. The language-level design it serves is
[Namespaces](namespaces.md).

## Why

An environment today is a cons chain of binding cells. A frame is the run
of cells at the head that carry a frame mark, and the only thing that
identifies a frame is the head pointer the current activation holds. Six
mechanisms exist to compensate for that one fact:

| mechanism | what it compensates for |
|---|---|
| the frame and function-frame flag bits on cells | lookup cannot tell a frame from the global region without a mark |
| the local boundary | the restore protocol needs to know where the frame region ends |
| the shadow list | an earlier fix for locals hiding globals, retired in spirit by the marks, still restored |
| the operative restore's walk to the operative's head | the body may have grown the caller's chain, or may not, and only a walk can tell |
| the top-level bracket that strips the leading frame run and parks it | a file's forms and `eval!` must bind globally from inside frames |
| `def-global` | a definition made inside a frame that must land in the global tree |

And one consequence the language keeps meeting: an operative cannot define
for its caller. Its `def` extends its own frame, which the restore drops. A
tail-evaluated `def` grows the caller's chain in front of a head the
caller's own saved compound still points at, which the next restore drops.
That is jonruttan/x-lang#527, the reason every lang's `define` is a
tail-position trick, and the reason x-engine-c#46 asked for one more
primitive, `def-in`, before this note replaced it.

A closure also captures the global tree's root at creation and reinstalls it
on each call, so a closure made in a child base can miss a global defined
after it. That is a second identity problem: the global environment has no
object either, only a root pointer.

## The model

An environment is one pair:

```
(bindings . parent)
```

`bindings` is a chain of `(name . value)` cells, or the root's tree.
`parent` is the enclosing environment, or nil at the root. That is the whole
representation. It is a pair tree like everything else in the base, so
`first` and `rest` walk it and the collector marks it with no special case.

The rules, in full:

- **Lookup.** Search `bindings`, then the parent's, up to the root. The
  root's bindings may be a tree for speed; that is an implementation detail
  of one environment, not a separate global region.
- **`def`.** Bind in the current environment: update the name's cell in this
  environment's bindings if it has one, otherwise add one. Never the parent.
- **`set!`.** Find the name by lookup and update the cell where it is found.
  An unbound name is an error, as now.
- **Procedure call.** Make a child of the closure's environment, bind the
  parameters in it, evaluate the body with it current. Every call makes a
  child, a parameterless one too, so a body's definitions are private to
  the activation without exception.
- **Operative call.** Make a child of the operative's static environment,
  bind the formals to the unevaluated arguments and the env parameter to
  the caller's environment, evaluate the body with it current. The caller's
  environment is a value in the body, as now.
- **`eval` with an environment.** Make that environment current, evaluate,
  restore the previous one. A `def` inside binds in the given environment
  and stays bound, because the environment is an object and the binding is
  in it. `(eval (list 'def n v) e)` from an operative is the definer every
  lang wanted, with nothing added.
- **`eval!`.** Evaluate in the root. The loader evaluates a file's forms in
  the root the same way.
- **Save and restore.** The current environment is a pointer. Every place
  that today saves the chain head, the boundary, the tree and the shadow
  list saves one pointer and restores one pointer: the tail-call
  trampoline, `guard`, `call/cc`, the operative return.
- **Closures and operatives.** Capture the current environment object.
  Nothing else: no tree, no boundary.
- **`base bind`.** Bind in the target base's root. `def-global` becomes
  `def` evaluated with the root as its environment and needs no primitive.
- **Child bases.** A child base has its own root. A closure made in the
  parent and handed to the child reaches the parent's root through its own
  parent chain, which is what it does today by carrying the tree.

## What it removes

From the engine: the two flag bits and every test of them, the local
boundary, the shadow list, the reachability walk in the operative restore,
the top-level bracket's parking of frames on the root chain, the captured
tree in every closure, and `def-global`. The ISA manifest loses one row and
gains none.

From the language: the tail-position `define` trick in every lang, the
`def-global` door in x-python and x-sweet, and the whole of issue #527 and
issue #644 as concepts rather than as cases. A definer written as an
operative, `doc`, `def-class`, `def-record`, `def-generic`, a lang's
`define`, binds where its caller's environment says.

## What it gives the language

An environment is a value the language can make, hand around, and evaluate
in. That is the mechanism [Namespaces](namespaces.md) needs, and it is
smaller than what that note proposed:

- A module is an environment whose parent is the root. The loader makes
  one, evaluates the file's forms in it, and the module's private names
  are in it and nowhere else.
- `provide` copies the listed bindings into the root, or records them in
  the registry as the note describes. `import` binds the chosen names into
  the importer's environment, which is a `def` evaluated there.
- A lang chooses its paradigm with two operations, make a child and
  evaluate in an environment. Kernel's `$define!` is `def` in a named
  environment. Scheme's internal defines get `letrec` semantics because a
  body's definitions live in the body's own environment. A lang that wants
  Kernel's flat answer for a parameterless body evaluates in the parent
  instead. None of this is decided in C.
- Reflection is honest: an environment is a pair tree, and the toolkit that
  would have read a frame bit from the object layout is `first` and `rest`.

## What it costs

- **One pair per activation** beyond the parameter cells allocated today.
- **Lookup depth** is the lexical nesting, which is what the frame run
  walks today, so parity is the expectation. It is a measurement to take
  on the suite and on the JIT lane before anything moves.
- **The engine work** is a rewrite of the evaluator's environment layer,
  not a patch. Around 170 references across ten files touch the current
  mechanisms, most in the evaluator, the procedure and operative types,
  binding and control. It wants its own C spec coverage in the same
  change, and the bare suite's define cases from x-engine-c#47 carried
  over against plain `def`.
- **The base-layout contract changes.** The env, boundary, tree and shadow
  rows go, replaced by one row for the current environment. x-lang's
  readers of those rows are few: the image tools, the sandbox spec, lint
  and coverage, plus the `Base cell` door. They move in the same pin bump.
- **Images.** An environment is heap structure; the writer's one known
  weak spot, a global mutated after the image was cut, is unchanged.

## Measurements before it lands

- Suite time from source and the JIT lane, old model against new, on the
  same box.
- Allocation count per boot, because every call now allocates one more
  pair and the writers' peaks are measured in objects.
- The state-image round trip of a booted dialect.
- The two envelope cases that motivated the marks: a parameter named after
  a global operative, and a top-level definition named like an operative's
  env parameter, both from `tests/x/specs/core/env-scope.spec.md`.

## Sequence

1. This note, reviewed.
2. The engine change on a branch, with C and bare specs, measured against
   x-lang's suite from source.
3. The contract rows, the declaration regenerated, a release cut, and the
   pin bump in x-lang with its few readers moved.
4. The langs drop their `define` tricks and `def-global` doors.
5. Namespaces, on the environment the engine now has.

## Open questions

- Whether the root's bindings stay a tree. They can, inside the root
  environment, and nothing else needs to know.
- Whether `guard` binds its error variable in a fresh child or in the
  current environment. A child is the consistent answer.
- What a continuation captures: the current environment pointer, which is
  all the restore protocol keeps.

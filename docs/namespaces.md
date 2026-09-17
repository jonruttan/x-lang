# Namespaces for the Library

*x-lang: computational expressions over a minimal, type-agnostic engine.*

This is a design proposal. Nothing in it is implemented. The measurements
were taken on the tree at `b11084e9` (2026-09-14) and are reproducible
with the commands beside them.

The proposal has three parts: a module gets a scope of its own, `provide`
and `import` become the only doors through that scope, and every name
conflict the doors can meet has a stated rule. The third part is a
requirement of the design, not a consequence of it: a scheme that removes
some collisions and leaves the rest silent is not an improvement over the
ratchets we have.

## Where names live today

The environment is one global tree plus lexical frames. A frame exists for
a closure's parameters, a `let`, a `guard` variable, and a `def` made in a
closure body. Everything else is global: every top-level form of every
module binds in the global tree, whatever file it came from.

`provide` records a module's export list in the registry and binds nothing.
`(import x/core/list)` loads the file once by name. The selective form
`(import x/core/list map filter)` checks that the names are in the export
list and binds nothing either. See [Modules](modules.md).

Three mechanisms already do part of a namespace's job:

- **Classes.** A class holds static methods and members, so `(List map …)`
  is a qualified call and `Pin` homes a whole tool under one global. A
  `%`-prefixed static is private by convention; a `(private …)` block is
  private in fact. Static dispatch costs 8 to 30 times a direct call, which
  is why hot helpers are kept as bare globals on purpose.
- **The catalog.** `(prim-ref ns name)` is a two-level table with a
  producer door, `prim-reg!`. It is the C surface, and the ISA check
  rejects an x-side alias of a C primitive filed there.
- **Slash-qualified names in the docs.** `(help Str8/split)` and
  `(help x/core/list)` key on a slash, but to the evaluator a slash is a
  symbol character and nothing more.

None of the three gives a module a private name.

| measured on `lib/x/**` | count |
|---|---:|
| top-level `%` definitions | 2,045 |
| distinct `%` names referenced from a file other than their definer | 353 of 1,793 |
| `%` names defined in more than one file | 72 |
| `%` definitions that only cache a catalog fetch | 427 |
| bare top-level definitions | 313 |
| classes | 75 |

The counts come from `tools/check/defs.awk` over `lib/`, the same scanner
the ratchets use. Three ratchets hold the line by counting rather than by
scope: `tools/check/bare-globals.sh`, `tools/check/percent-globals.sh` and
`tools/check/dup-defs.sh`. What they cannot prevent is recorded in the
tree: `lib/x/core/logic.x` keeps `%equal?` because a lang bundle rebound
`equal?` and retargeted the collection classes through it, and
[Crafting a Lang](crafting-a-lang.md) records four collisions among one
lang's `%`-prefixed names.

## The design

### A module is one frame

The loader evaluates a module's forms as the body of a single closure. A
`def` at the module's top level then lands in that frame, and a closure
defined in the module captures the frame. Symbol lookup walks the frame
region before the global tree, so a module's own names resolve ahead of any
global, and a caller's parameter of the same name cannot reach them.

This part works on the current engine. Checked by hand: definitions made in
a closure body stay private, an escaping closure still resolves them after
recursion and tail calls, a caller parameter with the helper's name does not
shadow it, a global with the helper's name defined later does not shadow it,
and `set!` on module state persists.

### `provide` is the export

`provide` evaluates each listed name in the module's frame and records
`(name . value)` in the registry entry, so the registry entry is the
namespace. Names that are classes or in the sanctioned bare set
(`tools/contract/bare-globals.x`) are also bound in the root environment,
so `(List map …)`, `when`, `equal?` and `(help x/core/list)` behave as they
do now.

### `import` binds

`(import x/core/list map filter)` copies those two exports into the
importer's own frame. The bare form `(import x/core/list)` loads the module
and binds nothing locally; references from the importer resolve through the
global tree at call time, as today.

An importer that wants a whole module under one name takes it as a value:

```x
(def S (module x/type/str))
(S append a b)
```

A module value dispatches like a class's statics. It costs a dispatch per
call, so hot code uses a selective import, which is the same trade
`method-of` offers for classes.

### What does not change

Qualified symbols are not resolved by the evaluator. Symbol evaluation is C
with no library hook; a reader rewrite of `List/map` would collide with the
module-path symbols `import` takes; and the JIT resolves a free variable to
an object pointer at compile time. Qualified use stays `(Class method …)`,
a module value, or a selective import.

The REPL's top level stays the global tree. Module identity keeps its rules:
first root wins, one version per name per session, the boot set is
unpinnable.

## Name conflicts

Every conflict the design can meet falls into one of four classes. Each
class has one rule, and every refusal names both sides and the name.
Nothing is skipped silently; that is the same standard `Pin` holds.

### Private against private

Two modules define the same private name. Today this is a collision that
`dup-defs.sh` catches in source, with 72 such names live. Under module
frames it is not a conflict: each binding is lexical to its file and no
other file can see it. No rule is needed and no gate.

### Private against global

A module defines, for its own use, a name that also exists globally. The
local binding wins inside that module and nowhere else. The rest of the
session keeps the global. This is the rule that makes a lang's own
`equal?` harmless to the library.

Lint warns when a module-level definition shadows a name in the sanctioned
bare set, because it is usually a mistake. The warning is not an error: a
lang bundle does it on purpose.

### Export against export

Two modules `provide` the same global name, a bare name or a class. Today
the second load rewires every caller of the first, because top-level
redefinition updates the binding in place.

The registry records an owner per exported name, so the rule is one owner
per name:

- `provide` of a name another module already exports is an error:

      provide: x/foo exports map, owned by x/core/list

- The same module providing again is a reload and updates in place.
- A deliberate override says so, with a distinct form, and is recorded as
  `(name owner overridden-by)`. `(modules)` and `(help name)` show both.
  A lang installing its vocabulary for the session is the intended user.

### Import against import

Two selective imports, or an import and a local definition, want the same
name in one frame. The rule is one binding per name per frame:

- An import of a name already bound in the frame by a different module, or
  by the module's own definition, is an error:

      import: map from x/type/vector is already bound here by x/core/list
      import: map from x/core/list is already defined in this module

- The same import repeated is a no-op.
- Rename on import resolves a wanted collision. A `(name alias)` pair in
  the import list binds the export under the alias:

      (import x/type/str (append str-append))

- A module value is the other way out: nothing is bound bare.

### Early binding against late binding

One conflict is not between two names but between two meanings of one
reference, and it decides how the library protects itself from a lang.

A selective import copies the export's value into the importer's frame. A
later global rebind cannot retarget it. That is the fixed-name rule of
`%equal?` and `Str`/`Str8` made general: a module imports by name what it
must keep. A bare import leaves the reference late-bound through the global
tree, which is what the seams need: `repl` replaced by a lang, the `include`
wrapper, the `%repl-print` family that `Lang` installs.

So the choice is made per reference, visibly, by the author. Import a name
to freeze it. Leave it global to keep it a seam. Library internals freeze
what they use; declared seams stay late-bound and are listed as such in
[The Lang Contract](lang-contract.md).

Two consequences belong in the contract:

- **Mutable state does not cross by copy.** `set!` on an imported name
  mutates the importer's cell, not the module's. State a module shares is a
  cell or a class, which is the rule the boot registry cells already follow.
  Lint reports `set!` on an imported name.
- **Reload leaves copies stale.** Re-providing a module updates the globals
  in place, but a frame that copied an export keeps the old value. The REPL
  reports a re-provide, and `import-version` is the door for a deliberate
  refresh.

### The gates afterwards

- `dup-defs.sh` shrinks to what is still global: the boot set and exported
  names. Its runtime counterpart is the `provide` owner rule.
- `percent-globals.sh` retires for a scoped module. Its replacement is a
  check that no `%` name appears in a `provide` list.
- Lint treats a `%` name defined in another module as undefined, which is
  what it is.

## What the engine must provide

Inside a frame, only a bare `def` in body position binds. Every wrapped
definer binds nothing: `(doc (def …))`, `def-class`, `def-record`,
`def-generic`, and a `def` under `do` or `when`. Each was tested. The cause
is issue #527: an operative cannot define into its caller's frame, because
the operative's restore drops what its body added to the chain. The C loader
strips frames on purpose, and `eval` restores the environment, so no
library-side loader can route around this.

The first answer was one more primitive, a `def` directed at a given
environment. It worked and it was withdrawn, because it was a policy in C
compensating for the environment model rather than a capability the
language lacked. The answer this note now rests on is
[First-Class Environments](environment-model.md): an environment is a value,
`(eval (list 'def n v) e)` binds in `e`, a module is an environment whose
parent is the root, and the engine loses mechanisms rather than gaining
one. The loader, `provide` and `import` above are written against that
model.

## Sequence

1. Engine: first-class environments, per [environment-model.md](environment-model.md), with its specs and contract rows.
2. Library, no behaviour change: `doc`, `def-class`, `def-record`,
   `def-generic` and `def-trait` define through the caller's environment.
3. Loader: a framed path in `module.x`, switched per module, and the
   conflict rules above with their errors and specs. Start with leaves
   outside the boot closure: `x/tool`, `x/codec`, `apps`, the lang bundles.
4. `x/type` and `x/core`, then the boot files, which keeps the pin boundary
   where it is.
5. Retire the per-file `%` budget for scoped modules; land the replacement
   gates.

## What to measure first

- **Lookup cost.** Symbol lookup walks the whole frame region before the
  global tree. A module with a hundred private definitions taxes every
  global lookup made from inside it. Measure on a module the size of
  `class.x` before step 4.
- **Source boot time.** The image writers and the asan-boot gate boot from
  source. A framed load of `regex.x` through the x-side reader took the same
  time as the C include, so the loader is not the risk; the lookup cost is.
- **State images.** A frame-scoped module round-trips as heap structure.
  Run the image suite against a scoped leaf before step 4.
- **The JIT.** `asm-compile` resolves free variables to object pointers.
  Check it from inside a frame before `x/tool/asm` is scoped.
- **Coverage.** `cov-walk` enumerates the environment. The registry should
  hold each module's frame so scoped functions stay reported.

## Alternatives considered

- **Finish classes-as-namespaces and keep the flat environment.** It is the
  current direction and it covers the public surface. It cannot give a
  private name, it taxes hot code with dispatch, and it leaves lang bundles
  with prefixes as their only defence.
- **Namespace objects resolved by qualified symbols.** No evaluator hook,
  a reader-level rewrite collides with module paths, and the JIT's free
  variable resolution would need to learn the scheme. The qualified call is
  already `(Class method …)`.
- **A child base per module.** A child base has no numeric tower and no
  library; the lang work established that.

## Open questions

- The names of the new forms: the override form of `provide`, the module
  value form, and whether the alias pair is `(name alias)` or `(alias name)`.
- Whether the boot files are ever scoped, or whether the boot set stays
  global as the pin boundary already makes it.
- Answered: a scoped file needs neither. `import` loads it with the
  ordinary `include`, and its header reads the rest of the file with the
  reader, one form at a time, into the module's environment. The reader's
  `read` answers the EOF sentinel at end of input (x-engine-c v0.2.13), so
  a `()` in a module is a form rather than the end of the file.

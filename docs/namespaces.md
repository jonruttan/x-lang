# Namespaces for the Library

*x-lang: computational expressions over a minimal, type-agnostic engine.*

This began as a design proposal, and the design is built. A file headed
`(module NAME)` is a scoped module, and [Modules](modules.md#module-scope)
says how to write one. This document keeps the reasoning: the rules, what
was measured, and why each file without a scope has none. On 2026-09-28,
78 of the library's 138 files were scoped.

The counts under "Where names live today" describe the tree before any of
it. They were taken at `b11084e9` (2026-09-14) and are reproducible with
the commands beside them.

The design has three parts: a module gets a scope of its own, `provide`
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

- **Classes.** A class holds static methods and fields, so `(List map …)`
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
tree: a lang bundle rebound `equal?` and retargeted the collection classes
through it, which is why those modules import the name (see [Early binding
against late binding](#early-binding-against-late-binding)), and
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

The loader tells the two apart by the value and by a mark. A class is
recognised as one. A sanctioned name is marked where it is exported,
`(provide x/type/iter Iter (global iter))`, since the boot never loads the
contract file; `check-bare-globals` holds the marks to it in both
directions, so a mark on any other name, or a sanctioned name exported
unmarked, fails the gate.

### `import` binds

`(import x/core/list map filter)` copies those two exports into the
importer's own frame. The bare form `(import x/core/list)` loads the module
and binds nothing locally; references from the importer resolve through the
global tree at call time, as today -- which reaches only the module's
classes and marked names. Any other export is reached by importing it.

An importer that wants a whole module under one name takes it as a value:

```x
(def S (module x/type/str))
(S append a b)
```

A module value dispatches like a class's statics. It costs a dispatch per
call, so hot code uses a selective import, which is the same trade
`method-of` offers for classes.

A private name is read from outside through the module's environment:
`(eval (lit NAME) (module M))`. That is how a spec reaches an internal it
tests, and how a development tool reaches one it drives (decision of
2026-09-27). The module grows no public surface for either.

An unscoped importer's frame is the root, so its selective imports bind
there. That is how a hot dispatcher that stays unscoped takes the vocabulary
of modules that have scopes: `num/tower.x` imports the number modules'
operations (`big-add`, `f-add`, ...) at its top, listed name by name, and
each is a root binding by import -- the same surface those names had as
private globals, reached at root-lookup cost (decision of 2026-09-22).

A root name that other files extend in place with `set!` (`number?`,
`real?`: the number modules widen and narrow them as they load) is defined
in the root, never in a module. A module that defined it would keep calling
its own frame's binding, which the `set!` in the root never reaches.

The boot-layer walkers of `core/list.x` and `core/alist.x` are a sanctioned
shared vocabulary (decision of 2026-09-24): `%fold`, `%map`, `%map1`,
`%reverse`, `%length`, `%append`, `%append2`, `%filter`, `%find`, `%memq?`,
`%member-str?`, `%for-each`, `%rev-onto`, `%assoc-get`, `%assq`,
`%assoc-str`, `%assoc-has?` and `%assoc-keys` are the private layer the
`List` and `Assoc` classes stand on, and some forty files read them at the
root for speed, as those two files' provide notes say. They stay root
globals; a reader that wants a door takes the class. They are listed in
`tools/contract/shared-privates.x`, and the private-reads gate does not
count a read of a listed name (decision of 2026-09-27). The two files' other
private names are not in the list, and a read of one is counted against its
reader as before.

`type/convert.x` waited on the lang bundles. Its base type handles (`%int`,
`%string`, `%symbol`, `%char`, `%ptr`, `%pair`) were read by ten bundles as
well as by the library, so the door came first: `(Type named INTEGER)`, a
lookup by registered name through the type registry, which answers for any
type registered at the time and nil for a name nothing carries; the name is
written bare or quoted, and any other form is evaluated. The set
of types is open (the tower, a lang and a program register and retire
types), so the door is a lookup, not a list of statics. A scoped reader
fetches from the door at load. An unscoped one holds the handle in the
function that uses it, or asks the door in place where the read is cold. The
bundles moved as their `requires-release` pins moved to the release that
carries the door, and the file has its header now: its handles are its own.

Seven boot files cannot be modules at all: `boot/engine.x`, `registry.x`,
`operatives.x`, `data.x`, `reflect.x`, `printer.x` and `string.x` load before
`boot/module.x` defines the `module` form, and `module.x` is the loader
itself. Their private names stay in the root, behind the `%`-budget.

Fifty-nine of those names are read by other files: the pair setters, the
cell and word accessors, the byte-level string layer, the type words, the
state-image hooks, the registries and the resolver. They are a shared
vocabulary by decision (2026-09-27), and
`tools/contract/shared-privates.x` lists them name by name, with what each
is. The private-reads gate does not count a read of a listed name, and it
refuses a read of any other private name of a boot file, whatever the
reader's budget. So what the boot layer shares grows only by an edit to
that file, and a row goes once its name has no reader left.

The names a lang is promised stay `%` names in the root (decision of
2026-09-27). `repl/loop.x`, `repl/banner.x` and `reader/intrinsics.x` own
them, and stay unscoped for it. The gate takes the seam's names from
`tools/contract/seam.x`, which is the list already, and the four names of
the analyse protocol from the shared list, where each row names the
document that describes it to a lang's author
([Crafting a Lang](crafting-a-lang.md)). What those three files define
beyond the promised names is counted as any private read is.

The assembler's architecture backends (`tool/asm/arm64.x`, `tool/asm/x86_64.x`)
stay unscoped for a related reason: their bare names, the registers and the
push, pop and prologue helpers, are one interface with two implementations,
and `asm.x` picks one at load. A reader cannot import from a module chosen
at run time, so the interface stays in the root.

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
`Str`/`Str8` made general: a module imports by name what it must keep, as the
containers that compare by content do with `(import x/core/logic equal?)`. A
bare import leaves the reference late-bound through the global
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
- Until a module is scoped, its `%` names are still globals that other files
  can read. `private-reads.sh` budgets those reads per reader file
  (`tools/contract/private-reads.x`), so the number can only fall as step 4
  replaces each read with a door. The names read across files by decision
  are outside the count: those `tools/contract/shared-privates.x` lists,
  and the `%` names of the seam.

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
  - Measured, with the profile-only counter x-engine-c#59 put in the lookup
    loop: scoping `core/boolean` and `core/control` alone adds 34% to the
    environment comparisons of an x-core boot, 39% with a workload behind
    it and 42% at x-base, with evaluations and allocations unchanged. The
    cost is per lookup from inside the module, and those two modules'
    operatives are looked up from everywhere. So six modules stay unscoped
    by decision (2026-09-22): `core/boolean`, `core/control`, `core/syntax`,
    `core/predicates`, `sys/pact` and `num/tower`. Their 44 private names are
    read by nothing outside them, so a scope would buy only the frame, and
    the frame is what costs.
  - `core/arithmetic.x`, measured the same way once its readers fetched the
    integer primitives themselves (2026-09-24): a module header adds 3.6% to
    the environment comparisons of an x-core boot and 4.3 times to those of
    a 200,000-step loop of `=`, `-` and `+`, 124 more bindings compared per
    wrapper call, with evaluations and allocations unchanged. Its operator
    wrappers resolve `match`, `eq?`, `first`, `rest` and the saved primitive
    on every call, and the module frame would sit in front of each. It stays
    unscoped with the six.
  - `type/convert.x`, measured the same way (2026-09-26): a module header
    adds 0.02% to the environment comparisons of an x-core boot, where
    little converts. A conversion through the dispatcher compares about 740
    more bindings with the header, whatever it converts: 9% more on a loop
    of symbol to string, which costs 8,200 comparisons a conversion without
    it, and 5% more on integer to string and back. Evaluations and
    allocations are unchanged, at about 1,900 and 1,400 a conversion for
    symbol to string. The dispatcher is the cost, and the frame adds little
    to it, so the file is scoped.
  - `core/fn.x`, measured the same way (2026-09-27): a module header adds
    0.01% to the environment comparisons of an x-core boot, since the
    library's own callers keep the engine's `apply`. A call through the
    library's `apply` compares 161 more bindings with the header, 351 where
    it compared 190, with evaluations and allocations unchanged at 88 and 38
    a call. The door is small, so the frame would nearly double its lookups,
    for eight names hidden. The file is unscoped.
  - The six large files were measured the same way (2026-09-28) and held to
    one line (decision of 2026-09-27): a header goes on when it adds under
    0.1% to the environment comparisons of an x-core boot, and under 10% to
    those of the file's own work. `type/convert.x` had passed that line and
    `core/fn.x` had not. Each file was measured with its header on and a
    copy of its names left in the root for its readers, and in each the
    work's evaluations and allocations are unchanged. None passes, and the
    six stay unscoped.
    - `type/class.x`, 89 private names: 3.8 times the comparisons of an
      x-core boot, 185 million where it made 49 million, since every method
      call runs through the file. A static call compares 10.5 times as many
      bindings, an instance call 5.8 times and a `new` 8.6 times.
    - `doc/doc.x`, 73: 0.98% more at boot, 5.8 times for a `doc` form and
      6.3 times for an `apropos`.
    - `tool/lint.x`, 88: 33% more to lint an 87-line file, `codec/hex.x`.
      The x-core boot does not load it.
    - `tool/asm.x`, 43: 2.0 times for an instruction emitted, 15,000
      comparisons where it made 7,400. The x-core boot does not load it.
    - `codec/sha256.x`, 33: 37% more on a digest of 1 KB, and 13% more on
      a digest of one block. The x-core boot does not load it.
    - `boot/tower-compiled.x`, 47, cannot take a header as it stands: it is
      a load sequence, with six of its eight includes between its compiles,
      and a plain include has no place in a scoped file. Its twenty-one
      compile-site helpers were measured in a module of their own, and add
      0.05% to the tower's load. They stay in the file all the same: their
      caller is the load sequence, which is unscoped and would take them
      back into the root by import.
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
  global as the pin boundary already makes it. Answered (2026-09-27): the
  boot set stays global, and the names it shares are listed in
  `tools/contract/shared-privates.x`.
- Answered: a scoped file needs neither. `import` loads it with the
  ordinary `include`, and its header reads the rest of the file with the
  reader, one form at a time, into the module's environment. The reader's
  `read` answers the EOF sentinel at end of input (x-engine-c v0.2.13), so
  a `()` in a module is a form rather than the end of the file.

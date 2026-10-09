# State Images

A state image is a live base written to a file and rebuilt by another
process running the same engine release. The format is
[state-image-format.md](state-image-format.md). The writer is
`tools/dev/image-write.x` over `lib/x/tool/image/`, the loader is
`tools/dev/image-read.x` on the `lib/img.x` prelude, and
`tools/dev/image-build.sh` keys and writes one
([tools/dev/README.md](../tools/dev/README.md)). This document says why they
are shaped as they are. Where it and the format document disagree, the
format document is the one that is right.

## The state is a graph the interpreter can read

The base holds the entire state of an interpreter, and every object is a
contiguous array of words: a metadata prefix, a header, then data units.
`engine/tools/contract/obj-layout.x` commits that layout, and the
collector's heap-chain link is a word like any other, so from any object x
code reaches the next one the base allocated. Saving the state is therefore
a traversal, not an engine feature: enumerate the chain and write each
object's units.

What the layout alone could not say is how many units an object has and
what each one is. A type declared a count (`type set-units!`) and the
collector traced every declared unit as a reference. That makes a bare
count unusable for anything that is not a reference: the collector marks a
pointer before establishing that it is a heap object, so a string
declaring its one unit would have a mark bit written into memory beside
its bytes. The declaration had to carry a label per unit, and the collector
had to read the labels.

## An image writer is a mark phase that emits

Writing an image asks what the collector asks, in the same order, at the
same moment:

| the collector | the image writer |
|---|---|
| what is reachable from the base? | what goes in the image? |
| which units of this object are references? | which units are indices? |
| what must a type be told to trace? | what must a type be told to write? |
| what needs a free hook because C owns it? | what needs a name because C owns it? |
| when is it safe: the seat is quiet | when is it safe: the seat is quiet |

If the collector can trace an object, the image can write it; where the
collector needs a declaration or a hook, the image needs the counterpart.
There is no object that is collectable and unwritable. Three things follow.

**Reachability is the collector's answer.** The writer does not compute what
is reachable. It asks `(heap tree-mark! base FLAG)` with a flag the
collector does not otherwise use, then walks the allocation chain and acts
only on flagged objects: the chain is the enumerator and the flag is the
filter. A walk written in x cannot do this, because the base's own spine is
not ordinary structure. A structural pair there may hold a raw C function
pointer (the collector's own hooks), and following it as a reference is a
wild read. The spine's nodes are also already SHARED, which rules that flag
out as the mark, and the collector's own mark bit cannot be left set across
a collect. The base tree is walked only through `base-layout.x` and
`base-paths.x`, as `lib/x/boot/reflect.x` walks it, never as structure.

**The seam is the seam.** An image is taken where
[crafting-a-lang.md](crafting-a-lang.md) §6 puts the per-turn sweep: the
previous eval has finished and no reader is mid-flight. The control cells
(`save-stack`, `error-handler`, the `tco-*` registers) are nil there and
have nothing to serialise; the format writes them as nil and the loader
installs them last. Anywhere else the writer refuses. An image of a
half-finished eval is a false image, not a smaller one.

**Units carry labels, not a count alone.** A unit is `ref`, `word`, `bytes`
or `foreign` (format §3.3). The collector traces a `ref` and ignores the
other three; the image writes an index, copies the word, puts the bytes in
the blob, or names the foreign value. The declaration lives in the type's
units slot, widened in place from an integer to a structural `(count .
mask)` pair, so a zero mask means all references and the integer form keeps
meaning what it meant. `Type set-unit-labels!` compiles the readable
spelling, and it is a primitive because the pair must be structural: the
collector tells the two forms apart with one pointer comparison, and a pair
x builds is a LIST. Policy in x, unchecked mechanism in C.

`word` means a raw machine value, not "the small one". A vector's slot 0
holds a heap INTEGER object, so a vector is `(ref ref)`; `word` is for a
unit the collector must not follow, an atom's integer or character code.
Ask what the unit holds, not how big it looks.

A per-type declaration does not describe every type. A BUFFER's outer
instance and its inner bookkeeping object are one type with two layouts.
So the writer never reads a type's units from outside: every type has a
`save` handler that writes its own labelled words and a `load` handler that
fixes a rebuilt object up (format §4.3), and the default `save` walks the
declared labels. The declaration is what most types need; the handler is
the door for the ones it does not describe.

## Identity: a name is a path, not a value

Two primitive objects can share one C function. `x_callable_bind` allocates
one for the bare global `+` and `x_prims_add` another for the catalogue's
`(int +)`, and nothing merges them:

```x
(same? (prim-ref (lit int) (lit +)) %int+)   ; => #f
```

Naming a foreign value by a coordinate that yields an equal value would
merge objects the running base kept apart, and `same?` would answer
differently after a round trip, a defect that surfaces long after the load.
The rule:

> A foreign value is named by the path it was found at, in a fresh base,
> not by a path that yields an equal value.

Bare `+` restores from the fresh base's bare `+`, and catalogue `(int +)`
from the fresh base's catalogue. The raw bitwise operators that
`lib/x/core/arithmetic.x` wraps and rebinds survive only inside the
wrapper's closure, and they restore from the fresh base's bare bindings,
where they still are before the library rebinds them.

The externals table (format §3.4) is this rule as a closed vocabulary: a
catalogue coordinate, a bare name, a C symbol, a type's call pointer, the
process handle, an engine static by role, a type's static by row, a spine
node by row. A `foreign` unit the writer cannot name this way makes the
write refuse. Not warn, not write nil and carry on: the failure this rules
out is an image that loads and misbehaves a thousand evals later.

## What the loader may not assume

An image is loaded by a process that did not write it, so no address in it
survives. Every foreign unit is reacquired by name, and the name must mean
the same thing on the far side. The header carries the engine release, the
word size and the byte order, and the loader refuses any mismatch before it
allocates: the image is a heap laid out by one build of the engine, and its
externals are named against that build's catalogue and statics. This is the
[engine-contract.md](engine-contract.md) parameter rule at work. None of
these is a requirement on an engine; each is checked where it is consumed.

Three kinds of value cannot be reacquired by name, and the library declares
each of them:

- **A reference into the base's spine** (the descriptor atoms, the io
  pairs, the registry cell) is not copied. The host has its own spine, live,
  at other addresses, and a copy would be a second, dead one. The reference
  is recorded as the row of `base-paths.x` that reaches the node and is
  resolved against the host's base. A spine node with no row is unnameable.
- **A value that is an address, whatever type holds it**, is a transient.
  The module lists the global with `(image transient! NAME)`, the writer
  sets it to nil in the child before the walk, and a recache hook the module
  registers with `(image recache-hook! THUNK)` re-derives it after the
  install. An INTEGER's unit is `word` and is written verbatim, so a
  trampoline address held as an integer would come back as the writing
  process's address, and a compile on the far side would call it. A `dlsym`
  external names only the symbol, and glibc keeps a library the process
  `dlopen`ed itself out of the global scope, so a pointer resolved through
  such a handle is a transient too, with its handle. `lib/x/num/float.x` is
  the pattern: each binding registers itself as it is made, one thunk clears
  them all, one hook remakes them all.
- **A value the library can remake**, compiled code, is a thunk among the
  transients: see "Compiled code" below.

The loader's order follows from this (format §5): verify before allocating
anything; resolve the externals before any object refers to them; allocate
every object and then patch, because a reference can point at an object the
walk has not reached, so indices cannot be assigned and resolved in one
pass; install the roots as direct primitive calls, the control cells last
and nil, so that nothing pushes onto the save-stack of the base being
replaced; then run the recache hooks inside the image.

## The reader: a loop in C, the rest in x

Boot cost is interpretation: the evaluations that construct the library's
objects, with no hot spot to cut. An image replaces them with one
allocate-and-patch per object. That loop runs per object over the whole
heap, and an interpreted loop over a heap costs about what the boot cost,
so the loop is one primitive, `(image rebuild!)`. Everything else the loader
does is per entry, over a header, an externals table and a roots table, and
is x: open, verify, resolve, install, and say in a sentence what refused.
The C refuses with a code. That is the ISA contract's division: the C layer
is a CPU, and checks, dispatch and policy live in x.

The host of that x is not a dialect. The suite is the consumer that matters,
and its default library is the cost being replaced, so a loader hosted on
helium would pay what it saves. The host is the engine plus `lib/img.x`, a
prelude written against bare primitives. It defines the `obj ref` and `obj
set!` it needs from the same addressing formula as `boot/data.x`, takes type
names and units cells from the type-rooted rows of `base-paths.x`, and
takes its unit labels from `lib/x/type/unit-label-rows.x`, the rows
helium's boot also reads. Its `do` is two operatives handing the body to
each other through `tail-eval`, because a helper procedure does not keep a
tail call in constant stack. `lib/x/tool/asm-cache.x` is the precedent,
written at the same level for the same reason.

Compiled code needs no C either. The cache pours stored bytes into a fresh
page and re-encodes every baked address for the loading process, through
`dlsym` and `ptr call`; the one ISA coordinate in the lane is `(obj
make-callable alloc)`, already pinned.

The writer stays in x throughout. It runs once, offline, inside the dialect
it is imaging.

## The writer's rules

- **It images a child base.** The writer loads the library into `(base
  make)` and walks that child's chain, so its own bindings are outside the
  image, and the child binds its own `include`, `syscall` and `args`
  (format §4.2). A writer running inside the base it images leaves a trace
  on the thing being recorded: every `def` it evaluates repoints an
  environment pair at a value the index pass never saw.
- **It mutates nothing inside the heap it images.** Allocation after the
  index pass is harmless, since a new object is newer than the cursor and
  is never walked; `set!` on an imaged pair is not. The writer's state is
  threaded through call frames as parameters. The one exception is the
  index stamp, written into a metadata slot, which is not part of any
  object's imaged content.
- **The cursor is an object, not an address.** A raw address dangles when a
  collect unlinks the object under it. Held as an x value the cursor is
  rooted, and the sweep relinks its heap word past what it freed, so the
  walk may collect periodically and stays bounded. While a frame holds a
  cursor into the child's chain, the writer's own base must not collect
  (format §4.1).
- **The child sweeps as it loads.** The engine never collects on its own,
  so a load holds every file's garbage until something asks. The loader's
  `include` collects after each file while `%image-writing` is true,
  which it is in the writer's child alone: nothing runs there but the load,
  the includers' state is rooted while a file loads (x-engine-c 0.2.6),
  and so is the form under evaluation. Without it x-coreutils, 1.2MB of
  source read on helium, made some 370M objects before the writer's first
  collect, a footprint past 12GB for a heap of 371K objects; with it the
  write peaks at 1.25GB. Outside the writer the loader does not collect,
  since an import can come from code holding anything.
- **Bare primitives in the loop.** The library's guarded operators and
  reflective accessors are x, and each costs allocations per call; over
  every object of a heap that ends the process. This is
  [contributing.md](contributing.md)'s prim-caching rule, with no exemption.
- **Naming happens after the walk.** The loop, `(image write!)`, names
  nothing: a word it cannot place goes to a callable the writer supplies,
  once per distinct word. Naming allocates, and the walk must not allocate
  into the chain it is walking.
- **Every refusal is stated, and the writer never dies.** A raise inside the
  child is reported and stops the write: a raise a parent guard swallows
  leaves the child's root chain holding nodes of C frames that no longer
  exist, and the child's next collect walks freed stack. A reference word
  the writer cannot place is reported by the holder's type and the word,
  and is never read as an object. A child with more live objects than the
  table holds is refused with the count. A crash is called a crash, never a
  library's refusal.

## What a library must do to image

A module that keeps something no image can carry declares it, and the
writer refuses what is not declared.

- **A cached address** is a transient with a recache hook, as above.
- **A compiled function** is registered with `lib/x/tool/compiled.x`, below.
- **A second base made at load** cannot be imaged: the writer walks one
  chain, and a reference into another base's heap cannot be placed. Turn
  what registers onto that base into a table that can be replayed, give it
  one builder, nil the base in a transient, and call the builder from a
  recache hook.
- **An entry that reads stdin at load** reads the writer's own script,
  because the engine's program and the child's stdin are one descriptor.
  The writer binds `%image-writing` in the child before the include, and
  an entry that loads and stops while it is bound images like any other.
  The read is guarded, because the name is bound in the writer's child
  alone, and the child has no catalogue yet to answer nil for an unbound
  name:

  ```x
  (if (guard (_ #f) %image-writing)
    ()
    (if %batch? (batch) (session)))
  ```

  The writer takes the binding back before it walks, so no image carries a
  true one.
- **Anything an import starts**, a forked viewer for instance, is decided
  once, in the writer's child. It moves out of the imports and into the
  entry's dispatch.

## Compiled code: put down before the write, picked up after the load

A compiled analyser runs from a page the writing process mapped, and no
name reacquires a page in another process. What an image can carry is the
code and its relocation records: `lib/x/tool/asm-cache.x` holds each entry
in the heap, the code as an object of `word` units and the records as a
list, so a compile after a load is a copy into a fresh page and a patch,
with no compiler run.

Every compile in `boot/tower-compiled.x` is the same pattern, source over
free variables displacing an interpreted twin. Each makes an entry in
`lib/x/tool/compiled.x` recording where the result is installed (a name's
binding, or one cell of a type's handler list), the twin, and the function
that compiles it. `(Compiled interpret-all!)` puts every twin back and lets
the compiled objects go; the writer runs it inside the child before the
walk, as a thunk among the transients. Each entry's recache hook compiles
it anew after the install, in the order the entries were made, after the
tower's own hook has asked the lane again, since the loading engine is not
the writing one.

The compiled version is remade, not carried. The cache carries the bytes.

## Where images are used

- **The spec suite.** `make test-x` writes one image per library the specs
  declare (`make images` alone does that) and boots each job from it, one
  spec file per job; `IMG=0` boots every library from source.
  `tools/dev/image-build.sh` keys an image on the library, every `.x` under
  `lib/` and `tests/x/lib/`, the engine's contract directory, the writer and
  the engine binary, and rewrites it when the key beside it differs. A lib
  edit rewrites every image on purpose: a suite that silently tests a stale
  library is worse than a slow one. The header's release catches a changed
  engine; the key catches changed source.
- **A lang bundle's suite** boots from an image of its harness, keyed on the
  bundle's module tree as well ([lang-contract.md](lang-contract.md)). The
  harness is on `x-core.x`, the dialect the bundle ships, not on
  `x-base.x`: a harness on a fuller library than the lang has hides what the
  lang lacks.
- **`x -l NAME`** boots from an image of the prefix the wrapper would have
  piped ahead of the program. For a bundle it is in the bundle's `.images/`
  and is its installer's to write (`x --image -l NAME` at the end of `make
  install`); the wrapper never writes into a bundle behind the installer's
  back. For a dialect or an app it is in `~/.cache/x/images/<tree>/`,
  written on a miss with one line on stderr. A pinned boot amalgam
  (`--boot`, or a manifest's `(boot ...)`) is never imaged: it is another
  release's boot, and the loader is this tree's. `--no-image` boots from
  source.

An image is a cache, not an artifact. It carries no release of its own, it
is rewritten whenever its key changes, and it may be deleted at any time.

## What it buys

- Boot elision: a dialect is a fixed traversal of the same source every
  time, and an image is that traversal's result.
- A sandbox with a library already in it, without replaying the library.
- A bug report that is the heap: the state at the moment of a defect,
  loaded elsewhere and inspected with the tools in the tree.
- A REPL that outlives its process.
- A lang bundle that ships a booted image rather than source to
  re-evaluate.

One path serves all of them. There is no privileged startup loader that
replaces the process base: the host boots, loads, installs the roots, and
evaluates in the image.

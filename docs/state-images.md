# State Images

The base holds the entire state of an interpreter, and every object is a
contiguous array of words. Those two facts together say the state is a graph
the interpreter can already read — so saving it is a **traversal**, not a
feature that has to be built into the engine first.

This document is the design for that: a binary image of a live base, written
and read from x. **The unit-shape declaration it rests on is implemented**
(x-engine-c branch `feat/unit-shapes`, plus `Type set-shape!` and the atom-type
declarations here); the image format, the writer and the reader are still
design. The measurements are real and every one of them is reproducible with
the script in "The image, measured"; the rulings are proposals, marked as such
where they change a contract.

## It is already readable

`ext/x-expr/include/x-obj.h` states the representation outright: every value
is a contiguous array of `x_obj_t` units, a small metadata header followed by
one or more data units. `engine/tools/contract/obj-layout.x` is the committed
form of that layout, and it says why it exists — the interpreter is fully
reflective, `%obj->ptr` plus `%ptr-ref-word` reach every word of every object,
and reflective x code must read its offsets from the contract rather than from
folklore.

Two consequences that had not been written down:

**The heap chain is walkable from x.** Slot `%obj-slot-heap` is the
singly-linked heap-chain link the collector uses, and it is a word like any
other. From any object, `(%rw o %heap-off)` reaches the next, so **enumeration
of the whole live heap is available today**, with no `heap each` primitive and
no engine change. The GC's chain is the image writer's iterator.

**One thing is missing, and it is not small.** Type word, flags word and the data
units are all reachable the same way — but nothing can say *how many* data
units an object has, and without that a reader cannot know where an object
ends.

It is not the accessor that is missing. `set-units!` turns out to be **x, not
C** — `lib/x/type/struct.x` writes the type's units cell reflectively through
the `type-units` row of the layout contract, and files it into the catalog with
`prim-reg!`. So the count is readable from x by the same path, and a
twenty-line `%obj-units` written against `%reflect-type-word`,
`%reflect-satom-tw` and `%type-units-cell` answers correctly for every type
that declares one:

```
pair (1 . 2) -> 2      vector of 5 -> 6      vector of 0 -> 1
structural pair -> 2   closure -> declared   operative -> declared
integer -> REFUSED     string -> REFUSED     symbol, char, prim -> REFUSED
```

**What is missing is the declaration itself, for the atom types.** INTEGER,
STRING, SYMBOL, CHARACTER, PRIMITIVE and POINTER declare no units anywhere.
Their one-unit shape is implicit in the C constructors and recorded in no
contract — and the engine cannot answer either: `x_type_prim_units` reaches
the same NULL and returns NULL for exactly these types.

**And the count cannot simply be declared.** This is the finding that decides
the design. The collector's fallback traverses every declared unit with
`x_heap_tree_mark`, whose first act on any pointer handed to it is

```c
x_obj_flags(p_obj) |= flags;    /* ext/x-expr/src/x-heap.c */
```

— it writes the mark bit *before* establishing that the pointer is a heap
object. Declare `units 1` on STRING and the next collect ORs a bit into memory
three words ahead of the string's bytes. The unit declaration is unusable for
any unit that is not a reference.

So the declaration must distinguish a reference from a word, from bytes, from
a foreign address, and the collector must consult the distinction. That was an
engine change — not "expose an accessor" but "teach the collector to read the
kind of each unit" — and it needed no new field: the shape widens `p_units` in
place. **It is done**; the section below is what was built, and with the six
atom types declared, `%obj-units` answers for every type in a booted helium.

## The image, measured

Save this as `census.x` and run `sh x.sh -q -f census.x`:

```x
(include "engine/tools/contract/obj-layout.x")

(def %o->p (prim-ref (lit obj) (lit ->ptr)))
(def %p->i (prim-ref (lit ptr) (lit ->int)))
(def %i->p (prim-ref (lit int) (lit ->ptr)))
(def %p->o (prim-ref (lit ptr) (lit ->obj)))
(def %rw   (prim-ref (lit ptr) (lit ref-word)))
(def %collect (prim-ref (lit heap) (lit collect)))

(def %heap-off (* %obj-slot-heap %word-size))
(def %type-off (* %obj-slot-type %word-size))

; (type-word count . sample-address), in a one-slot box so the walk names
; nothing it has to allocate.
(def %box (Vector make 1 ()))
(def %tally
  (fn (self tw a lst)
    (if (null? lst)
        (Vector set! 0 (pair (pair tw (pair 1 a)) (Vector ref 0 %box)) %box)
        (if (= tw (first (first lst)))
            (Obj set! (rest (first lst)) 0 (+ 1 (first (rest (first lst)))))
            (self tw a (rest lst))))))

(def %census
  (fn (self a n)
    (if (= a 0)
        n
        (do (%tally (%rw (%i->p a) %type-off) a (Vector ref 0 %box))
            (self (%rw (%i->p a) %heap-off) (+ n 1))))))

(def %report
  (fn (self lst)
    (if (null? lst)
        ()
        (do (display "  ") (write (first (rest (first lst)))) (display "\t")
            (let ((nm (guard (e ())
                        (Type name (%p->o (%i->p (rest (rest (first lst)))))))))
              (display (if (null? nm) "<static>" nm)))
            (newline)
            (self (rest lst))))))

(%collect)
(display "live objects: ") (write (%census (%p->i (%o->p (pair 1 2))) 0))
(newline)
(%report (Vector ref 0 %box))
```

A booted **helium**, collected, is about **89,700 objects**:

| count | type | in an image |
|--:|---|---|
| 53,785 | LIST | structure |
| 27,394 | `<static>` (the built-in PAIR type object) | structure |
| 3,220 | STRING | bytes |
| 2,884 | SYMBOL | structure |
| 1,040 | INTEGER | structure |
| 995 | PROCEDURE | structure |
| **129** | **PRIMITIVE** | **the path it was found at** |
| 92 | `<static>` (the built-in ATOM type object) | structure |
| 74 | CHARACTER | structure |
| 39 | OPERATIVE | structure |
| 26 | CLASS | structure |
| **18** | **POINTER** | **declared foreign** |
| 2 | BUFFER | bytes |
| 1 | VECTOR | the probe's own box |

Counts drift by a few dozen between runs because the probe is part of what it
measures; the `include` of the layout contract alone accounts for about 3,800
of them (the same walk with the offsets inlined reports 85,862). Read the
table for shape, not for a checksum.

Ninety percent of a whole interpreter is pairs. **The part that holds a
machine address at all is 147 objects, under two tenths of one percent** — and
all 147 turn out to be nameable, for reasons the next three sections measure.

### The pointers are nameable, individually

The POINTER objects are the only genuinely opaque leaves, and in a booted
helium there are seventeen of them (the census script's own `include`
allocates the eighteenth).
They are not a mystery: `lib/x/sys/posix.x` resolves sixteen libc entry points
at load time (`(def %c-fork (%resolve "fork"))` and its fifteen siblings) over
one `dlopen` handle, `%libc`, whose value is the macOS `RTLD_DEFAULT`
sentinel, `-2`.

```bash
grep -c '^(def %c-.* (%resolve "' lib/x/sys/posix.x    # => 16
```

So the pointer half of the foreign surface is seventeen values whose
externalised form is the expression that produced them.

### Naming a primitive: measured, and it is not one table

The obvious plan for the 129 primitives is the catalog: it is a live
`(ns . methods)` table in the base's `prims` field, it is what `prim-ref`
already reads, and a coordinate is a perfectly good name. It is also not
enough. A probe that collects primitive addresses from each naming table in
turn and diffs them against the heap walk above:

| naming source | primitives it accounts for | left over |
|---|--:|--:|
| the catalog (135 coordinates, 22 namespaces) | 85 | 44 |
| plus the bare boot bindings (`x_callable_bind`'s keep-list) | 117 | 12 |
| plus the global BST (`env-global-tree`) | 123 | 6 |
| plus six raw operators held only in closures — below | 129 | **0** |

Every primitive in a booted helium has a path. Three of the four sources are
tables you can walk; the fourth is not, and it is the interesting one.

**Six primitives are deliberately unreachable by name.**
[`lib/x/core/arithmetic.x`](../lib/x/core/arithmetic.x) wraps the bitwise
operators in arity and type guards and `set!`s the global to the wrapper, so
the raw primitive survives only inside the wrapper's closure — the file says
so on purpose: the raw prim rides in the closure so that no `%int&` /
`%int^` family lands in the global namespace. The probe finds them exactly
there, in `%arith-guard`'s own parameter frame, beside the operator name:

```
slot holder, name = "&"   |   "|"   "^"   "<<"   ">>"   "~"
```

and the split is visible from the outside:

```x
(Type name &)                          ; => "PROCEDURE"  — the guard
(Type name =)                          ; => "PRIMITIVE"  — unwrapped
(Type name (prim-ref (lit int) (lit &)))  ; => "PRIMITIVE"  — the raw one
```

This is not a defect and needs no fix. A closure-captured primitive is written
into the image the same way as anything else — the closure's environment frame
is structure, and the primitive in it is an object. What it settles is *which*
name the image writes down.

### Identity: a coordinate is not a name

The measurement that decides this:

```x
(same? (prim-ref (lit int) (lit +)) %int+)   ; => #f
```

Two distinct primitive objects, one C function. `x_callable_bind` allocates
one object for the bare global and `x_prims_add` allocates another for the
catalog, and nothing merges them. So **naming a primitive by "a coordinate
that yields an equivalent value" silently merges objects the running base kept
apart**, and `same?` starts answering differently after a round trip — a
defect that survives the load and shows up much later, which is the worst
shape a bug in this design can have.

The rule that survives is narrower and is the one to build against:

> **A foreign leaf is named by the path it was found at, in a fresh base —
> not by a path that yields an equal value.**

Bare `+` restores from the fresh base's bare `+`; catalog `(int +)` restores
from the fresh base's catalog; the six raw bitwise operators restore from the
fresh base's bare bindings, which is where they still are before a library
rebinds them. A fresh base has all three, and it has them distinct, so
identity is preserved *because* the naming is by path rather than by value.

## The thesis: an image writer is a mark phase that emits

This is the part worth keeping, because it decides the whole design.

Writing an image asks exactly the questions the collector asks, in the same
order, at the same moment:

| the collector | the image writer |
|---|---|
| what is reachable from the base? | what goes in the image? |
| which units of this object are references? | which units are indices? |
| what must a type be *told* to trace (`type set-units!`)? | what must a type be *told* to write? |
| what needs a free-hook because C owns it? | what needs externalising because C owns it? |
| when is it safe — the seat is quiet | when is it safe — the seat is quiet |

Every row is the same question. That gives the design its shape and its
correctness argument in one: **if the collector can trace an object, the image
can write it; if the collector needs a declaration, the image needs the same
declaration; if the collector needs a hook, the image needs the counterpart
hook.** There is no third category, and no object that is collectable but
unwritable.

Two things follow immediately.

**The seam is the seam.** An image must be taken exactly where
[crafting-a-lang.md](crafting-a-lang.md) §6 puts the per-turn sweep: the
previous eval has finished and no reader is mid-flight, which is what makes
the control state genuinely empty. `error-handler` is a `setjmp` chain into
the C stack, `save-stack` and the `tco-*` registers are live only mid-eval.
At the quiet seam they are nil and there is nothing to serialise. Anywhere
else, the writer must refuse — an image of a half-finished eval is not a
smaller image, it is a false one.

**A type's units must become a shape, not a count.** Today
[`lib/x/type/obj.x`](../lib/x/type/obj.x) carries the GC contract as a note:
raw slots are traced only if the type declares units, `-1` for the slot-0
counted Vector convention or a fixed number, and without it a collect frees
the payloads underneath the object. That declaration says *how many* units to
trace. An image needs to know *what each unit is*, and so, it turns out, does
the collector — tracing every declared unit as a reference is strictly less
correct than tracing the ones that are references.

A unit is declared as one of four kinds.

| kind | code | is | collector | image |
|---|--:|---|---|---|
| `ref` | 0 | a heap object pointer | traces it | writes an index |
| `word` | 1 | an immediate | ignores it | copies the word |
| `bytes` | 2 | a pointer to bytes whose length the type knows | ignores it | writes them inline |
| `foreign` | 3 | an address C owns | ignores it | externalises it |

**The declaration goes in `p_units`. There is no new field.** An x-expr object
does not track its own length: an atom is one unit and a pair is two by
construction, and the only per-instance size that exists is the slot-0 count.
So the footprint an image needs — metadata units, header, data units — is
determined by the base-wide meta width, the header length from
[obj-layout.x](../engine/tools/contract/obj-layout.x), and `p_units`. Nothing
else can carry it, and a second field beside it could only drift from it.

`p_units` is an object slot, so it can widen in place — the same contract
pattern the base and the types already use, where a reader takes the shape it
understands:

| `p_units` holds | means |
|---|---|
| an INT atom, N ≥ 0 | today: N units, every one a reference |
| an INT atom, N < 0 | today: slot 0 holds the payload count, total N = slot0 + 1, every one a reference |
| a pair `(count . mask)` | *count* keeps both meanings above; *mask* is an INT bitfield, two bits per unit, giving each unit's kind |

Units past the end of the mask take the kind of the last unit it describes, so
a dynamic-size type says what its payload units are without a marker. And
because `ref` is code 0, a zero mask means "all references", so the pair form
degrades exactly onto the integer form.

> **`word` means a raw machine value, not "the small one".** The trap, found
> by writing the spec: a vector's slot 0 holds a heap INTEGER *object*, not an
> immediate, so `(word ref)` over a count of `-1` is **wrong** for it — the
> collector skips slot 0, the length is freed under the instance, and the next
> read finds a hole. A vector is `(ref ref)`, which is mask 0, which is the
> bare count it already had. `word` is for a unit that holds a machine value
> the collector must not follow: the engine's own atom types, whose single data
> unit is an int or a character code rather than a pointer. Ask what the unit
> *holds*, not how big it looks.

The cost in C is one `x_obj_type_isspair(p_units)` branch per object at each of
the three sites that read the slot — the collector's traversal
(`x_type_heap_mark`), the unit accessor (`x_type_prim_units`), and the spine
guard (`x_eval_spine_guard`) — and a shift and mask per unit. No allocation, no
symbol comparison, nothing in the inner loop that was not there before.

The readable spelling stays in x. `Type set-shape!` takes `'(word ref)`,
`'(bytes)`, `'(foreign)` and compiles it to `(count . mask)`; the engine only
ever sees two integers. Policy in x, unchecked mechanism in C — and
`set-units!` keeps working untouched, because the integer form is still the
integer form.

> **The shape pair must be built in C, and that is why `set-shape!` is a
> primitive.** x's `pair` makes LIST-typed pairs; the readers discriminate the
> two forms with `x_obj_type_isspair()`, which matches *structural* pairs only
> — one pointer comparison on a path the collector walks per object. An
> x-built shape is therefore read as a bare count, and the count comes out as
> the pair's first data word. `isa.x` already records that x makes list-pairs
> only; this is that constraint biting, and it cost one segfault to find.

> **The dynamic-size marker is a negative count, not a flag.** Worth stating
> because the object header does have spare attribute bits and one might
> reasonably expect the job to be done there: `X_OBJ_FLAG_3` is taken —
> `include/x-eval.h` aliases it `X_OBJ_FLAG_FRAME` for environment frames,
> which is 2,346 of the objects in the census above.

`bytes` earns its place by arithmetic. Classified as `foreign`, strings would
put 3,220 objects into the pile that needs per-type code; classified honestly
as data the type can measure, they need none, and the declared-foreign set
falls to the seventeen pointers.

## Externalise and internalise

For a `foreign` unit — and only for those — the type declares how the value
is named and how it is reacquired. The type contract already carries
`write`/`read` for the *textual* representation; this is the same pair one
level down, for the representation that has to preserve identity.

Three declaration forms, not one, because most foreign leaves need a statement
rather than code:

```x
(foreign resolved)                       ; the writer finds the path itself —
                                         ; catalog coordinate or bare global
(foreign drop)                           ; restore as nil — control state,
                                         ; caches, anything rebuilt on demand
(foreign externalise F internalise G)    ; the general case
```

`resolved` is the primitives' declaration and covers all 129 measured above —
the writer records which table it found the object in, not merely a table that
has an equal one. `drop` is the control state at the quiet seam. The closures are for
everything a fresh base does not already hold.

`F` answers a value the image can hold — for `%c-fork`, the string `"fork"`
against the handle's own index. `G` takes it back and returns a live value —
`(%dlsym %libc "fork")`. The seventeen pointers of a booted helium are one
declaration on POINTER plus the two closures posix.x would supply.

**A type with a `foreign` unit and no declaration makes the write refuse.**
Not warn, not write a nil and carry on. The failure mode this rules out is an
image that loads and then misbehaves a thousand evals later, which is the
worst bug this design could ship; refusing at write time costs a message.

**Externalise never runs during the walk.** This is a constraint, not a
preference, and it comes out of building the probes above: the walk holds a
raw address as its cursor, so anything that allocates into the chain being
walked, or collects underneath it, dangles the cursor. So the writer runs in
two phases — the walk collects addresses and indices and touches nothing else;
externalise runs afterwards over the foreign table alone, which is at most a
few hundred entries. The same discipline is why the walk must not collect,
and it should arm that: no collect between the opening sweep and the last
row written.

## The format

Word-oriented, in the writing machine's own word size and byte order, because
an image is not a portable artifact — the header exists to say so and to
refuse.

```
header        magic and format version
              engine release, os, arch, endian, word size
              extra-metadata width (Obj meta-count at write time)
              digests of base-layout.x, obj-layout.x, obj shape table
              counts: types, foreign entries, objects; the root index
type table    one row per distinct type word: name, and the unit shape
foreign table one row per foreign leaf: its externalised form
object table  one row per object: type index, flags, meta units, units
```

Index 0 is nil, so objects number from 1 and a nil unit needs no tag.

**No per-unit tags.** The type table's shape says what each unit of each
instance is, which is precisely why the shape declaration is the linchpin of
the design rather than a detail of it. An image with per-unit tags would cost
a word per unit — on this measurement, several megabytes to say what fourteen
type rows already say.

**The two static type objects** — the built-in ATOM and PAIR types, which the
engine matches by pointer identity, not by name — are two fixed rows in the
type table with reserved ids. They are the reason the table holds ids rather
than addresses.

**The metadata width is base-wide and load-bearing.** This build runs
`(Obj meta-count)` = 2, so every object carries two prepended units at
negative offsets and the meta flag set. obj.x is explicit that changing the
width while objects are live is undefined, so the width goes in the header and
the reader sets it before it allocates the first object — or refuses.

## Restore

Two passes, into a **child base**, not the running one.

1. Set the metadata width from the header. Allocate every object with its
   type and unit count, filling nothing. Keep the index-to-address table.
2. Patch every unit: `ref` from the table, `word` verbatim, `bytes`
   reallocated and copied, `foreign` through `internalise`. Set the shared
   flag where the image records it.

Then wrap the root with `Base wrap` and hand it back. `(Image read path)`
answers a Base instance.

Restoring into a child is what makes this a library feature instead of an
engine feature. The machinery exists —
[sandboxing-tutorial.md](sandboxing-tutorial.md) already builds isolated
interpreters, hands them capabilities, and evaluates in them — and a child is
independent by construction, so a botched restore damages a value, not the
process. Replacing the running base is a separate question and does not need
answering first.

It also answers a complaint that tutorial already documents: a fresh child is
the bare C ISA, and giving it a library means replaying the library into it.
An image is the other way to get one.

Proposed surface, data-last per [contributing.md](contributing.md):

```x
(Image write path base)   ; refuses rather than write an unfaithful image
(Image read path)         ; => a Base instance
(Image inspect path)      ; => the header, without loading anything
```

## What the header refuses

An image is loadable by the engine release, platform and layout that wrote it,
and by nothing else. The vocabulary for saying that already exists — the
parameters in `x-engine.xon` and the pin manifests — so the header carries
`%param-release`, `%param-os`, `%param-arch`, `%param-endian`,
`%param-word-size`, the metadata width, and a digest of each layout contract
it depends on. Any mismatch refuses.

This is the [engine-contract.md](engine-contract.md) parameter rule doing its
job: none of these is a requirement on an engine, and all of them are checked
where they are consumed. An image is exactly such a consumer.

The writer refuses too, and its refusals are the more important half: control
state that is not empty, a type with an undeclared `foreign` unit, a type with
no shape at all.

## What it buys

- **Boot elision.** A dialect is a fixed traversal of the same source every
  time. An image is that result.
- **Sandboxes with a library in them**, without replaying the library.
- **A bug report that is the heap.** The state at the moment of a defect,
  written out, loaded elsewhere, inspected with the tools in the tree.
- **Session persistence** — a REPL that survives the process.
- **Lang bundles that ship a booted image** rather than source to re-evaluate,
  which is a different answer to the cost [lang-scale.md](lang-scale.md)
  measures.

## Not decided

- **The writer half needs a door.** Reading needs the shape declaration above
  and nothing else; writing objects back means setting type words and flags, which today is raw word
  surgery of the kind `lib/x/boot/reflect.x` already does in `%reflect-retag!`.
  Whether that stays reflective or earns a primitive is open.
- **The shape landed on a branch, not in a release.** `isa.x` carries the
  `(type set-shape! types)` row and the gates pass, but an engine change
  reaches this repo only as a pinned artifact: it still wants a release and a
  re-pin before anything may depend on it.
- **Is an image a pinned artifact or a local cache?** If a lang may ship one,
  it acquires a release, a digest, and a place in the pin vocabulary. If it is
  only a cache, it needs none of that and may be deleted at any time.
- **Foreign values that participate in cycles.** None do today. The design
  above assumes it and does not check it.
- **Interning on restore.** Identity is by path, but the reader still needs one
  table so that two saved references to the same object come back as one
  object, and two that differed come back distinct. Cheap; easy to get wrong.
- **The probes in this document are not in the tree.** The census belongs in
  `tools/dev/` alongside the other measuring tools, and the naming coverage
  check belongs wherever it can fail a build when a new primitive arrives with
  no path to it.

## What bit while probing

Two hazards found writing the scripts in this document, both of which the
writer has to respect:

- **A collect during a walk dangles the cursor.** The cursor is a raw address
  in a chain the collector is free to unlink. Do not collect between the
  opening sweep and the last row.
- **`obj ->ptr` on nil segfaults.** A reflective walker meets nil constantly —
  every list terminator, every empty field, every unbound cell — and the raw
  door has no nil check. Guard before every conversion, not after the first
  crash.
- **A `def` inside a hot tail loop is not free.** The census loop, written
  with three inner `def`s, grew the environment enough that the process was
  killed by the OS at 120,000 iterations. The same loop written without them
  walks the whole heap without noticing. This is worth knowing well beyond
  this document.

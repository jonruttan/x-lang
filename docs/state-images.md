# State Images

The base holds the entire state of an interpreter, and every object is a
contiguous array of words. Those two facts together say the state is a graph
the interpreter can already read — so saving it is a **traversal**, not a
feature that has to be built into the engine first.

This document is the design for that: a binary image of a live base, written
from x and read by the engine at startup. **The unit-shape declaration it rests on is implemented**
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

## The reader is C, and the profile says why

Measured on this tree, booting each dialect and reading the base's own eval
counter:

| | evals | boot | evals/sec | live objects |
|---|--:|--:|--:|--:|
| helium | 6,728,402 | 0.92s | 7.3M | 90,937 |
| xenon | 46,154,541 | 5.65s | 8.2M | 153,924 |
| radon | 46,451,316 | 5.81s | 8.0M | — |

Throughput is flat at ~8M evals/sec, so **boot time is pure interpretation** —
proportional to work done, with no `cc` invocation, no I/O stall and nothing
quadratic hiding in it. Any of those would show as time without evals, and
xenon's rate is if anything *higher* than helium's.

That is 46M evals to produce 154k surviving objects: **about 300 evals per
live object**. An image replaces all of them with one allocate-and-patch each.

### There is no cheaper lever, and that was checked

The obvious hope is that a boot this expensive has one hot spot to fix
instead. It does not. A profiling engine (`-DX_PROFILE -DX_COV`) booting
xenon reports:

| counter | xenon |
|---|--:|
| evals | 48,342,243 |
| assoc calls / steps | 4,272,848 / 72,477,713 (~17 deep) |
| BST hits / misses | 17,144,538 / 1,509 |
| symbol-find steps | 0 |

The alist scanning is the eye-catching number and is not the answer: at a few
nanoseconds a step it is a fraction of a second out of 5.65. The globals BST
is essentially perfect — 1,509 misses in 17 million. And the one structural
win is **already banked**: `lib/x/tool/asm-cache.x` caches the compile-asm
lane, whose own header prices it at 7.2M evals of a 52M boot, and a fresh
xenon boot writes zero new cache entries, so it is fully hit.

What is left is ~48M evals of diffuse interpretation at ~118ns each, with no
hot spot. Which is the case *for* an image rather than against it: a wholesale
skip is the only thing that helps a cost with no peak in it.

> **The per-include timings a profiling build prints are INCLUSIVE.** A parent
> counts everything nested under it, so their sum exceeds the boot several
> times over and ranking by them attributes a whole subtree to its root. Read
> them as a tree or rank only the leaves.

It also rules the reader out of x. A bare heap walk — following the chain and
counting, nothing else — costs 0.81s over helium's heap and 2.28s over
xenon's, which is ~3µs per evaluator operation. A reader needs roughly twenty
operations per object, so ~9s against a 5.65s boot. And a reader living in the
library would need the library booted before it could read the image that was
meant to replace booting the library.

**So the reader is C, at process startup, before any x runs.** The writer
stays in x: it runs once, offline, inside the dialect it is imaging, where 2s
does not matter.

## What the loader may not do

This is the constraint that shapes the format, and it is easy to miss: **the
loader runs before x exists, so it cannot call an x closure.** The
`internalise` half of the type declaration is x code. It cannot run at load
time.

So the load-time foreign vocabulary is **closed, and every entry must be
resolvable by C alone**:

| kind | payload | how C resolves it |
|---|---|---|
| `nil` | — | NULL |
| `catalog` | ns, method | walk the fresh base's prims catalog |
| `bare` | name | look up the fresh base's boot binding |
| `dlsym` | library, symbol | `dlopen` + `dlsym` |
| `fd` | role (in/out/err) | the process's own descriptors |

A `foreign` unit whose value is not one of these **makes the write refuse**.
Types wanting richer reacquisition get it after boot, from x, through
`internalise` — but then their instances are not part of a startup image, and
saying so at write time is the whole point of the refusal.

The measured foreign surface fits this: a booted helium's 147 address-holding
objects are 129 primitives (catalog or bare — both C-resolvable) and 17
pointers that are sixteen `dlsym` results over one `dlopen` handle.

## The format

Word-oriented, in the writing machine's own word size and byte order, because
an image is not a portable artifact — the header exists to say so and refuse.

```
header        magic "XIMG" + format version
              a known byte-order word, word size
              engine release, os, arch
              extra-metadata width (Obj meta-count at write time)
              digests of base-layout.x, obj-layout.x, base-paths.x
              counts: types, foreign, objects, bytes
              root index -- the base object
type table    per type: name, units count, units mask, and which of
              { static ATOM, static PAIR, heap type } it is
foreign table per entry: kind + payload, from the closed table above
extent table  one word per object: its unit count
object table  per object: type index, flags, then its units
byte blob     string bytes, symbol names, and the tables' own strings
```

**Index 0 is nil**, so objects number from 1 and a nil unit needs no tag.

**Every unit is one word, and the type's shape says what it means** — a
reference is an object index, a word is the value itself, bytes is an index
into the byte blob, foreign is an index into the foreign table. This is why
the shape declaration is the linchpin: without it the format needs a tag per
unit, which on this measurement is megabytes spent restating what fourteen
type rows already say.

**The extent table is explicit** rather than derived. A fixed-shape type's
count comes from its shape, but a slot-0-counted type's does not without
reading slot 0 first, and one word per object buys a pass-one that is a
straight loop.

**Metadata units are imaged as `word`.** They carry coverage flags and source
lines; the header records the width, and the loader sets it before it
allocates anything, because obj.x is explicit that changing the width with
objects live is undefined.

## Load

Four passes, none of which call x:

1. **Verify and arm.** Check the header against this engine — release, os,
   arch, byte order, word size, and each layout digest. Set the extra-metadata
   width. Any mismatch refuses here, before a byte is allocated.
2. **Resolve foreign.** Build a fresh base the usual way, so its types and
   primitives exist, then resolve every foreign entry against it. Pin the
   results: they are about to be referenced by objects the fresh base cannot
   see, and nothing else is keeping them alive.
3. **Allocate.** One object per record, from the extent table, in index order.
   Fill nothing. Keep the index-to-pointer table.
4. **Patch.** Walk the unit stream, writing each unit per its kind. Set the
   flags the image records, including `X_OBJ_FLAG_SHARED` where it had it.

Then install the image's root as the process base. The fresh base from pass 2
is discarded; what survives of it is exactly what pass 2 pinned, which is
correct — identity is by path, so the image's reference to bare `+` *is* this
process's bare `+`.

**Identity needs one interning table and no more.** Two saved references to
one object must come back as one object, and two that differed must stay
distinct. The index table gives that for free within the image; the foreign
table gives it across the boundary, which is why naming is by path and not by
value — resolving bare `+` and catalog `(int +)` to the same object would
merge two the running base kept apart.

## Restore into a child, from x

The startup loader replaces the process base. That is what boot elision needs
and it is the harder case. The gentler one is worth keeping: a reader called
from x that builds a **child base** rather than replacing the running one, as
in [sandboxing-tutorial.md](sandboxing-tutorial.md). It is slower than booting
— that is what the numbers above say — so it is not for speed. It is for
handing someone a heap: a sandbox with a library already in it, or a bug
report that is the state at the moment it broke.

Same format, same passes, no privilege. Only the last step differs: wrap the
root with `Base wrap` instead of installing it.

## The writer, and the discipline it needs

**Where this ended up, before the account of how.** The writer enumerates by
walking the heap chain, filters by asking the collector what is reachable
(`(heap trace! base)`, read the flag, `(heap untrace!)`), and reads each
object's units through its type's shape. Two passes: stamp an index into
metadata slot 1, then resolve every unit against those indices.

The subsections below are the record of arriving there, and several of them
are accounts of approaches that did not work — a walk that computed
reachability itself, a walk seeded from named base fields, a walk that treated
the base tree as ordinary structure. They are kept because each one failed for
a reason about this heap that is worth knowing, and because the reasons are
what argued for the engine change rather than a preference.


The writer is x, and a first pass over the heap — asking each object its
extent — is written and works: **88,705 objects, 169,838 units, zero
refusals** on a booted helium. Getting there needed two rules that are not
optional and were each learned by being killed by the OS.

**Bare primitives only in the loop, and that includes the reflective
accessors.** `%reflect-meta-set!` is x, not C — it runs a `match`, calls
`%reflect-flags`, and uses the *guarded* `&` — so calling it per object cost
three times what inlining the same three raw word operations does. The library's guarded operators are
enormously more expensive than the coordinates under them, measured over 2,000
iterations of an otherwise empty loop:

| loop body | allocations per iteration |
|---|--:|
| guarded `>`, variadic `+` | 486 |
| bare `eq?`, variadic `+` | 111 |
| bare `eq?`, `(int +)` | **35** |

`>` alone accounts for ~375 of those, because it routes through `or`, `null?`
and `%arith-guard`'s `match`. Fourteen times fewer allocations for the same
loop. This is [contributing.md](contributing.md)'s prim-caching rule, and a
reflective pass over 90k objects is exactly where ignoring it stops the
process: three attempts at this pass were SIGKILLed at ~19,400 allocations per
iteration before the operators were the suspect. Two wrong diagnoses came
first — `let` in the loop, then lost tail calls — and the control that settled
it was an *empty* loop, which allocates 491 objects an iteration all by
itself.

**Hold the cursor as an object, not an address, and the walk can collect.**
(*Why* it survives is not established: the claim below that a function
parameter roots what it holds was never tested by that experiment, since the
cursor was reachable from the base regardless. A collecting reachability walk
whose worklist is reachable from nothing else does survive, which is evidence
for it, but not proof.)
A raw-address cursor cannot survive a collect — the object under it is freed
and the address dangles — and that is why the first version of every pass here
was pure accumulation. But a cursor held as an ordinary x value is a function
parameter, so it is rooted, and the sweep relinks its heap word past whatever
it freed. A mid-walk collect is then safe, and it is what makes the writer
affordable:

| pass 1 | peak live objects |
|---|--:|
| first working version | 139M allocated, none reclaimed |
| bare prims + a last-type cache | 45M allocated, none reclaimed |
| object cursor, collecting every 4096 objects | **3.0M peak** |

Fifteen times less memory than the disciplined non-collecting version, and it
is also *more correct*: the collect reclaims the writer's own setup garbage,
which a non-collecting walk would otherwise reach and index. The collecting
walk indexed 83,729 objects against 82,846 live at walk start — over, not
under, so nothing live was missed.

Even so, keep the passes few and the loops bare. At ~500 allocations per
object visited the writer is near the floor of what an interpreted loop costs,
and that floor is what decides how many passes the design can afford.

### The two passes, and what they measured

Indices cannot be assigned and resolved in one walk — a reference can point at
an object the walk has not reached yet — so the writer is two passes.

**Pass 1 stamps an index into metadata slot 1.** This is the forwarding-slot
trick, and it is what makes the writer affordable at all: an 88k-entry side
map built in interpreted x would cost about what the boot costs, while a meta
slot turns an address into an index in O(1) with no map. Slot 0 is already
taken — it holds the source line the error machinery reports — and slot 1 is
unowned by lib and specs. The writer perturbs it and does not restore it,
which is acceptable because a write runs once, at the end of a build step, in
a process that then exits.

**120 objects will not take a stamp**, and they are the same 120 every time:
`meta-set!` is a documented no-op on an object without `%obj-flag-meta`, and
these are the objects allocated by engine init *before* x set the metadata
width. They are a contiguous tail of the walk — indices 88,703 to 88,822 of
88,822, newest-to-oldest — because the chain walk reaches the oldest objects
last. So they need a 120-entry side table and a range check, not a general
fallback map.

**Pass 2 resolves every unit per its type's shape.** On a booted helium:

| units | count | | references | count |
|---|--:|---|---|--:|
| `ref` | 145,510 | | resolved | 121,545 |
| `bytes` | 6,216 | | nil | 23,681 |
| `word` | 1,113 | | unstampable tail | 265 |
| `foreign` | **148** | | unresolved | 19 |

Nothing was refused for want of a shape. The classification cross-checks
against the census at the top of this document, arrived at by a completely
different route: `foreign` is 148, which is exactly the 129 primitives plus 17
pointers plus 2 buffers counted there; `bytes` is the strings plus the
symbols; `ref` is the pairs times two.

> **Do not give one value two meanings — especially not in this design.** Pass
> 2's first run segfaulted because it used `-1` for "this type declares no
> units", and `-1` is already the dynamic-size sentinel. BUFFER declares
> nothing, so the pass read its slot 0 as a unit count and walked off into
> whatever the arithmetic produced. Refusal needs its own flag, and the C
> loader will need the same separation.

**The writer perturbs what it measures, and the mechanism is exactly one
thing: `set!` on a global.** A global's binding is a pair in the environment,
the environment is part of the heap being imaged, and `set!` repoints that
imaged pair at a freshly allocated value that pass 1 never indexed. One
mutated global, one unresolved reference.

That is measured, not reasoned. The writer mutated 17 globals and pass 2
reported 19 unresolved references; adding three more counters that do nothing
but increment took it to **22**, exactly as predicted.

So the rule is not "allocate nothing between the passes" — allocation is
harmless, because anything allocated after pass 1 is newer than the cursor and
never walked. The rule is:

> **The writer must not mutate any object inside the heap it is imaging.**
> Its state belongs in call frames — threaded through the recursion as
> parameters — not in mutable globals. Frames created during the walk are new
> objects: never visited, and never referenced by anything imaged.

The one permitted exception is pass 1's stamp, which writes *metadata*, not a
unit. Metadata is not part of any object's imaged content, so repointing it
cannot dangle a reference.

Two candidate fixes are thereby ruled out rather than left open: allocating
nothing between passes solves a problem that does not exist and reinstates the
memory ceiling the collecting cursor removed; and walking pass 2 over a
recorded count does not help, because the unresolved references are *inside*
objects pass 1 legitimately indexed.

The residual count drift — pass 1 reporting 83,598, 83,640 and 83,706 across
three runs — has the same cause and the same fix.

**Built, and the result is determinism.** Rewritten to thread its state, the
writer reports the *same numbers every run* — 84,042 indexed, 79,828 visited,
across three consecutive runs with no variation at all, where the mutating
version drifted by ~100 each time. That is not a nicety: an image is only
reproducible if the writer is.

Unresolved references fall from 19 to **6**, and the six are structural rather
than incidental. They are the base's own control and I/O state: `save-stack`,
`error-handler`, `env-alist`, `line`, `err-line`, `err-file`, `state`, `file`
and `sigint` all hold values pass 1 never indexed, because the evaluator
repoints them continuously *while the writer runs* — the writer cannot stand
outside the interpreter that is executing it.

Which is not a defect to fix but the `(foreign drop)` category arriving on its
own. Every one of those fields is control state, reader position, or an I/O
handle: nil at the quiet seam, meaningless in a saved image, and rebuilt by the
loader against the fresh base. `env-alist` is the sharpest case — it is the
*live* environment, including the writer's own frames, and what an image wants
is `env-global-tree`, which indexes cleanly and does not appear in that list.

**It holds across the dialects, unchanged.** The same writer, run against each:

| dialect | indexed | visited | unresolved | refused for want of a shape |
|---|--:|--:|--:|--:|
| helium | 84,130 | 79,917 | 6 | **0** |
| xenon | 132,670 | 128,409 | 6 | **0** |
| radon | 133,569 | 129,308 | 6 | **0** |

Xenon and radon were the point of the exercise and bring a numeric tower the
walk had never seen — bigint, rational, float, complex, decimal, regex — and
not one of those types failed to state its extent. The six unresolved
references are the same six base control cells in every dialect, which is what
one would expect of something structural. Each run reproduces its own numbers
exactly.

So the writer's analysis half is done: every live object states its extent,
every unit classifies, and every reference resolves except the ones the design
already said to drop.

### An image reaches disk, and what it does not yet contain

Pass 3 pours each object's record into one raw block — type index, flags,
extent, then its units — and hands the block to `write(2)` in a single call.
Nothing walks bytes, for `lib/x/tool/asm-cache.x`'s reason. A booted helium
emits **3,152,336 bytes across 80,306 object records**, and reading the file
back parses cleanly:

```
record 0: type=83926 flags=128 extent=1 units=[0]
record 1: type=83972 flags=128 extent=2 units=[83580, 0]
```

Types and references are **indices, not addresses** — indices 0, 1 and 2 are
reserved for nil and the two static type tags, so pass 1 stamps from 3 and no
pointer reaches the file.

Three defects were found by reading the file back rather than by writing it,
which is the argument for doing so:

- **The header disagreed with the body.** It carried pass 2's object count,
  and pass 3 emitted 174 more. The general fault is conflating an estimate
  with a description: pass 2's counts size the buffer, they do not describe
  the file, so the header is now written last from what was actually emitted.
- **The magic was wrong**, reading `GSFX` rather than `XIMG`.
- **The root index was 0**, and that one is not a slip.

> **The base is not a chain-linked heap object, so no walk can reach it.**
> Three measurements say so together. Its flags word is **0**, where every
> ordinary object carries the metadata bit (128, or 160 for an owned string).
> Its type word sits in the static address band but is *neither* static tag —
> `4366025000` against `satom` 4366027776 and `spair` 4366027808 — which is
> the engine's own base sentinel, the one `x_type_heap_mark` special-cases to
> traverse a base's pair tree instead of treating it as an object. And walking
> the chain *from* the base never terminates, where every real chain walk ends
> cleanly, because word 0 of a base is not a link.
>
> So the root is **emitted out of band** — taken from `(%base)` and given a
> reserved index — and that is not a workaround for a walk that ought to find
> it. Nothing on the chain can find it. The base's *contents* are ordinary
> pairs and are imaged normally; only the base object itself is special, which
> is exactly how the collector already treats it.

So the file on disk is a faithful record of the object graph's *structure* and
is not yet loadable. Outstanding, in the order they block a loader: the root;
the byte blob, since `bytes` units emit 0 and string contents are absent; the
foreign table, since `foreign` units emit 0; and the side table for the other
119 unstampable objects, whose 265 incoming references also emit 0.

### The base tree cannot be walked generically

Reachability from the base — the walk this document has argued for since "an
image writer is a mark phase that emits" — crashes deterministically about
32,768 objects in, and always on an object flagged SHARED, which x-heap.h
reserves for base tree nodes.

The cause is visible once every unit pushed from a SHARED node is printed.
Slots in those nodes hold addresses around 4.31e9, the static data band. One
holds **6160731856** — the text band, where the seventeen `dlsym` results from
the census live. It is a **raw C function pointer sitting in a structural
pair**, and `x-heap.c` reads the collector's own hooks exactly that way:
`x_firstptr(x_firstobj(x_base_field_heap_mark(p_base)))`, a pair whose first
is a function pointer rather than an object. Following it as a reference and
dereferencing it is a wild read.

So a structural pair is not always two references, and the rule that every
other type obeys does not reach here. **The base tree must be walked through
`base-layout.x` and `base-paths.x`** — the committed descriptors that say
which leaves are cells, which are direct values, and which are external —
exactly as `lib/x/boot/reflect.x` walks it, and never as ordinary structure.

This is the same lesson BUFFER teaches one level down: a per-type shape
describes a type whose instances agree, and the two places that break the rule
are the two the engine already treats as special.

Four theories died before this one, and the discipline that killed them is
worth as much as the answer. Raw values in base slots — disproved, the I/O
fields are ordinary atoms holding their values. Non-pointers pushed as
references — a guard for small words never fired. The mid-walk collect
freeing the worklist — an identical crash with collecting disabled, which also
clears the collect of suspicion. And before those, the collect interval, which
changed nothing.

### Let the engine compute reachability

Walking reachability in x was the wrong instinct. The collector already knows
what is reachable, including everything that kept catching this walk out: the
base sentinel, the base spine's function pointers, PROCEDURE's custom mark
handler, the mark hooks and the root chain. `x_heap_tree_mark` is that walker,
it takes the flag to set **as a parameter**, and `(heap pin!)` is an x-level
door to it. So the writer should not recompute reachability; it should ask,
then use the chain purely as an enumerator and the flag as the filter. That is
the "mark phase that emits" thesis done literally rather than reinvented.

Neither existing flag can carry it, and both failures are informative.

**SHARED cannot**, because `x_heap_tree_mark` uses the flag it sets as its own
visited test: `while (p_obj != NULL && (x_obj_flags(p_obj) & flags) != flags)`.
Base tree nodes are *already* SHARED, so the traversal halts at the first one
it reaches. Measured: pinning from the base moved the SHARED count from 1,882
to **1,884** — two objects — while 85,431 were live.

**The GC's own mark bit cannot**, because leaving it set across a collect is
unsafe in exactly the way `heap collect`'s comment warns about. The next
collect's mark phase would treat the pre-set objects as already visited, stop
short, and its sweep would then free their unmarked children. And the walk
must collect to stay bounded, so "mark once and never collect" is not
available either.

**And there is no spare bit.** All four attribute bits are aliased by the eval
layer — `X_OBJ_FLAG_1..4` are `SHADOW`, `COV`, `FRAME`, `FNFRAME` — and
`own`, `ro`, `meta`, `shared` and `mark` are all taken.

**Built, and measured.** `X_OBJ_FLAG_TRACE` (0x400), `x_heap_chain_clear`,
and the coordinates `(heap trace! obj)` / `(heap untrace!)`:

```
live objects:            85,466
chain / traced before:   83,522 /      0
chain / traced after:    83,521 / 79,407
chain / traced cleared:  83,540 /      0
```

The bit starts genuinely unused, `(heap trace! (%base))` marks **79,407**
objects, and `(heap untrace!)` takes every one of them back. Against the
33,823 a reachability walk written in x could reach, that is the measurement
that settles it: **the collector's traversal sees more than twice what an x
walk can**, because it accounts for the base sentinel, the spine's function
pointers, custom mark handlers, the hooks and the root chain.

The 4,114 chain objects it does *not* mark are the writer's own state and
garbage — precisely what an image must exclude, isolated for free rather than
by discipline.

The clear is a CHAIN walk, not a tree one, and not an unset mode on
`x_heap_tree_mark`. The mark hooks are why: `x_type_heap_mark` calls back into
the tree walker with the flags it is handed, so an unset mode would have hooks
*setting* the flag on children unless the mode threaded through every hook
signature. A chain clear sidesteps that and is strictly more complete — it
reaches objects that became garbage after the trace, which a tree walk would
leave flagged for good.

So the door is a small engine change, and the heap is already built for it.
Both halves of the collector are **flag-generic**: `x_heap_tree_mark` takes
the flag to set, and `x_heap_sweep` takes the flag to test — keeping what
carries it, `&= ~flags` on the survivors, freeing the rest. Mark and sweep
over the same flag are already a complete cycle that leaves no residue.

What imaging needs is that cycle without the freeing: set a flag over the
reachable set, read it, clear it. Three pieces:

1. **A new flag above `mark` (0x400)**, because no spare exists, with a row in
   `obj-layout.x` where `make check-obj-layout` will hold it.
2. **A clear mode on the tree walker.** The guard inverts by itself, which is
   why this is small rather than a rewrite — the flag is the visited test in
   both directions:

   ```c
   /* set   */  while (p && (x_obj_flags(p) & f) != f) { x_obj_flags(p) |=  f; ... }
   /* clear */  while (p && (x_obj_flags(p) & f) != 0) { x_obj_flags(p) &= ~f; ... }
   ```
3. **One coordinate** exposing both with a caller-chosen flag, rather than
   `pin!`'s hardcoded SHARED.

The walker already does the work; it only needs somewhere to write the answer
that nothing else is reading, and a way to take it back.

> **A tree clear only reaches what is still reachable.** Anything that became
> unreachable between the mark and the clear keeps the flag for good. That is
> harmless in a writer that exits — which is the only mode this design claims
> — but a long-running process wanting to image itself repeatedly would want a
> chain-based clear instead, in the shape of `x_heap_root_chain_mark`'s
> existing pre-clear pass.

**What this replaces.** Seeding the walk from named base fields does not work:
`type-alist` reaches 33,781 objects, every other field adds almost nothing
because they are already reachable through it, and the total stalls at 33,823
of 85,431 live — 39%. Whether the missing 61% is the writer's own machinery
(which an image should exclude) or real data (which it must not) cannot be
settled by adding roots, which is the argument for asking the collector
instead of guessing.

### BUFFER cannot be described by a per-type shape

The only two objects that could not state their extent were the reader
buffers, and looking at why turned up a limit the shape design did not
anticipate. A BUFFER is two units: a raw `char *` and a reference to an inner
bookkeeping object which is *itself* BUFFER-typed and holds two raw `char *`
cursors. So the outer instance is `(bytes ref)` and the inner is
`(bytes bytes)` — **the same type, two shapes.**

It costs the collector nothing, because BUFFER has a custom mark handler and
its shape is never read. It costs the image nothing either, because buffers
are not imaged: they are cursors into a char array, the loader's fresh base
has its own, and the base field is repointed. But it means a per-type shape is
not universally sufficient, and a type whose instances differ has to say so
some other way.

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
- **Whether the loader may allocate one arena instead of N objects.** Pass 3
  currently allocates per object to keep the heap chain and the free path
  exactly as they are. A contiguous arena threaded onto the chain would be
  faster still, but it changes what `x_obj_free` may assume, so it is a second
  step and not a first one.
- **The writer's own `def`s cost holes.** Each one added between the passes
  repoints an imaged environment pair; adding two took the count from 6 to
  10. The mutation-free rule applies to the writer's setup, not only its
  loops.
- **Whether a per-type shape is enough.** BUFFER says it is not: one type,
  two instance shapes. Nothing needs it today — buffers are not imaged — but
  the next type whose instances differ will need an answer, and the format
  has no place to put one.
- **What ash costs, and whether an image can carry a tokenizer base.** ash was
  the dialect that prompted this and is not installed here, so it is unmeasured
  — though xenon and radon both walk clean, which is the tower ash sits on.
  It is also the bundle that cannot take the per-turn collect
  ([crafting-a-lang.md](crafting-a-lang.md) §6), and an isolated tokenizer base
  that does not survive collection may not survive imaging either.
- **Where the writer runs.** It needs the reflective walker, which lives in the
  library, so it runs *inside* the dialect it is imaging. Consistent, but it
  means a dialect must boot once to produce the image that skips its boot.
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
- **A profiling build of the wrong engine boots partway and dies.** The first
  profile run here was built from a checkout predating the library's engine
  requirements; it segfaulted 25 includes in, and its timings looked like a
  fast boot rather than a crashed one. Check that the probe produced its
  *answer*, not just a plausible number.
- **`obj ->ptr` on nil segfaults.** A reflective walker meets nil constantly —
  every list terminator, every empty field, every unbound cell — and the raw
  door has no nil check. Guard before every conversion, not after the first
  crash.
- **A `def` inside a hot tail loop is not free.** The census loop, written
  with three inner `def`s, grew the environment enough that the process was
  killed by the OS at 120,000 iterations. The same loop written without them
  walks the whole heap without noticing. This is worth knowing well beyond
  this document.

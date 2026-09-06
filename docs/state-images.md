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

## The reader: a loop in C, the rest in x

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

It also rules the *per-object* work out of x. A bare heap walk — following
the chain and counting, nothing else — costs 0.81s over helium's heap and
2.28s over xenon's, which is ~3µs per evaluator operation. A reader needs
roughly twenty operations per object, so ~9s against a 5.65s boot.

**So the allocate-and-patch loop is C, and nothing else has to be.** The first
draft of this document put the whole loader in C, reasoning that a reader must
run before x exists. That reasoning is wrong, and the next section prices what
it would have cost.

The writer stays in x throughout: it runs once, offline, inside the dialect it
is imaging, where 2s does not matter.

### The reader hosts below the library, and that is most of the C

A loader that must run before x exists has to do all of it in C: read the
file, verify the header, resolve every foreign entry, allocate, patch, and
explain itself when any of that fails. Call it 350 lines. But **it does not
have to run before x exists — only before the *expensive* x exists**, and
those are not the same moment.

Where xenon's boot actually goes, measured by including each stage over a
helium base:

| stage | cost | share |
|---|--:|--:|
| helium | 0.83s | 16% |
| the numeric tower (`lib/x/boot/tower-compiled.x`) | +2.92s | 56% |
| `lib/x/xe.x` | +0.13s | 2% |
| the rest of `lib/x/boot/xenon.x` | +1.36s | 26% |
| **xenon** | **5.24s** | |

(One sitting, so the totals are internally consistent; boot timings on this
tree vary ~10% run to run, which is why they differ slightly from the eval
table above.)

Everything the four passes do *except the per-object loop* is per-entry work
over hundreds of items — one header, ~150 foreign entries, ~1,000 static paths
— which x does in tens of milliseconds (measured below). So the division is:

- **x** — open, verify, resolve the foreign table, install, and say something
  useful when any of that fails.
- **C, one primitive** — allocate N objects from the extent table and patch
  their units. Per-object across 154k objects, so it can be nothing else.

That is ~80–100 lines and one ISA coordinate against ~350 lines and five kinds
of resolution logic. The C refuses with a code; x turns the code into a
sentence. Which is the division the ISA contract already states in its opening
lines: the C layer is a CPU, and checks, dispatch and policy live in x.

**But the host may not be a dialect.** The reader is x, so *something* must be
booted before it runs, and that something is a floor under every load. helium
is the tempting host — it has `Sys/open-read`, `Sys/fd-read`, the catalog and
the whole library vocabulary — and for a xenon startup its 0.83s is a fair
trade against 5.24s. It is the wrong answer anyway, because the suite is the
consumer that matters and helium costs more than what the suite loads. The
next section measures that.

### Restoring compiled code needs no C either

The tower is 56% of what an image would cache, and the tower's headline is a
JIT burst — `compile-asm` assembling analysers in process. Machine code is the
one thing that looks like it must be reconstituted in C: it needs executable
pages, and every address it baked in is wrong in a new process.

Both were solved before this document existed. `%asm-cache-pour` in
`lib/x/tool/asm-cache.x` already pours cached bytes into a fresh buffer and
re-encodes every baked address for the loading process, across three
relocation kinds — trampoline, fvar, self. The lane is:

```
asm-new (mmap) -> one read(2) into the buffer -> walk the relocation records
-> asm-finalize! (mprotect R+X) -> (obj make-callable code)
```

All of it is x calling libc through `dlsym` and `ptr-call`: `%asm-mmap` and
`%asm-mprotect-rx!` are not primitives. The only ISA coordinate in the whole
lane is `(obj make-callable alloc)`, which is already pinned.

So an image need not store machine code at all. The analysers are reachable
from the heap — they are swapped into the symbol type's analyse list — so
*something* callable must land in those slots; but a foreign entry can name an
**asm-cache key**, and resolving it calls the existing pour. One more foreign
kind, resolved in x, no C. The two mechanisms already agree on identity: the
cache keys on `x-machine` and `x-release`, which is the refusal the image
header makes on arch and engine release.

And the JIT matters less than its share suggests. Booting xenon with the cache
stashed, and again with it in place:

| | xenon boot |
|---|--:|
| cold — 12 compiles | 6.27s |
| warm — 12 pours | 5.80s |

Compiling is worth ~0.5s, about 8% of the boot. The tower's 2.92s is
overwhelmingly *interpreted construction* — types, classes, methods, closures
— which is precisely what an image caches wholesale and what no narrower cache
can reach.

### The suite is the consumer, and it sets the host

Boot elision is not mainly an interactive nicety here. The spec suite pays the
same boot once per spec file, and that is where the time is:

| | |
|---|--:|
| `make test-x`, whole suite | 299s |
| tests / spec files / jobs | 2,792 / 143 / 43 |

`tests/spec-runner.awk` cuts a batch only when the declared library changes,
so it is **one interpreter per spec file**, and each one re-evaluates that
file's library from source. `lib/x/specs/lib/ansi.spec.md` runs a single test
in 0.86s; almost all of it is the library.

Which sets the floor, and the floor is the whole design constraint:

| | |
|---|--:|
| engine start + parse, no library at all | **0.05s** |
| `lib/x-core.x`, the default (97 of 143 files) | **0.90s** |

**The engine's own floor is eighteen times cheaper than the library the suite
loads.** So a host that is itself a dialect cannot pay: helium's 0.83s is
indistinguishable from the 0.90s it would be replacing, and 97 files would
save nothing. On the x-core files alone the library costs ~82s of the 299s,
and the heavy-library files — `decimal` 15s, `sha256-jit` 16s, `tower` 13s,
`compile` 12s — pay far more than 0.85s per spawn.

**So the host is the engine plus a loader prelude, not a dialect.** That is a
requirement, not a preference, and it decides what the reader is written in:
on a bare base there is no library, and `fn` itself is derived, so the prelude
defines what little it needs or the reader is written in `op` directly.
Everything it actually needs is already a primitive — `ffi dlopen`/`dlsym` and
`ptr call` for the file, `first`/`rest`/`pair` for the foreign table, integer
ops, and the one new loop coordinate. `lib/x/tool/asm-cache.x` is the
precedent and was written at exactly this level for exactly this reason: it
fetches bare prim doors because the library layer was too expensive for the
job it does.

The C budget does not change. What changes is that the reader's x half may not
lean on the library it is about to load.

That prelude is `lib/img.x`, loaded with `sh x.sh -l img`, and it is measured
rather than argued: **0.05s to boot**, and the whole x-core image — 98,508
objects, 15 instanced types, 1,084 statics, 149 foreign entries, 209 type
cells — **loads, installs and evaluates in 0.45s**, against 0.90s to boot the
same x-core from source. The same reader hosted on helium took 1.95s, and
0.88s of it was helium. Where the 0.45s goes:

| phase | cost | what it is |
|---|--:|---|
| boot img | 50ms | `if`, `do`, `prim-ref`, byte strings, reflection, shapes |
| read | 5ms | one `sys read` into raw memory |
| types | 87ms | 19 names matched to live types, absent ones registered, shapes |
| statics | 170ms | 1,084 base-path walks from the target base |
| foreign | 44ms | 149 names reacquired |
| rebuild | 9ms | the one primitive, allocate then patch |
| roots, cells | 36ms | two env roots and 209 handler stacks written into place |
| eval | 0.7ms | `(write (list 1 2 3))`, through the image's own printer |

So "per-entry work in milliseconds" above is right in kind and optimistic by an
order: the statics walk is ~0.16ms an entry and there are a thousand of them.
It is the next thing to cut, not a floor.

The prelude carries everything the library would otherwise have supplied and
nothing else: `(obj ref)` and `(obj set!)` are not engine primitives — the
engine's own comment says they are "pure x-lang now" — so img defines them
from the same addressing formula as `boot/data.x`; type names and units cells
are walks of the type-rooted rows of `base-paths.x`; the unit shapes are the
rows of `lib/x/type/shape-rows.x`, split out of `type.x` so that one file
feeds both helium's boot and this one. Its `do` is two operatives handing the
body to each other through `tail-eval`: a helper *procedure* does not keep a
tail call in constant stack, and a 300,000-step loop found that out.

### The type-cell table

A type struct is base state — a static, walked by name — but what the
library *pushed* onto its stacks is heap. Every `-stack` row of the layout
contract reaches the head pair of a handler list, `(handler . older)`, and a
push writes a new head into the parent's slot. Those heads are traced from
the base and stamped like any object, so the image already held every
printer and every class dispatcher; what it lacked was eleven words per type
saying which slot each hangs from. A loader that installs only the two env
roots gets a helium that can run `list` and cannot `write`.

The table is one entry per type per pushed-on stack — the eleven rows the
`type push-*` coordinates and the from/to cells name — in the statics' own
type-rooted form, `[object index][type name][steps]`, minus the tag word.
The loader walks its own struct to the parent and sets the half the last
step names. 209 entries, 36ms.

Installing them was also what surfaced two faults nothing had exercised,
because for the first time the host's collector and tokenizer walked into the
imaged graph:

- **The static sentinel was being read as an entry.** The writer emits
  −(SCOUNT+1) for a reference it cannot name so a loader can refuse it; the
  rebuild's bound was `<=` and read the word past the statics object
  (ASan: 0 bytes after an 8680-byte region). Strict now, like the foreign
  bound beside it.
- **The engine's own handlers were unnameable.** `STRING type-read-stack` is
  `(fn fn fn fn ATOM)` after the library's pushes: the C reader is the fifth
  element of a list, which no row reaches, and the tokenizer applies every
  element of an analyse list without a nil check. The atom *is* nameable — it
  is what a fresh base holds at `(type STRING type-read)`, and every loader
  has a fresh base — so the writer also walks a pristine `(Base make)` and
  records its off-chain nodes under the same type-rooted paths. Off-chain,
  not "atom-tagged": the token handlers are type-word-0 objects that `write`
  prints as nothing at all, and a filter on the tag skipped every one.

**Still unnamed, and harmless for now:** `%token-eof`, a global the engine
registers in every base whose value is a static the writer has no path to —
the name itself is the path, and that is a small new statics kind — and eight
nodes of the tokenizer's syntax table, a `todo` subtree of `base-layout.x`
that the loader never installs because it keeps its own. Both restore as nil.

**What this does not fix**, so the arithmetic stays honest:

- **The per-snippet collect.** The runner emits a collect at every snippet
  seam, which is why `tower.spec.md` is 14.6s for fourteen tests. An image
  removes that file's boot, not its thirteen collects over a large heap.
- **One image per library.** The suite names 28 distinct ones, each stale the
  moment its sources change — so the runner needs a freshness rule, and the
  header's digests are only half of it.

## What the loader may not assume

This is the constraint that shapes the format: **an image is loaded by a
process that is not the one that wrote it, so not one address in it
survives.** Every foreign unit has to be *reacquired* by name, and the name
has to mean the same thing on the far side.

Putting the resolving in x relaxes what may do it — it is x, so it may call an
x closure — but it does not relax the discipline. The
vocabulary stays **closed and declared**, because the refusal is the point: a
type whose foreign values cannot be named this way should be told so at write
time, not have it discovered at load time.

| kind | payload | how it is reacquired |
|---|---|---|
| `nil` | — | NULL |
| `catalog` | ns, method | walk the host base's prims catalog |
| `bare` | name | look up the host base's boot binding |
| `dlsym` | library, symbol | `dlopen` + `dlsym` |
| `fd` | role (in/out/err) | the process's own descriptors |
| `asm` | asm-cache key | `%asm-cache-pour` re-pours and relocates |

A `foreign` unit whose value is not one of these **makes the write refuse**.
Types wanting richer reacquisition get it after boot, from x, through
`internalise` — but then their instances are not part of a startup image, and
saying so at write time is the whole point of the refusal.

The measured foreign surface fits this: a booted helium's 147 address-holding
objects are 129 primitives (catalog or bare — both nameable) and 17
pointers that are sixteen `dlsym` results over one `dlopen` handle.

## Naming the statics: a reference into the base is a path, not a copy

266 references from imaged objects point at objects that carry no metadata
word and so cannot hold an index. They are **185 distinct objects, and they
are the base's own spine** — measured by dumping them:

```
#<ATOM:0x0>  #<ATOM:0x1>  #<ATOM:0x2>          the three file descriptors
(())   (#<buffer> ())   ((#<ATOM:0x2>) (()) (#<buffer> ()))
                                               the pair tree holding them
```

Those atoms are exactly what `filein`, `fileout` and `fileerr` answer, and the
pairs are the io group they hang from. None of it is heap-allocated: it is
built at base creation, which is why it has no metadata prefix and why the
chain walk never reaches it.

So a reference into that structure must not be *copied*. The host base has its
own — at different addresses, with different descriptors — and copying would
produce a second, dead spine alongside the live one.

**Record the walk instead.** Every one of these objects sits at a fixed
position in the base tree, reachable by a sequence of `first`/`rest` steps
from the base. That is exactly the vocabulary
`engine/tools/contract/base-paths.x` already commits — its rows *are* step
lists, `make check-base-paths` re-derives them from the C headers, and
`lib/x/boot/reflect.x` already walks them at runtime. So the foreign table
gains one more kind:

| kind | payload | how it is reacquired |
|---|---|---|
| `base-path` | a step list (`f`/`r`) | walk it from the host base |

It needs no new contract: the steps are the ones already checked.

Recording steps rather than a field name matters, because not every node in
that tree is named. The fd atoms sit at named rows; the interior pairs holding
them do not, and a reference can land on either. A step list addresses both,
and degrades to the named case when a row happens to match.

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

Four passes. One and two are x on the host; three and four are the one
primitive, being the only per-object work:

1. **Verify and arm.** *(x)* Check the header against this engine — release,
   os, arch, byte order, word size, and each layout digest. Set the
   extra-metadata width. Any mismatch refuses here, before a byte is
   allocated — and refuses in a sentence, which is the point of doing it in x.
2. **Resolve foreign.** *(x)* The host is already a base, so its types and
   primitives exist even with no library on top: resolve every foreign entry
   against it and pin the results. They are about to be referenced by objects
   the host cannot see, and nothing else is keeping them alive.
3. **Allocate.** *(C)* One object per record, from the extent table, in index
   order. Fill nothing. Keep the index-to-pointer table.
4. **Patch.** *(C)* Walk the unit stream, writing each unit per its kind. Set
   the flags the image records, including `X_OBJ_FLAG_SHARED` where it had it.

Then `Base wrap` the image's root and evaluate in it. The host stays where it
is; what it contributes is exactly what pass 2 pinned, which is correct —
identity is by path, so the image's reference to bare `+` *is* this process's
bare `+`.

**Identity needs one interning table and no more.** Two saved references to
one object must come back as one object, and two that differed must stay
distinct. The index table gives that for free within the image; the foreign
table gives it across the boundary, which is why naming is by path and not by
value — resolving bare `+` and catalog `(int +)` to the same object would
merge two the running base kept apart.

## One path, not two

An earlier draft of this document had two. A privileged startup loader that
*replaces* the process base, for boot elision; and a gentler reader callable
from x that builds a **child base**, as in
[sandboxing-tutorial.md](sandboxing-tutorial.md), for everything else. The
first was the hard case and carried all the risk.

Hosting the reader in x collapses them into one. There is nothing to replace:
the host boots, loads, wraps the root with `Base wrap`, and evaluates in it. Boot elision, a sandbox with a library already in it, a bug report that
is the state at the moment it broke, a REPL that outlives its process — one
path, no privilege, and the hard case simply stops existing.

## The writer, and the discipline it needs

**Where this ended up, before the account of how.** The writer enumerates by
walking the heap chain, filters by asking the collector what is reachable, and
reads each object's units through its type's shape. Two passes: stamp an index
into metadata slot 1, then resolve every unit against those indices.

```x
(heap tree-mark! (%base) 1024)   ; the collector answers; 1024 is ours to pick
   ... walk the chain, act on flagged objects only ...
(heap chain-clear! 1024)         ; take the bit back
```

Measured on a booted helium: **80,398 objects indexed, 1 unresolved
reference, 2 extents refused** — the two BUFFERs, whose type declares no
units. Against 33,823 objects for the best walk that computed reachability in
x. The worklist, the visited set and the base-tree special case are all gone:
the chain is an enumerator, the flag is the filter. The byte blob those
objects need is **191,087 bytes**.

> **Every walk goes through one helper, and it returns what it visited.**
> Written once because writing it per pass produced the same three faults
> repeatedly: a PTR cursor, which roots nothing it addresses, freed under the
> walk by a collect; a collect on the first iteration, while the start object
> is still an unrooted temporary; and — the one that did real damage — a pass
> that visited nothing and therefore reported zero of everything. A clean zero
> over zero objects was reported here as a result. The helper holds its cursor
> as an object and returns `(acc . visited)`, so that cannot recur silently.

**The unresolved references are the writer's own bindings**, one per `def`
evaluated after the mark. A `def` repoints a pair in the environment, the
environment is inside the heap being imaged, and the value it now points at
was never stamped. Measured by prediction twice: three extra `def`s gave
exactly three more, and hoisting the reporter's definition above the mark took
five down to one.

The last one does not go away by discipline. The writer runs inside the base
it is imaging, so evaluating anything at all leaves a trace on the thing being
recorded — the same fact as the base control cells above. The structural fix
is to run the writer in a base of its own: a child shares the heap chain,
which no longer matters now that reachability comes from the collector, but it
does *not* share the environment, which is where this last reference lives.

**What running the writer in a child actually costs.** Attempted, not
finished, and the obstacles are worth recording before anyone tries again:

- A bare child is the C ISA and nothing else, so **every form has to be handed
  in** — `do`, `if`, the variadic arithmetic, all of it. They bind and work
  (`Base bind` carries operatives and parent closures fine, and a parent
  closure called from the child resolves its own library names), but the
  writer must be written against whatever was passed, not against the library.
- **A closure in a child captures its environment as a snapshot**, so a name
  defined *after* it is invisible. Mutual recursion that works in the parent —
  where the globals BST inserts in place — fails silently in a child. The walk
  had to be restructured to pure self-recursion.
- **A collect from the child is survivable.** It marks from the child's roots
  and sweeps a shared chain, which looks alarming, but the parent came through
  intact and kept evaluating. That is worth understanding properly rather than
  relying on.

Against a payoff of **one reference** on helium, that is not yet worth it. The
discipline half is free and already banked: nothing defined between the mark
and the last pass took seven down to one. The child-base writer is the right
shape for a writer that is a module rather than a prototype — written for the
child from the start, instead of retrofitted into it.

**120 traced objects cannot hold an index, and do not need one.** Their flags
carry no metadata bit and their type words are the two *static* type objects,
which makes them compile-time constants in the binary rather than heap
allocations — `x_obj_set` statics, with no metadata prefix to stamp. Nothing
in the image references them: the measured count of references into that set
is zero. A loader's fresh base brings its own, so they are excluded rather
than restored, and the side table this document previously wanted for them is
not needed.

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
  time. An image is that result: against ~300 evals per live object today, a
  load starts from the engine's 0.05s floor rather than a dialect's seconds.
- **Sandboxes with a library in them**, without replaying the library.
- **A bug report that is the heap.** The state at the moment of a defect,
  written out, loaded elsewhere, inspected with the tools in the tree.
- **Session persistence** — a REPL that survives the process.
- **Lang bundles that ship a booted image** rather than source to re-evaluate,
  which is a different answer to the cost [lang-scale.md](lang-scale.md)
  measures.

### The suite, booted from images: measured

The consumer arrived. `make test-x` writes one image per library the
specs declare (`make images` alone does that; `IMG=0` is the source-boot
control) — 25 of the 29, keyed so a lib edit rewrites them all — and
`tests/spec-runner.awk` boots each job from its image; `spec-runner.sh`
drops the bucket to one file per job when images are on, because a boot
that costs a third of a second no longer needs eight files to amortize it,
and a one-file job is what the timeout, the alloc ceiling, the crash report
and the parallel scheduler all wanted anyway. On the same box, the same
suite (2,804 tests from source; the image runs add the image spec's 15),
2026-09-05:

| | `IMG=0`: from source, 8-file buckets | default: from images, one file per job |
|---|--:|--:|
| serial | 304s | 280s |
| `PARALLEL=1` | 210s | 178s |

Where the rest of the time is: the suite is test-bound, not boot-bound. The
serial run's boots summed to roughly 70s before images and roughly 45s
after (140 boots at a third of a second); the heaviest single jobs are
tests, and images do not touch those. The two that stood out were then cut
along their fixture chains: `tools/pin` (25s, one file) is six files of at
most 7s, sharing `tests/x/lib/pin.x`, which makes the trees they read; the
two `bitwise-parity` files (17s each, five renders apiece) are five files
of two renders. `sha256-jit` (15s) stays one file: its cases share the
engine its first case builds, and a split would build it once per file.
The long poles are now `date`, `list`, `bitwise` and `str-class`, 11–16s
each, none of them a batch. The three JIT dialects (`x-base`, `xe`, `rn`)
were not imaged: their compiled tower entry points are unnameable, two
dozen words each since the analyser states compile. The next section
says how that was closed, and what still stands in the way.

### A lang bundle's suite, booted from an image of its harness

A bundle's spec harness (`tests/lib/harness.gen.x`, [lang-contract.md](lang-contract.md))
is a library like any the suite declares: an amalgam, the bundle's root
armed, its base module imported. `image-build.sh` takes it as the library
and the bundle's module tree as an extra key path, so the image is
rewritten when the bundle changes as well as when the platform does, and
the runner loads `lib/img.x` and the loader from `X_ROOT` -- the platform
root, derived from the runner's own location -- because the harness sits in
the bundle, where no loader lives. x-awk is the worked example (its
`tests/spec-runner.sh`, twelve lines): 167 tests, 38s from `x-base.x` to
16s from an image of an `x-core.x` harness, one file per job, 2026-09-05.

Two things the first bundle taught. **The harness must be on `x-core.x`**:
every bundle had booted `x-base.x`, whose compiled tower is unnameable, so
none of them could image until the amalgam list gained `x-core.x` (`make
boot`). And **`x-base.x` had been hiding a bug**: x-awk declares dialect
`he` and never imported the numeric layer its arithmetic assumes, so `x -l
awk` printed 0 for `1/4` while the suite, booted under a full tower, stayed
green. A harness on bare `x-core.x` -- the dialect the bundle ships -- found
it in one run (19 failures). The harness now imports `x/num/tower`
interpreted, which is the tower `x-base.x` gave it and images clean; the
gap in the shipped lang is recorded in the bundle, priced (the tower is 7s
of a helium boot) and left for the bundle to close. An `xe` or `rn` bundle
stays on `x-base.x` and from source until an image can carry compiled code.

Two facts the suite surfaced that the format doc now carries as invariants
11 and 12: a value an image cannot carry (`num/float.x`'s libm handle) is
a declared **transient**, written as nil and re-derived by the module's
recache hook; and the interned `#t`/`#f` share the singletons' bytes,
which `eq?` depends on and a rebuilt symbol had lost — `type/bool.x`'s hook
points them back.

### Compiled code: put down before the write, picked up after the load

A compiled analyser is native code in a page the writing process mapped,
and no name reacquires it in another process. The tower does not need it
to be *carried*, only *remade*: every compile in `boot/tower-compiled.x` is
the same shape, source over free variables, with an interpreted twin it
displaces. So each compile goes through a **site** that records where the
result went (a global, a type's analyse stack, one cell of the symbol
type's lists), the twin, a maker, and the value in place. Two walks over
the record: `%tower-unjit!` puts every twin back and lets go of the
compiled objects, run by the writer inside the child before its walk
(a thunk among `%image-transients`, the second half of the transient rule
in `boot/reflect.x`); `%tower-rejit!` compiles every site anew in boot order,
run by the loader after the install (`%image-recache-hooks`), asking the
lane again since the loading engine is not the writing one. Measured
2026-09-05: x-base's twelve unnameable words go to zero from the tower;
x-base, xe and rn each write clean at ~130K objects; the x-base smoke and
reader specs run from the image in 1s a file against 6s from source, and
a direct load-plus-rejit is 0.77s with every analyser native again and
`(/ 1 3)`, `1.5d`, `1+2i` and `(Num expt 2 70)` answering correctly.

**What refused them after that was not the tower.** After the un-JIT, four
words remain, and the writer now says who holds them (a holder chase,
printed with the census when anything is unnameable): `hit`, `cell`,
`buf`, `sl` -- the `def`s inside `lib/x/tool/asm-cache.x`'s own function
bodies. **A `def` in a closure's tail position bound globally**: the
engine decided top-level by an empty save stack, and a closure's frame is
popped before its deferred tail runs, so a def under an `if`/`do` in tail
position was global while the same def one form earlier was frame-local.
Every compile so left its last compiled function, self-cell and read
buffer in bare globals -- a clobbering bug in its own right, since a
user's `a`, `f` or `r` was overwritten by any compile. The fix is the
engine's (x-engine-c `feat/def-lexical-scope`): a `def` scopes by the
live frame, `eval!` evaluates its form as a top-level one (the REPL runs
inside the frames of `unless`, `if`, `do` and its own loop), and an
operative's restore sheds an inner operative's frame instead of keeping
it whenever the caller's head was "reachable" -- which, every chain
ending at the same bottom cells, it always was, so a `when` or `unless`
whose `if` took the empty branch had been leaving `test then else e` at
the head of the top-level environment for the rest of the session. That
engine is the pinned one (x-engine-c v0.2.8, #41), and on it `x-base.x`,
`xe.x` and `rn.x` write clean from the real library, on a cold asm byte
cache as much as a warm one. The distinction mattered on v0.2.7: the site
mechanism runs every compile inside a helper closure in non-tail
position, which the old rule classified as closure scope, but a cold
cache took the compiler's miss path and asm-compile.x's own tail-position
defs leaked (a CI runner found it: refused, fourteen minutes each), so
the three waited for the pin. `make images` lists them now.

## Not decided

- **A `dlsym` external names only the symbol, and on glibc that is not
  enough for a library the process dlopen'd itself.** CI's first Linux run
  of the writer found it: glibc keeps `num/float.x`'s libm out of the
  global scope, so none of its 18 pointers round-tripped and every
  float-loading library was refused there. Float's answer is the transient
  rule — each libm binding registers itself and one hook remakes them all
  — so no libm pointer is an external at all. A module that must keep such
  a pointer *as* an external would need a **library-qualified** one,
  `dladdr`'s `dli_fname` beside the symbol, resolved by the loader through
  a handle on that library: additive to format v1, and undecided until
  something needs it.

- **The writer half needs a door.** Reading needs the shape declaration above
  and nothing else; writing objects back means setting type words and flags, which today is raw word
  surgery of the kind `lib/x/boot/reflect.x` already does in `%reflect-retag!`.
  Whether that stays reflective or earns a primitive is open.
- ~~**How the runner knows an image is stale.**~~ Decided, and it is a
  content hash: `tools/dev/image-build.sh` keys each image on the library
  file, every `.x` under `lib/`, `tests/x/lib/` and the engine's contract
  directory, the writer and its helpers, and the engine binary, and rewrites
  the image when the key beside it differs. The header's digests catch a
  changed *engine*; the key catches changed x source, over-broadly on
  purpose — a lib edit rewrites every image, a few seconds each — because a
  suite that silently tests a stale library is worse than a slow one.
- **How small the loader prelude can actually be.** The host must sit below
  the library (measured above), so the prelude is written against bare
  primitives. Nothing says yet how many lines that is, and if it turns out to
  need much of a dialect, the floor rises and the suite case weakens.
- **When a lang's own boot loads from an image.** `x -l awk` costs 6s, all
  of it library, and the wrapper assembles the boot it would image (root
  and param forms, the dialect entry, the bundle forms, the entry) -- so the
  image is that pipe's result and the loader stands in for the entry, with
  the root, param and bundle forms re-emitted after it, since the install
  replaces the env they landed in. Undecided: who writes it (the bundle's
  `make install`, or the wrapper on a miss, paying the boot once and saying
  so), and whether `args` and `%batch?` -- the child's at write time -- are
  cells the install would overwrite with the writer's values. Probe before
  building: the suite never asked, a lang always does.
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
- **Whether the base spine's shape is stable enough to address by steps.** The
  step lists come from a contract that a gate re-derives from the headers, so
  a spine change fails the build rather than silently moving a reference — but
  an image written before such a change and loaded after it would resolve its
  steps against a different tree. The header's layout digest is what should
  refuse that, and it is already in the format.
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

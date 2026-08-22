# Conformance: the heap (profile `gc`)

Collection is a SEPARATE PROFILE, not part of `core`. An engine with no collector
still boots x-lang: only `lib/x/sys/gc.x`, `lib/x/repl/loop.x` and
`lib/x/tool/profile.x` reach this family, which is why `tools/contract/requires.x`
lists exactly those three.

The behavioural promise that goes with these instructions -- that allocation NEVER
collects, and that a live object never moves -- is a GUARANTEE, not a capability,
and is falsified by the compliance suite rather than defined here. This file
defines what the instructions DO; `tools/check/compliance.sh` checks that an engine
declaring `gc/explicit-only` is telling the truth.

### the heap can be counted, and allocating increases the count

covers: heap/count

```scheme
(def %count (%coord (lit heap) (lit count)))
(def before (%count))
(def junk (pair (pair 1 2) (pair 3 4)))
(%ok (< before (%count)))
```
---
    *** ERROR: ok

### collection preserves a reachable object

covers: heap/collect

The one property that matters. An engine free to collect what is still referenced
would fail here, and would corrupt the six library sites that hold raw pointers
across allocating expressions.

```scheme
(def %collect (%coord (lit heap) (lit collect)))
(def keep (pair 11 22))
(%collect)
(%ok (match ((= (first keep) 11) (= (rest keep) 22)) (#t ())))
```
---
    *** ERROR: ok

### collection is idempotent from the caller's view

covers: heap/collect

```scheme
(def %collect (%coord (lit heap) (lit collect)))
(def keep (pair 33 44))
(%collect)
(%collect)
(%ok (= (first keep) 33))
```
---
    *** ERROR: ok

### an object can be pinned

covers: heap/pin!

```scheme
(def %pin (%coord (lit heap) (lit pin!)))
(def %collect (%coord (lit heap) (lit collect)))
(def p (pair 55 66))
(%pin p)
(%collect)
(%ok (= (first p) 55))
```
---
    *** ERROR: ok

### the allocation ceiling is armable without a library

covers: alloc/limit!

`alloc-limit!` is bound BARE precisely so a harness can arm it before anything
loads -- every runner in this repo does, including this one. An engine that filed
it only in the catalog would leave every bare harness unable to guard itself.

```scheme
(%ok (match ((eq? alloc-limit! ()) ()) (#t 1)))
```
---
    *** ERROR: ok

## Registration is the engine's job; invocation is the library's

The three hook and root operations look like collector internals and are not.
`x_heap_mark_hook_add`'s own documentation is explicit: a registered callable is
"intended to be invoked once per garbage-collection mark phase BY THE CONSUMING
LAYER". The engine only puts it on a list, and that list is a base field the
layout contract addresses. So the contract to define is registration, and it is
observable without running a collection at all.

Each path ends at a CELL whose first is the list -- the same shape as the prims
catalog, and the same trap: one `first` too few and every lookup silently misses.

### mark-hook! prepends the callable to the base's mark-hook list

covers: heap/mark-hook!

```scheme
(def %mkhook (%coord (lit heap) (lit mark-hook!)))
(def %f (fn (_ ) 1))
(%mkhook %f)
(%ok (same? (first (first (%walk (rest (rest (%assoc (lit heap-mark-hooks) %base-paths))) (%base)))) %f))
```
---
    *** ERROR: ok

### free-hook! prepends to the free-hook list

covers: heap/free-hook!

```scheme
(def %fhook (%coord (lit heap) (lit free-hook!)))
(def %f (fn (_ ) 1))
(%fhook %f)
(%ok (same? (first (first (%walk (rest (rest (%assoc (lit heap-free-hooks) %base-paths))) (%base)))) %f))
```
---
    *** ERROR: ok

### mark-root! prepends the object to the root list

covers: heap/mark-root!

An object handed to `mark-root!` is one the collector must treat as reachable
whatever else points at it. The engine's part is recording it; whether a later
collection honours the list is the collector's behaviour, and `gc/non-moving` and
`gc/explicit-only` in the compliance suite are where that is falsified.

```scheme
(def %mkroot (%coord (lit heap) (lit mark-root!)))
(def %p (pair 1 2))
(%mkroot %p)
(%ok (same? (first (first (%walk (rest (rest (%assoc (lit heap-mark-roots) %base-paths))) (%base)))) %p))
```
---
    *** ERROR: ok

## heap mark and sweep -- deliberately not defined here

These two are not a matter of finding the right call shape, and the library says so
in its own words: `lib/x/sys/gc.x` notes that `heap-collect` runs an atomic
mark+sweep in ONE C call and "MUST be atomic: mark and sweep cannot straddle an
allocation, or the sweep frees the [objects] alive only by marking".

x-lang cannot pair them atomically, because evaluating the second form allocates.
So a conformance case calling `mark` and then `sweep` would be defining the
conditions under which the engine corrupts itself, and one calling either alone
defines nothing. `heap/collect`, which IS the atomic pairing, is defined above.

A decision, recorded next to the subject rather than left as two silent gaps --
"no case exists" and "no case should exist" look identical from the outside.

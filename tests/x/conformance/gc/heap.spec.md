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

## heap sweep, mark, and the GC hooks -- deliberately not defined here

`heap/sweep` frees everything not marked by an immediately preceding `heap/mark`,
and evaluating anything in x allocates -- so there is no correct call site for it
at this level, and a case that called it would be defining the conditions under
which the engine corrupts itself. `heap/mark` and `heap/mark-root!` are the other
half of that pair and have the same problem in isolation.

`heap/mark-hook!` and `heap/free-hook!` install callbacks that run DURING
collection, where the allocation rules invert; the library's own use of them is
covered by its spec suite, under a booted engine that can survive a mistake.

These are decisions, recorded next to the subject rather than left as four silent
gaps in a coverage report -- "no case exists" and "no case should exist" look
identical from the outside.

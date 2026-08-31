# @no-seam-collect
<!-- This file tests the collector's own mark/free hooks: a seam collect
     would fire a test-installed hook between snippets, entangling the
     harness with the mechanism under test.  Runs alone, no seam collects. -->
# @weight 1
## GC hook & root API

End-to-end coverage for the per-pass GC extensible lists in x-expr's
heap-group, driven through the x-lang surface: (Heap mark-hook!),
(Heap free-hook!), (Heap mark-root!), and the atomic (Heap collect).

(Heap collect) runs mark+sweep in one C call with no allocation between
the phases, so it is safe to invoke mid-expression -- including from
within the spec runner's per-test (begin …) wrapping.  A registered
fn-hook is fired through the TCO trampoline so a value-returning hook
body doesn't leave a half-finished call for the sweep to free.

Installing hooks via the class is fine (cold path), but code that runs
MID-COLLECT must not class-dispatch (dispatch allocates; the mark phase
must not): such callables are fetched raw from the catalog instead.

### a no-op mark-hook survives a full collect

```scheme
(Heap mark-hook! (fn (_ ) ()))
(Heap collect)
#t
```
---
    #t

### a value-returning mark-hook survives a full collect

A hook whose body returns a non-nil tail used to leave the env extended
and the call deferred; the collect then freed the in-flight frame.

```scheme
(Heap mark-hook! (fn (_ ) 42))
(Heap collect)
#t
```
---
    #t

### an allocating mark-hook survives a full collect

```scheme
(Heap mark-hook! (fn (_ ) (list 1 2 3)))
(Heap collect)
#t
```
---
    #t

### a C-primitive callable works as a mark-hook

The hook runs mid-collect, so it is the raw catalog prim, not a class
dispatch.

```scheme
(Heap mark-hook! (prim-ref 'heap 'count))
(Heap collect)
#t
```
---
    #t

### a no-op free-hook survives a full collect

```scheme
(Heap free-hook! (fn (_ ) ()))
(Heap collect)
#t
```
---
    #t

### mark-root! keeps its object reachable across a collect

The pair is reachable from the global `kept`, but registering it as a
root additionally exercises the root-mark pass; after collect its data
is intact.

```scheme
(def kept (pair 'alive ()))
(Heap mark-root! kept)
(Heap collect)
(eq? (first kept) 'alive)
```
---
    #t

### a mark-hook may register a root mid-collect

The hook registers a root during the mark phase, so it calls the raw
catalog prim (no allocation mid-collect); the freshly registered root
is honoured and the object survives.

```scheme
(def guarded (pair 'safe ()))
(def %mark-root (prim-ref 'heap 'mark-root!))
(Heap mark-hook! (fn (_ ) (%mark-root guarded) ()))
(Heap collect)
(eq? (first guarded) 'safe)
```
---
    #t

### all three registration surfaces compose

```scheme
(Heap mark-hook! (fn (_ ) ()))
(Heap free-hook! (fn (_ ) ()))
(def survivor (pair 'kept ()))
(Heap mark-root! survivor)
(Heap collect)
(eq? (first survivor) 'kept)
```
---
    #t

## heap pin!

### pin! returns the object it marks

```scheme
(def pinned (pair 'held ()))
(eq? ((prim-ref 'heap 'pin!) pinned) pinned)
```
---
    #t

### a pinned object's data is intact after a collect

Like the `mark-root!` case above, the pair is also reachable from the
global, so this exercises the SYSTEM-flag traversal rather than proving
survival of an otherwise-unreachable object; the flag makes it immune to
the sweep and its contents are unchanged afterwards.

```scheme
(def held (pair 'safe ()))
((prim-ref 'heap 'pin!) held)
(Heap collect)
(eq? (first held) 'safe)
```
---
    #t

### pin! marks recursively: nested data survives too

```scheme
(def deep (pair 'outer (pair 'inner ())))
((prim-ref 'heap 'pin!) deep)
(Heap collect)
(eq? (first (rest deep)) 'inner)
```
---
    #t

## heap sweep -- covered in C, not from x

`heap-sweep` is registered and reachable, and there is no spec for it on
purpose. Its own header calls it LOW-LEVEL / UNSAFE on its own: a sweep frees
every object not marked by an *immediately* preceding mark, "with no
intervening allocation". Evaluating anything in x-lang allocates, so a
correct x-level call site cannot be written -- the eval-list cell the
evaluator is mid-traversal on would be freed underneath it. `(Heap collect)`
is the safe atomic mark+sweep and is specced above. The phases are exercised
separately in the engine's tests/c/src/6.6.x-prim-io.spec.c, where that window
exists.

## heap mark

### mark returns nil (side-effect contract)

```scheme
(null? ((prim-ref 'heap 'mark)))
```
---
    #t

### marking alone frees nothing

A mark sets flags and reclaims no memory; it is only half a collection.
The pair is intact afterwards because nothing swept.

```scheme
(def survives (pair 'still ()))
((prim-ref 'heap 'mark))
(eq? (first survives) 'still)
```
---
    #t

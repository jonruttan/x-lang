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

```x
(Heap mark-hook! (fn (_ ) ()))
(Heap collect)
#t
```
---
    #t

### a value-returning mark-hook survives a full collect

A hook whose body returns a non-nil tail used to leave the env extended
and the call deferred; the collect then freed the in-flight frame.

```x
(Heap mark-hook! (fn (_ ) 42))
(Heap collect)
#t
```
---
    #t

### an allocating mark-hook survives a full collect

```x
(Heap mark-hook! (fn (_ ) (list 1 2 3)))
(Heap collect)
#t
```
---
    #t

### a C-primitive callable works as a mark-hook

The hook runs mid-collect, so it is the raw catalog prim, not a class
dispatch.

```x
(Heap mark-hook! (prim-ref 'heap 'count))
(Heap collect)
#t
```
---
    #t

### a no-op free-hook survives a full collect

```x
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

```x
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

```x
(def guarded (pair 'safe ()))
(def %mark-root (prim-ref 'heap 'mark-root!))
(Heap mark-hook! (fn (_ ) (%mark-root guarded) ()))
(Heap collect)
(eq? (first guarded) 'safe)
```
---
    #t

### all three registration surfaces compose

```x
(Heap mark-hook! (fn (_ ) ()))
(Heap free-hook! (fn (_ ) ()))
(def survivor (pair 'kept ()))
(Heap mark-root! survivor)
(Heap collect)
(eq? (first survivor) 'kept)
```
---
    #t

## heap tree-mark! / chain-clear!

`pin!` above sets one particular flag, `SHARED`, which is permanent. These two
take the flag as an argument, so a caller can borrow the collector's traversal
to ask *what is reachable from here* and then take the answer back.

Which bit is the caller's to pick, and it must be one the collector does not
own. `SHARED` is already set on base-tree nodes and the flag doubles as the
traversal's visited test, so marking with it halts at the first one; a leftover
`MARK` makes the next collect's mark phase stop short and free what it missed.
`0x400` is above both and is what these tests use.

### tree-mark! returns the object it marks

```x
(def subject (pair 'held ()))
(eq? ((prim-ref 'heap 'tree-mark!) subject 1024) subject)
```
---
    #t

### the flag goes on, and comes off again

An object reachable from the base carries the bit after a mark from the base,
and does not after the clear. The assertion is the transition, not a count:
how many objects a heap holds is not a property worth pinning in a spec.

```x
(do
  (def set? (fn (_ o) (if (eq? (& (%reflect-flags o) 1024) 0) #f #t)))
  (def subject (pair 'reachable ()))
  (def before (set? subject))
  ((prim-ref 'heap 'tree-mark!) (%base) 1024)
  (def during (set? subject))
  ((prim-ref 'heap 'chain-clear!) 1024)
  (list before during (set? subject)))
```
---
    (#f #t #f)

### chain-clear! reaches what a tree walk would not

The clear walks the allocation chain, so it takes the flag off an object that
became unreachable after the mark -- which a traversal from a root could no
longer find.

```x
(do
  (def orphan (pair 'gone ()))
  ((prim-ref 'heap 'tree-mark!) orphan 1024)
  (def marked (if (eq? (& (%reflect-flags orphan) 1024) 0) #f #t))
  ((prim-ref 'heap 'chain-clear!) 1024)
  (list marked (if (eq? (& (%reflect-flags orphan) 1024) 0) #f #t)))
```
---
    (#t #f)

## heap pin!

### pin! returns the object it marks

```x
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

```x
(def held (pair 'safe ()))
((prim-ref 'heap 'pin!) held)
(Heap collect)
(eq? (first held) 'safe)
```
---
    #t

### pin! marks recursively: nested data survives too

```x
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

```x
(null? ((prim-ref 'heap 'mark)))
```
---
    #t

### marking alone frees nothing

A mark sets flags and reclaims no memory; it is only half a collection.
The pair is intact afterwards because nothing swept.

```x
(def survives (pair 'still ()))
((prim-ref 'heap 'mark))
(eq? (first survives) 'still)
```
---
    #t

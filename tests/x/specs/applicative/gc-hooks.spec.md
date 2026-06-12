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
(Heap mark-hook! (prim-ref (lit heap) (lit count)))
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
(def kept (pair (lit alive) ()))
(Heap mark-root! kept)
(Heap collect)
(eq? (first kept) (lit alive))
```
---
    #t

### a mark-hook may register a root mid-collect

The hook registers a root during the mark phase, so it calls the raw
catalog prim (no allocation mid-collect); the freshly registered root
is honored and the object survives.

```scheme
(def guarded (pair (lit safe) ()))
(def %mark-root (prim-ref (lit heap) (lit mark-root!)))
(Heap mark-hook! (fn (_ ) (%mark-root guarded) ()))
(Heap collect)
(eq? (first guarded) (lit safe))
```
---
    #t

### all three registration surfaces compose

```scheme
(Heap mark-hook! (fn (_ ) ()))
(Heap free-hook! (fn (_ ) ()))
(def survivor (pair (lit kept) ()))
(Heap mark-root! survivor)
(Heap collect)
(eq? (first survivor) (lit kept))
```
---
    #t

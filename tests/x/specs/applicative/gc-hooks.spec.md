## GC hook & root API

End-to-end coverage for the per-pass GC extensible lists in x-expr's
heap-group, driven through the x-lang surface: heap-mark-hook!,
heap-free-hook!, heap-mark-root!, and the atomic (heap-collect).

(heap-collect) runs mark+sweep in one C call with no allocation between
the phases, so it is safe to invoke mid-expression -- including from
within the spec runner's per-test (begin …) wrapping.  A registered
fn-hook is fired through the TCO trampoline so a value-returning hook
body doesn't leave a half-finished call for the sweep to free.

### a no-op mark-hook survives a full collect

```scheme
(heap-mark-hook! (fn (_ ) ()))
(heap-collect)
#t
```
---
    #t

### a value-returning mark-hook survives a full collect

A hook whose body returns a non-nil tail used to leave the env extended
and the call deferred; the collect then freed the in-flight frame.

```scheme
(heap-mark-hook! (fn (_ ) 42))
(heap-collect)
#t
```
---
    #t

### an allocating mark-hook survives a full collect

```scheme
(heap-mark-hook! (fn (_ ) (list 1 2 3)))
(heap-collect)
#t
```
---
    #t

### a C-primitive callable works as a mark-hook

```scheme
(heap-mark-hook! heap-count)
(heap-collect)
#t
```
---
    #t

### a no-op free-hook survives a full collect

```scheme
(heap-free-hook! (fn (_ ) ()))
(heap-collect)
#t
```
---
    #t

### heap-mark-root! keeps its object reachable across a collect

The pair is reachable from the global `kept`, but registering it as a
root additionally exercises the root-mark pass; after collect its data
is intact.

```scheme
(def kept (pair (lit alive) ()))
(heap-mark-root! kept)
(heap-collect)
(eq? (first kept) (lit alive))
```
---
    #t

### a mark-hook may register a root mid-collect

The hook calls heap-mark-root! during the mark phase; the freshly
registered root is honored and the object survives.

```scheme
(def guarded (pair (lit safe) ()))
(heap-mark-hook! (fn (_ ) (heap-mark-root! guarded) ()))
(heap-collect)
(eq? (first guarded) (lit safe))
```
---
    #t

### all three registration surfaces compose

```scheme
(heap-mark-hook! (fn (_ ) ()))
(heap-free-hook! (fn (_ ) ()))
(def survivor (pair (lit kept) ()))
(heap-mark-root! survivor)
(heap-collect)
(eq? (first survivor) (lit kept))
```
---
    #t

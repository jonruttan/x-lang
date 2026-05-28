## GC hook & root API

Exercises the registration surface for x-expr's per-pass extensible
GC lists -- heap-mark-hook!, heap-free-hook!, heap-mark-root! -- and
verifies that a subsequent `(heap-mark)` traverses the registered hook
and root lists without crashing.

These tests deliberately invoke `(heap-mark)` only, never
`(heap-sweep)` and never `(heap-collect)`/`(heap-collect-force)`.
There is a separate bug (tracked in the project tasks) where any
manual sweep call inside a `(begin …)` form -- including the spec
runner's per-test wrapping -- frees transient body pairs that are
still on the eval stack, segfaulting the next step.  Once that's
fixed these tests should be extended with sweep-side assertions
(root keep-alive across collection, free-hook fires before reclaim).

### heap-mark-hook! accepts a no-op hook

```scheme
(heap-mark-hook! (fn (_ ) ()))
(heap-mark)
#t
```
---
    #t

### heap-mark-hook! accepts a C-primitive callable

`heap-count` is a bare C primitive, not a fn closure -- different
dispatch path; both should work.

```scheme
(heap-mark-hook! heap-count)
(heap-mark)
#t
```
---
    #t

### multiple mark-hooks chain rather than overwrite

After registering a C-primitive hook followed by a no-op fn, a mark
pass walks both without crashing.  Pre-fix, the second registration
would replace the first's stack-cell slot and the walker would extract
the most-recently-registered hook as the entire list head -- crashing
on its first non-pair internal field.

```scheme
(heap-mark-hook! heap-count)
(heap-mark-hook! (fn (_ ) ()))
(heap-mark)
#t
```
---
    #t

### heap-free-hook! accepts a no-op hook

Free hooks fire during sweep, which the spec runner's `(begin …)`
wrapping makes unsafe to invoke here.  This test only confirms
registration doesn't error and a subsequent mark survives.

```scheme
(heap-free-hook! (fn (_ ) ()))
(heap-mark)
#t
```
---
    #t

### heap-mark-root! accepts an arbitrary object

```scheme
(def my-pair (pair (lit alive) ()))
(heap-mark-root! my-pair)
(heap-mark)
#t
```
---
    #t

### all three registration surfaces are independent slots

Each list lives at a distinct field in heap-group; registering into
one shouldn't disturb the others.

```scheme
(heap-mark-hook! (fn (_ ) ()))
(heap-free-hook! (fn (_ ) ()))
(def survivor (pair (lit kept) ()))
(heap-mark-root! survivor)
(heap-mark)
(eq? (first survivor) (lit kept))
```
---
    #t

## GC stress

Exercises mark+sweep over non-trivial heaps via the atomic `(Heap collect)`
(ns `heap` is de-registered: the class -- or a catalog fetch -- is the only
surface; the bare `heap-collect` name no longer exists).

List sizes are kept at/below 1000: larger non-tail recursion (e.g.
`(List range 1 5001)`) overflows the C stack independently of GC -- tracked
separately -- so using it here would test recursion depth, not the
collector.

### GC during map over large list

```scheme
(def result (map (fn (_ x) (* x x)) (List range 1 1001)))
(Heap collect)
(= (length result) 1000)
```
---
    #t

### GC after abandoned large list

```scheme
(do (def waste (fn (self n acc) (if (= n 0) acc (self (- n 1) (pair n acc))))) (waste 1000 ()))
(def before (Heap count))
(Heap collect)
(< (Heap count) before)
```
---
    #t

### shared structure survives GC

```scheme
(def shared (list 1 2 3 4 5))
(def a (pair 'ref-a shared))
(def b (pair 'ref-b shared))
(Heap collect)
(and (= (length (rest a)) 5) (= (length (rest b)) 5))
```
---
    #t

### closure-captured data survives GC

```scheme
(def make-counter (fn (_ start) (def n start) (fn (_ ) (do (set! n (+ n 1)) n))))
(def c (make-counter 100))
(do (def waste (fn (self n) (if (= n 0) () (do (list 1 2 3) (self (- n 1)))))) (waste 2000))
(Heap collect)
(= (c) 101)
```
---
    #t

### repeated GC cycles stay stable

Iteration count is kept modest: the spec runner evaluates each test via
`(eval %r %E)`, which does not engage TCO, so a tail-recursive loop here
accumulates frames and each in-loop collect walks a growing eval-list
(O(n^2)).  20 cycles is plenty to show stability; 100 collects via the
harness take ~90s (tracked separately).  Standalone the same loop at 100
runs in well under a second.

```scheme
(def live-data (List range 1 101))
(do (def gc-loop (fn (self n) (if (= n 0) () (do (list 1 2 3) (Heap collect) (self (- n 1)))))) (gc-loop 20))
(= (length live-data) 100)
```
---
    #t

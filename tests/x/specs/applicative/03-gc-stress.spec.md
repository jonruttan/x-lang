## GC stress

### GC during map over large list

```scheme
(include "lib/x/profile.x")
(def result (map (fn (_ x) (* x x)) (range 1 5001)))
(heap-collect-force)
(= (length result) 5000)
```
---
    #t

### GC after abandoned large list

```scheme
(include "lib/x/profile.x")
(do (def waste (fn (self n acc) (if (= n 0) acc (self (- n 1) (pair n acc))))) (waste 5000 ()))
(def before (heap-count))
(heap-collect-force)
(< (heap-count) before)
```
---
    #t

### shared structure survives GC

```scheme
(include "lib/x/profile.x")
(def shared (list 1 2 3 4 5))
(def a (pair (lit ref-a) shared))
(def b (pair (lit ref-b) shared))
(heap-collect-force)
(and (= (length (rest a)) 5) (= (length (rest b)) 5))
```
---
    #t

### closure-captured data survives GC

```scheme
(include "lib/x/profile.x")
(def make-counter (fn (_ start) (def n start) (fn (_ ) (do (set! n (+ n 1)) n))))
(def c (make-counter 100))
(do (def waste (fn (self n) (if (= n 0) () (do (list 1 2 3) (self (- n 1)))))) (waste 2000))
(heap-collect-force)
(= (c) 101)
```
---
    #t

### repeated GC cycles stay stable

```scheme
(include "lib/x/profile.x")
(def live-data (range 1 101))
(do (def gc-loop (fn (self n) (if (= n 0) () (do (list 1 2 3) (heap-collect-force) (self (- n 1)))))) (gc-loop 100))
(= (length live-data) 100)
```
---
    #t

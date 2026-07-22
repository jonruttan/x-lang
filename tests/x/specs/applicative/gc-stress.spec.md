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
(def result (List map (fn (_ x) (* x x)) (List range 1 1001)))
(Heap collect)
(= (List length result) 1000)
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
(and (= (List length (rest a)) 5) (= (List length (rest b)) 5))
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
(= (List length live-data) 100)
```
---
    #t

## vector payloads survive collection (the Dict-across-a-REPL-turn segfault)

### dict buckets, vector slots, and array stores are traced

Vectors are per-instance sized; the dynamic-units sentinel (type units
= -1, count in slot 0) makes the mark hook walk their payloads. Before
it, a collect freed Dict buckets under the instance and the next get
segfaulted -- jon hit it live because the REPL collects every turn.

```scheme
(do (import x/type/dict) (import x/type/array)
  (def d (Dict from-plist (list 'a 1 'b 2)))
  (def v (Vector of (list 1 2) (list 3 4)))
  (def arr (Array from-list (list (list 9 9))))
  ((prim-ref 'heap 'collect))
  (list (d get 'b) (Vector ref 1 v) (arr ->list)))
```
---
    (2 (3 4) ((9 9)))

## every heap type survives collection (the GC-payload audit)

The mark hook traces a typed object by per-type units, a C mark
callback, or (for pair-layout customs) recursion. Any custom type that
stores heap payloads but declares neither had UNTRACED slots -- freed
under the live instance, segfault on next access. This audit swept
every C type struct and every make-obj/make-instance consumer; the
three gaps (VECTOR, ASM, ITER) are fixed, the rest verified.

### Gen driving a C iterator survives (ITER units fix)

```scheme
(do (import x/type/gen)
  (def g (Gen from-seq (Vector of 10 20 30)))
  (def it (Iter new (Vector of 1 2 3)))
  ((prim-ref 'heap 'collect))
  ((prim-ref 'heap 'collect))
  (list (g ->list) (first ((prim-ref 'iter 'step) it))))
```
---
    ((10 20 30) 1)

### the full type zoo survives two collects

```scheme
(do (import x/type/dict) (import x/type/set) (import x/type/array)
    (import x/type/regex) (import x/type/promise)
  (def d (Dict from-plist (list 'k (list 1 2 3))))
  (def st (Set from-list (list "x" "y")))
  (def arr (Array of (list 5) (list 6)))
  (def rx (Regex compile "([a-z]+)-([0-9]+)"))
  (def p (delay (+ 40 2)))
  (def bigvec (Vector make 40 (list 'deep)))
  ((prim-ref 'heap 'collect))
  ((prim-ref 'heap 'collect))
  (list (d get 'k) (st has? "y") (arr ->list)
        (Assoc get 1 (Regex match-groups "ab-12" rx))
        (Promise force p) (Vector ref 39 bigvec)))
```
---
    ((1 2 3) #t ((5) (6)) "ab" 42 ('deep))

## retagged singletons survive collection (#101)

The mark hook walks typed objects by their type's declared units, and
build_struct DEFAULTS x-made types to pair units -- over a 1-slot static
satom that walk read the "#t" text pointer as a child object (ASan:
global-buffer-overflow past the "#f" string global, in x_heap_tree_mark).
BOOL declares units 0: its instances trace nothing. This pins the boot
claim across back-to-back collections on the REPL's own sweep path.

### collect twice, then every boolean behavior

```scheme
(do
  (Heap collect)
  (Heap collect)
  (list (Type name (Type of #t)) (if #t 1 2) (if #f 1 2)
        (guard (e (lit R)) (+ #t 1)) (eq? #t #t) (boolean? #f)))
```
---
    ("BOOL" 1 2 'R #t #t)

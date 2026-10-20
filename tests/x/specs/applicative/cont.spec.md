# @no-seam-collect
<!-- Each case collects where only a waiting continuation holds the objects
     under test; a seam collect between cases would add a collect the case
     did not place. -->
# @weight 1
## Cont: a continuation the collector can see into

Two continuations hand control back and forth the way a generator and its
caller do.  The body suspends halfway through building a list, its first
element evaluated and held by nothing but the frame building it; the caller
collects, allocates, and takes the body up again.  With the engine's bare
`call/cc` the resumed frame reads freed memory (x-lang#283); through
`(Cont capture f)` the marker beside the continuation marks what the
captured frames hold.

### an object a suspended frame holds survives a collect

```x
(import x/sys/cont)
(do
  (def %ct-kgen ())
  (def %ct-kcall ())
  (def %ct-out ())
  (def %ct-yield
    (fn (_ v) (Cont capture (fn (_ k) (do (set! %ct-kgen k) (%ct-kcall v))))))
  (def %ct-body
    (fn (_)
      (do (set! %ct-out (list (Str8 append "x" "y") (%ct-yield 1) (Str8 append "p" "q") (%ct-yield 2)))
          (%ct-kcall (lit done)))))
  (def %ct-resume
    (fn (_ v)
      (Cont capture
        (fn (_ k) (do (set! %ct-kcall k) (if (null? %ct-kgen) (%ct-body) (%ct-kgen v)))))))
  (def %ct-fill
    (fn (self i) (if (= i 0) () (do (Str8 append "garbage-" "fill") (self (- i 1))))))
  (def %ct-r1 (%ct-resume 0))
  (Heap collect)
  (%ct-fill 5000)
  (def %ct-r2 (%ct-resume 10))
  (Heap collect)
  (%ct-fill 5000)
  (def %ct-r3 (%ct-resume 20))
  (write (list %ct-r1 %ct-r2 %ct-r3 %ct-out)))
```
---
    (1 2 'done ("xy" 10 "pq" 20))

### many waiting continuations, a collect among them

```x
(import x/sys/cont)
(do
  (def %cm-ks ())
  (def %cm-n (pair 0 ()))
  (def %cm-capture
    (fn (self i acc)
      (if (= i 0) acc
        (self (- i 1)
          (Cont capture
            (fn (_ k)
              (do (set! %cm-ks (pair k %cm-ks))
                  (pair (Str8 append "v" (Str8 append "-" "x")) acc))))))))
  (def %cm-vals (%cm-capture 8 ()))
  (Heap collect)
  (%set-first! %cm-n (+ (first %cm-n) 1))
  (if (< (first %cm-n) 3)
    ((first %cm-ks) (pair "again" %cm-vals))
    ())
  (write (list (first %cm-n) (List length %cm-vals) (first (rest %cm-vals)))))
```
---
    (3 10 "again")

### the continuation answers its value and can be taken up again

```x
(import x/sys/cont)
(do
  (def %cv-k ())
  (def %cv-n (pair 0 ()))
  (def %cv-v (Cont capture (fn (_ k) (do (set! %cv-k k) 0))))
  (%set-first! %cv-n (+ (first %cv-n) 1))
  (Heap collect)
  (if (< (first %cv-n) 4) (%cv-k (+ %cv-v 10)) ())
  (write (list %cv-v (first %cv-n))))
```
---
    (30 4)

### a continuation that escapes is a plain return

```x
(import x/sys/cont)
(Cont capture (fn (_ k) (do (k 7) (error "not reached"))))
```
---
    7

## cov: FFI primitives

### convert obj to ptr returns a non-nil value

```scheme
(display (not (null? (Convert to (pair 1 2) %ptr))))
```
---
    #t

### convert integer to ptr returns a non-nil value

```scheme
(display (not (null? (Convert to 42 %ptr))))
```
---
    #t

### ptr-ref-word reads flags field

```scheme
(do
  (def word-size
    (if (> (Convert to (Convert to 4294967296 %ptr) %int) 0) 8 4))
  (def %flags-offset (* 2 word-size))
  (def %p (pair 1 2))
  (display (number? (Ptr ref-word (Convert to %p %ptr) %flags-offset))))
```
---
    #t

### ptr-set-word! can set and read flags

```scheme
(do
  (def word-size
    (if (> (Convert to (Convert to 4294967296 %ptr) %int) 0) 8 4))
  (def %flags-offset (* 2 word-size))
  (def %p (pair 1 2))
  (Ptr set-word! (Convert to %p %ptr) %flags-offset
    (| (Ptr ref-word (Convert to %p %ptr) %flags-offset) 2))
  (display (> (& (Ptr ref-word (Convert to %p %ptr) %flags-offset) 2) 0)))
```
---
    #t

## cov: coverage marking

### eval marks pair with coverage flag

```scheme
(do
  (def word-size
    (if (> (Convert to (Convert to 4294967296 %ptr) %int) 0) 8 4))
  (def %flags-offset (* 2 word-size))
  (def obj-flags (fn (_ obj)
    (Ptr ref-word (Convert to obj %ptr) %flags-offset)))
  (def %tokens (Tok read-str (%base) "(+ 1 2)\n"))
  (def %form (first %tokens))
  (eval %form)
  (display (> (& (obj-flags %form) 2) 0)))
```
---
    #t

### direct if marks then branch

```scheme
(do
  (def word-size
    (if (> (Convert to (Convert to 4294967296 %ptr) %int) 0) 8 4))
  (def %flags-offset (* 2 word-size))
  (def obj-flags (fn (_ obj)
    (Ptr ref-word (Convert to obj %ptr) %flags-offset)))
  (def %tokens (Tok read-str (%base) "(if #t (+ 1 1) (+ 2 2))\n"))
  (def %form (first %tokens))
  (def %then (first (rest (rest %form))))
  (def %else (first (rest (rest (rest %form)))))
  (eval %form)
  (display (> (& (obj-flags %then) 2) 0))
  (display " ")
  (display (= (& (obj-flags %else) 2) 0)))
```
---
    #t #t


### atom branches mark and read correctly

```scheme
(do
  (def word-size
    (if (> (Convert to (Convert to 4294967296 %ptr) %int) 0) 8 4))
  (def %flags-offset (* 2 word-size))
  ; %obj->ptr, not the convert catalog: an atom's int->ptr conversion is
  ; a value cast -- the historical crash this spec pins (#231 chip).
  (def obj-flags (fn (_ obj)
    (Ptr ref-word (%obj->ptr obj) %flags-offset)))
  (def %tokens (Tok read-str (%base) "(if #t 1 2)\n"))
  (def %form (first %tokens))
  (def %then (first (rest (rest %form))))
  (def %else (first (rest (rest (rest %form)))))
  (eval %form)
  (display (> (& (obj-flags %then) 2) 0))
  (display " ")
  (display (= (& (obj-flags %else) 2) 0)))
```
---
    #t #t

### untaken if-else branch is unmarked

```scheme
(do
  (def word-size
    (if (> (Convert to (Convert to 4294967296 %ptr) %int) 0) 8 4))
  (def %flags-offset (* 2 word-size))
  (def obj-flags (fn (_ obj)
    (Ptr ref-word (Convert to obj %ptr) %flags-offset)))
  (def %tokens (Tok read-str (%base) "(if #t (+ 1 1) (+ 2 2))\n"))
  (def %form (first %tokens))
  (def %else (first (rest (rest (rest %form)))))
  (eval %form)
  (display (= (& (obj-flags %else) 2) 0)))
```
---
    #t

### closure if marks both branches when both taken

```scheme
(do
  (def word-size
    (if (> (Convert to (Convert to 4294967296 %ptr) %int) 0) 8 4))
  (def %flags-offset (* 2 word-size))
  (def obj-flags (fn (_ obj)
    (Ptr ref-word (Convert to obj %ptr) %flags-offset)))
  (def %marked? (fn (_ obj)
    (if (null? obj) #t
      (> (& (obj-flags obj) 2) 0))))
  (def %tokens (Tok read-str (%base)
    "(def f (fn (_ x) (if (< x 0) (- 0 x) (+ x 1))))\n(f -3)\n(f 5)\n"))
  (def %def-form (first %tokens))
  (def %fn-form (first (rest (rest %def-form))))
  (def %if-form (first (rest (rest %fn-form))))
  (def %then (first (rest (rest %if-form))))
  (def %else (first (rest (rest (rest %if-form)))))
  ; Eval using operative loop (defs persist)
  (def %forms %tokens)
  (def %loop ())
  (set! %loop (op () %e
    (if (not (null? %forms))
      (do (guard (err ()) (eval! (first %forms)))
          (set! %forms (rest %forms))
          (%loop)))))
  (%loop)
  (display (%marked? %then))
  (display " ")
  (display (%marked? %else)))
```
---
    #t #t

### closure if leaves untaken branch unmarked

```scheme
(do
  (def word-size
    (if (> (Convert to (Convert to 4294967296 %ptr) %int) 0) 8 4))
  (def %flags-offset (* 2 word-size))
  (def obj-flags (fn (_ obj)
    (Ptr ref-word (Convert to obj %ptr) %flags-offset)))
  (def %tokens (Tok read-str (%base)
    "(def f (fn (_ x) (if (< x 0) (- 0 x) (+ x 1))))\n(f 5)\n"))
  (def %def-form (first %tokens))
  (def %fn-form (first (rest (rest %def-form))))
  (def %if-form (first (rest (rest %fn-form))))
  (def %then (first (rest (rest %if-form))))
  (def %forms %tokens)
  (def %loop ())
  (set! %loop (op () %e
    (if (not (null? %forms))
      (do (guard (err ()) (eval! (first %forms)))
          (set! %forms (rest %forms))
          (%loop)))))
  (%loop)
  (display (= (& (obj-flags %then) 2) 0)))
```
---
    #t

### flag survives GC

```scheme
(do
  (def word-size
    (if (> (Convert to (Convert to 4294967296 %ptr) %int) 0) 8 4))
  (def %flags-offset (* 2 word-size))
  (def obj-flags (fn (_ obj)
    (Ptr ref-word (Convert to obj %ptr) %flags-offset)))
  (def %p (pair 1 2))
  (Ptr set-word! (Convert to %p %ptr) %flags-offset
    (| (obj-flags %p) 2))
  ; Force some allocations to trigger GC
  (def %junk (%map (fn (_ x) (pair x x)) (list 1 2 3 4 5 6 7 8 9 10)))
  (display (> (& (obj-flags %p) 2) 0)))
```
---
    #t

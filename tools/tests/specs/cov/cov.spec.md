## cov: FFI primitives

### convert obj to ptr returns a non-nil value

```x
(display (not (null? (Convert to (pair 1 2) (Type named POINTER)))))
```
---
    #t

### convert integer to ptr returns a non-nil value

```x
(display (not (null? (Convert to 42 (Type named POINTER)))))
```
---
    #t

### ptr-ref-word reads flags field

```x
(do
  (def word-size
    (if (> (Convert to (Convert to 4294967296 (Type named POINTER)) (Type named INTEGER)) 0) 8 4))
  (def %flags-offset (* 2 word-size))
  (def %p (pair 1 2))
  (display (number? (Ptr ref-word (Convert to %p (Type named POINTER)) %flags-offset))))
```
---
    #t

### ptr-set-word! can set and read flags

```x
(do
  (def word-size
    (if (> (Convert to (Convert to 4294967296 (Type named POINTER)) (Type named INTEGER)) 0) 8 4))
  (def %flags-offset (* 2 word-size))
  (def %p (pair 1 2))
  (Ptr set-word! (Convert to %p (Type named POINTER)) %flags-offset
    (| (Ptr ref-word (Convert to %p (Type named POINTER)) %flags-offset) 2))
  (display (> (& (Ptr ref-word (Convert to %p (Type named POINTER)) %flags-offset) 2) 0)))
```
---
    #t

## cov: coverage marking

### eval marks pair with coverage flag

```x
(do
  (def word-size
    (if (> (Convert to (Convert to 4294967296 (Type named POINTER)) (Type named INTEGER)) 0) 8 4))
  (def %flags-offset (* 2 word-size))
  (def obj-flags (fn (_ obj)
    (Ptr ref-word (Convert to obj (Type named POINTER)) %flags-offset)))
  (def %tokens (Tok read-str (%base) "(+ 1 2)\n"))
  (def %form (first %tokens))
  (eval %form)
  (display (> (& (obj-flags %form) 2) 0)))
```
---
    #t

### direct if marks then branch

```x
(do
  (def word-size
    (if (> (Convert to (Convert to 4294967296 (Type named POINTER)) (Type named INTEGER)) 0) 8 4))
  (def %flags-offset (* 2 word-size))
  (def obj-flags (fn (_ obj)
    (Ptr ref-word (Convert to obj (Type named POINTER)) %flags-offset)))
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

```x
(do
  (def word-size
    (if (> (Convert to (Convert to 4294967296 (Type named POINTER)) (Type named INTEGER)) 0) 8 4))
  (def %flags-offset (* 2 word-size))
  ; %obj->ptr, not the convert catalogue: an atom's int->ptr conversion is
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

```x
(do
  (def word-size
    (if (> (Convert to (Convert to 4294967296 (Type named POINTER)) (Type named INTEGER)) 0) 8 4))
  (def %flags-offset (* 2 word-size))
  (def obj-flags (fn (_ obj)
    (Ptr ref-word (Convert to obj (Type named POINTER)) %flags-offset)))
  (def %tokens (Tok read-str (%base) "(if #t (+ 1 1) (+ 2 2))\n"))
  (def %form (first %tokens))
  (def %else (first (rest (rest (rest %form)))))
  (eval %form)
  (display (= (& (obj-flags %else) 2) 0)))
```
---
    #t

### closure if marks both branches when both taken

```x
(do
  (def word-size
    (if (> (Convert to (Convert to 4294967296 (Type named POINTER)) (Type named INTEGER)) 0) 8 4))
  (def %flags-offset (* 2 word-size))
  (def obj-flags (fn (_ obj)
    (Ptr ref-word (Convert to obj (Type named POINTER)) %flags-offset)))
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

```x
(do
  (def word-size
    (if (> (Convert to (Convert to 4294967296 (Type named POINTER)) (Type named INTEGER)) 0) 8 4))
  (def %flags-offset (* 2 word-size))
  (def obj-flags (fn (_ obj)
    (Ptr ref-word (Convert to obj (Type named POINTER)) %flags-offset)))
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

```x
(do
  (def word-size
    (if (> (Convert to (Convert to 4294967296 (Type named POINTER)) (Type named INTEGER)) 0) 8 4))
  (def %flags-offset (* 2 word-size))
  (def obj-flags (fn (_ obj)
    (Ptr ref-word (Convert to obj (Type named POINTER)) %flags-offset)))
  (def %p (pair 1 2))
  (Ptr set-word! (Convert to %p (Type named POINTER)) %flags-offset
    (| (obj-flags %p) 2))
  ; Force some allocations to trigger GC
  (def %junk (%map (fn (_ x) (pair x x)) (list 1 2 3 4 5 6 7 8 9 10)))
  (display (> (& (obj-flags %p) 2) 0)))
```
---
    #t

## cov: library report pipeline (#402)

The blocks above prove the C flag mechanics; these prove the x/tool/cov
LIBRARY against real fn objects. The tool rotted to 0/0 invisibly when
the type-label model changed (fn bodies are C-built spines whose type name
is nil) because nothing exercised this layer.

### cov-count-tree walks a C-built fn body spine

```x
(do
  (import x/tool/cov cov-count-tree)
  (def f (fn (_ x) (+ x 1)))
  (def spine ((prim-ref (lit obj) (lit ref)) f 1))
  (display (> (first (rest (cov-count-tree (first (rest spine)) 0))) 0)))
```
---
    #t

### cov-check-fn reports a called fn as covered

```x
(do
  (import x/tool/cov cov-check-fn)
  (def f (fn (_ x) (+ x 1)))
  (f 1)
  (def r (cov-check-fn (lit f) f #f))
  (display (list (first r)
                 (> (first (rest (rest r))) 0)
                 (> (first (rest r)) 0))))
```
---
    (f #t #t)

### cov-check-class reports a class's own methods (#408)

```x
(do
  (import x/tool/cov cov-check-class)
  (def-class CovProbe ()
    (static
      (method touched (self x) (+ x 1))
      (method untouched (self x) (- x 1))))
  (CovProbe touched 1)
  (def rows (cov-check-class (lit CovProbe) CovProbe #f))
  (display (list (%length rows)
                 (> (first (rest (rest (first rows)))) 0))))
```
---
    (2 #t)

## cov: branch coverage

`cov-branches` walks forms that have run and counts the branches the
construct declarations name, by the marks x-bin-profile leaves.

### an if counts its then and its else

```x
(do
  (import x/tool/cov cov-branches)
  (def %forms (Tok read-str (%base) "(if #t (+ 1 1) (+ 2 2))\n"))
  (eval (first %forms))
  (def r (cov-branches %forms (lit ((if (branch . cond))))))
  (write (list (first r) (first (rest r)))))
```
---
    (1 2)

### the untaken branch is listed with its label

```x
(do
  (import x/tool/cov cov-branches)
  (def %forms (Tok read-str (%base) "(if #t (+ 1 1) (+ 2 2))\n"))
  (eval (first %forms))
  (def r (cov-branches %forms (lit ((if (branch . cond))))))
  (def missed (first (rest (rest r))))
  (display (first (first missed))))
```
---
    if-else

### a match counts one branch a clause

```x
(do
  (import x/tool/cov cov-branches)
  (def %forms (Tok read-str (%base) "(match ((eq? 1 1) (+ 1 0)) ((eq? 1 2) (+ 2 0)))\n"))
  (eval (first %forms))
  (def r (cov-branches %forms (lit ((match (branch . clauses))))))
  (write (list (first r) (first (rest r)))))
```
---
    (1 2)

### an and counts each argument, and stops where evaluation stopped

```x
(do
  (import x/tool/cov cov-branches)
  (def %forms (Tok read-str (%base) "(and (eq? 1 2) (+ 1 2))\n"))
  (eval (first %forms))
  (def r (cov-branches %forms (lit ((and (branch . short))))))
  (write (list (first r) (first (rest r)))))
```
---
    (1 2)

### a guard's handler is a branch, unreached when nothing raises

```x
(do
  (import x/tool/cov cov-branches)
  (def %forms (Tok read-str (%base) "(guard (e (+ 1 2)) (+ 3 4))\n"))
  (eval (first %forms))
  (def r (cov-branches %forms (lit ((guard (branch . guard))))))
  (write (list (first r) (first (rest r)))))
```
---
    (0 1)

### branches inside a called fn are found

```x
(do
  (import x/tool/cov cov-branches)
  (def %forms (Tok read-str (%base) "(def %cov-probe (fn (_ x) (if (> x 0) (+ x 1) (- x 1))))\n(%cov-probe 5)\n"))
  (eval (first %forms))
  (eval (first (rest %forms)))
  (def r (cov-branches %forms (lit ((if (branch . cond))))))
  (write (list (first r) (first (rest r)))))
```
---
    (1 2)

### a construct declared with no branches is not counted

```x
(do
  (import x/tool/cov cov-branches)
  (def %forms (Tok read-str (%base) "(if #t (+ 1 1) (+ 2 2))\n"))
  (eval (first %forms))
  (write (first (rest (cov-branches %forms (lit ((if (branch . none)) (do (fmt . body)))))))))
```
---
    0

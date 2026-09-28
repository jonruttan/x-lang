# The profiling engine's eval count, read by x/tool/profile

An engine built with `X_PROFILE` counts, in each object's flags word, how
many times evaluation reached it. These cases run on `x-bin-profile` only
(`tools/tests/profile-spec-runner.sh`): an engine without the flag never
writes the count, and every case here would read zero.

## profile: one object

### an expression counts each time it is evaluated

```x
(do
  (import x/tool/profile profile-evals)
  (def %form (first (Tok read-str (%base) "(+ 1 2)\n")))
  (eval %form) (eval %form) (eval %form)
  (display (profile-evals %form)))
```
---
    3

### an expression never evaluated reads zero

```x
(do
  (import x/tool/profile profile-evals)
  (def %form (first (Tok read-str (%base) "(+ 1 2)\n")))
  (display (profile-evals %form)))
```
---
    0

### nil reads zero

```x
(do
  (import x/tool/profile profile-evals)
  (display (profile-evals ())))
```
---
    0

### the largest count is what the contract's width allows

```x
(do
  (import x/tool/profile profile-evals-max)
  (display (= (profile-evals-max) (- (<< 1 %obj-evals-bits) 1))))
```
---
    #t

## profile: one function

### a function's calls are the count of its first body cell

```x
(do
  (import x/tool/profile profile-fn)
  (def %f (fn (_ n) (+ n 1)))
  (%f 1) (%f 2) (%f 3)
  (display (first (profile-fn %f))))
```
---
    3

### its evals are the counts through its body

The body cell and the form in it each count once a call. The two cells that
hold the form's operands are never evaluated themselves.

```x
(do
  (import x/tool/profile profile-fn)
  (def %f (fn (_ n) (+ n 1)))
  (%f 1) (%f 2) (%f 3)
  (display (rest (profile-fn %f))))
```
---
    (6 4 #f)

### a function never called reads zero through its body

```x
(do
  (import x/tool/profile profile-fn)
  (def %f (fn (_ n) (+ n 1)))
  (display (profile-fn %f)))
```
---
    (0 0 4 #f)

### a branch never taken adds nothing

```x
(do
  (import x/tool/profile profile-evals)
  (import x/tool/cov cov-body)
  (def %g (fn (_ x) (match ((= x 0) (+ 1 1)) (#t (+ 2 2)))))
  (%g 1) (%g 1)
  (def %clauses (rest (first (cov-body %g))))
  (display (list (profile-evals (first (rest (first %clauses))))
                 (profile-evals (first (rest (first (rest %clauses))))))))
```
---
    (0 2)

### a loop written as a tail call counts its iterations

```x
(do
  (import x/tool/profile profile-fn)
  (def %loop (fn (self n) (match ((= n 0) ()) (#t (self (- n 1))))))
  (%loop 5)
  (display (first (profile-fn %loop))))
```
---
    6

### an operative's calls are the count of its first form

The engine counts the cells of a procedure's body and never an operative's,
but every call evaluates an operative's first form once, and that form is
counted.

```x
(do
  (import x/tool/profile profile-fn)
  (def %o (op (x) e (+ 1 2)))
  (%o a) (%o b)
  (display (profile-fn %o)))
```
---
    (2 2 4 #f)

### a wrapped combiner has no body of its own

```x
(do
  (import x/tool/profile profile-fn)
  (display (profile-fn (wrap (op (x) e x)))))
```
---
    ()

## profile: a walk

### a pair that carries a stop bit is left out, with everything under it

```x
(do
  (import x/tool/profile profile-tree)
  (def %form (first (Tok read-str (%base) "(a (b c) d)\n")))
  (def %inner (first (rest %form)))
  (def %off (* %obj-slot-flags %word-size))
  (Ptr set-word! (Obj ->ptr %inner) %off
    (+ (Ptr ref-word (Obj ->ptr %inner) %off) %obj-flag-trace))
  (display (list (first (rest (profile-tree %form 0)))
                 (first (rest (profile-tree %form %obj-flag-trace))))))
```
---
    (5 3)

### the stop bit on the pair the walk starts at does not end it

```x
(do
  (import x/tool/profile profile-tree)
  (def %form (first (Tok read-str (%base) "(a b)\n")))
  (def %off (* %obj-slot-flags %word-size))
  (Ptr set-word! (Obj ->ptr %form) %off
    (+ (Ptr ref-word (Obj ->ptr %form) %off) %obj-flag-trace))
  (display (first (rest (profile-tree %form %obj-flag-trace)))))
```
---
    2

### a count at its maximum is reported

```x
(do
  (import x/tool/profile profile-tree profile-evals-max)
  (def %form (first (Tok read-str (%base) "(a b)\n")))
  (def %off (* %obj-slot-flags %word-size))
  (Ptr set-word! (Obj ->ptr %form) %off
    (+ (Ptr ref-word (Obj ->ptr %form) %off)
       (<< (profile-evals-max) %obj-evals-shift)))
  (display (profile-tree %form 0)))
```
---
    (1048575 2 #t)

## profile: the whole process

### clearing sets every count to zero

```x
(do
  (import x/tool/profile profile-fn profile-clear!)
  (def %f (fn (_ n) (+ n 1)))
  (%f 1) (%f 2) (%f 3)
  (profile-clear!)
  (display (profile-fn %f)))
```
---
    (0 0 4 #f)

### clearing zeroes the count and leaves every other flag bit

The engine clears the count's bits across the allocation chain; the trace
bit, the one below them, is still set afterwards.

```x
(do
  (import x/tool/profile profile-evals profile-clear!)
  (def %form (first (Tok read-str (%base) "(+ 1 2)\n")))
  (def %off (* %obj-slot-flags %word-size))
  (eval %form) (eval %form)
  (Ptr set-word! (Obj ->ptr %form) %off
    (+ (Ptr ref-word (Obj ->ptr %form) %off) %obj-flag-trace))
  (profile-clear!)
  (display (list (profile-evals %form)
                 (& (Ptr ref-word (Obj ->ptr %form) %off) %obj-flag-trace))))
```
---
    (0 1024)

### the profiler's own work leaves no row

Between the clear and the reading, the walks call only engine forms,
primitives and the profiler's own functions, whose rows are left out, so a
clear followed at once by a reading finds nothing from any file. The case's
own function comes from the runner's input, which has the empty path, and the
rows are read before the library's `List filter` and printer run.

```x
((fn (_)
   (import x/tool/profile profile-rows profile-clear!)
   (profile-clear!)
   ((fn (_ rows)
      (display (List filter (fn (_ row) (not (str=? (first row) ""))) rows)))
    (profile-rows))))
```
---
    ()

### a function called since the clear has a row

A case's own functions are read from the runner's input and not from a file,
so their rows have the empty path, and the library's do not.

```x
(do
  (import x/tool/profile profile-rows profile-clear!)
  (def %f (fn (_ n) (+ n 1)))
  (profile-clear!)
  (%f 1) (%f 2) (%f 3) (%f 4) (%f 5) (%f 6) (%f 7)
  (def %mine
    (List filter
      (fn (_ row)
        (if (str=? (first row) "") (= (first (rest (rest row))) 7) #f))
      (profile-rows)))
  (display (List map (fn (_ row) (rest (rest row))) %mine)))
```
---
    ((7 14 4 #f))

### a row's source line comes from the body's first form, not its body cell

The reader stamps one object for each thing it reads -- a list's first cell --
and leaves a list's other cells as their allocation left them. A body cell is
one of those, so a stamp found there can be an older object's. Here it names
a file the loader filed, and the row still takes the first form's stamp: the
runner's input, which has the empty path.

```x
(do
  (import x/tool/profile profile-rows profile-clear!)
  (import x/tool/cov cov-body)
  (def %f (fn (_ n) (+ n 1)))
  (def %meta-set! (prim-ref (lit obj) (lit meta-set!)))
  (def %filed (%cell-int (first (first (first (%reflect-base-cell (lit file-registry)))))))
  (%meta-set! (cov-body %f) 0 7)
  (%meta-set! (cov-body %f) 1 %filed)
  (profile-clear!)
  (%f 1) (%f 2) (%f 3) (%f 4) (%f 5) (%f 6) (%f 7) (%f 8) (%f 9) (%f 10) (%f 11)
  (display
    (List map (fn (_ row) (str=? (first row) ""))
         (List filter
           (fn (_ row) (equal? (rest (rest row)) (list 11 22 4 #f)))
           (profile-rows)))))
```
---
    (#t)

### a function made inside another has its own row while one is alive

The inner body is left out of the outer function's sum, so the two rows
divide the counts between them: the outer function's five pairs are its body
cell, the `fn` form's two cells and the two of its parameter list.

```x
(do
  (import x/tool/profile profile-rows profile-clear!)
  (def %outer (fn (_) (fn (_ n) (+ n 1))))
  (profile-clear!)
  (def %inner (%outer))
  (%inner 1) (%inner 2) (%inner 3) (%inner 4) (%inner 5)
  (def %rows (profile-rows))
  (def %with
    (fn (_ calls)
      (List map (fn (_ row) (rest (rest row)))
           (List filter
             (fn (_ row)
               (if (str=? (first row) "")
                 (= (first (rest (rest row))) calls)
                 #f))
             %rows))))
  (display (list (%with 5) (%with 1))))
```
---
    (((5 10 4 #f)) ((1 2 5 #f)))

### the trace flag is cleared again once the rows are gathered

```x
(do
  (import x/tool/profile profile-rows)
  (import x/tool/cov cov-body)
  (def %f (fn (_ n) (+ n 1)))
  (%f 1)
  (profile-rows)
  (display (& (Ptr ref-word (Obj ->ptr (cov-body %f))
                            (* %obj-slot-flags %word-size))
              %obj-flag-trace)))
```
---
    0

### a closure shared by two procedures is one row

```x
(do
  (import x/tool/profile profile-rows profile-clear!)
  (def %make (fn (_) (fn (_ n) (+ n 1))))
  (def %a (%make))
  (def %b (%make))
  (profile-clear!)
  (%a 1) (%a 2) (%a 3) (%b 4) (%b 5) (%b 6) (%b 7) (%b 8) (%b 9)
  (display
    (List map (fn (_ row) (rest (rest row)))
         (List filter
           (fn (_ row)
             (if (str=? (first row) "") (= (first (rest (rest row))) 9) #f))
           (profile-rows)))))
```
---
    ((9 18 4 #f))

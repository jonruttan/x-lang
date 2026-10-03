# @weight 1

Callback (`lib/x/sys/callback.x`): a C function pointer that calls an x
function.  `(Callback make fn nargs)` writes a stub; `(cb address)` is what a
C library takes.  The stub makes each C argument an integer, calls the
function, and answers its result as a C long.

## calls

### a call through the address reaches the function, its arguments integers

```x
(do
  (import x/sys/callback)
  (def %cb-add (Callback make (fn (_ a b c) (+ a (* 10 b) (* 100 c))) 3))
  (def %cb-call (prim-ref (lit ptr) (lit call)))
  (write (%cb-call (Ptr from-int (%cb-add address)) 1 2 3))
  (newline))
```
---
    321

### every argument count, none to four

```x
(do
  (import x/sys/callback)
  (def %cb-call (prim-ref (lit ptr) (lit call)))
  (def %cb-run
    (fn (_ cb . args) (apply %cb-call (pair (Ptr from-int (cb address)) args))))
  (write (list
    (%cb-run (Callback make (fn (_) 7) 0))
    (%cb-run (Callback make (fn (_ a) (* a 2)) 1) 21)
    (%cb-run (Callback make (fn (_ a b) (- a b)) 2) 50 8)
    (%cb-run (Callback make (fn (_ a b c d) (+ a b c d)) 4) 1 2 3 4)))
  (newline))
```
---
    (7 42 42 10)

### an answer that is not an integer: #t is 1, anything else 0

```x
(do
  (import x/sys/callback)
  (def %cb-call (prim-ref (lit ptr) (lit call)))
  (write (list
    (%cb-call (Ptr from-int ((Callback make (fn (_) #t) 0) address)))
    (%cb-call (Ptr from-int ((Callback make (fn (_) ()) 0) address)))
    (%cb-call (Ptr from-int ((Callback make (fn (_) "s") 0) address)))))
  (newline))
```
---
    (1 0 0)

## a C library calling back

### qsort sorts with an x comparator reading the elements through their pointers

```x
(do
  (import x/sys/callback)
  (def %cb-libc ((prim-ref (lit ffi) (lit dlopen)) () 1))
  (def %cb-qsort ((prim-ref (lit ffi) (lit dlsym)) %cb-libc "qsort"))
  (def %cb-call (prim-ref (lit ptr) (lit call)))
  (def %cb-word
    (fn (_ a) ((prim-ref (lit ptr) (lit ref-word)) (Ptr from-int a) 0)))
  (def %cb-cmp (Callback make (fn (_ a b) (- (%cb-word a) (%cb-word b))) 2))
  (def %cb-buf ((prim-ref (lit ptr) (lit alloc)) 40))
  (def %cb-xs (list 5 3 9 1 7))
  (def %cb-fill
    (fn (self i xs)
      (if (null? xs) ()
        (do ((prim-ref (lit ptr) (lit set-word!)) %cb-buf (* 8 i) (first xs))
            (self (+ i 1) (rest xs))))))
  (%cb-fill 0 %cb-xs)
  (%cb-call %cb-qsort %cb-buf 5 8 (%cb-cmp address))
  (def %cb-read
    (fn (self i)
      (if (= i 5) ()
        (pair ((prim-ref (lit ptr) (lit ref-word)) %cb-buf (* 8 i)) (self (+ i 1))))))
  (write (%cb-read 0))
  (newline))
```
---
    (1 3 5 7 9)

## refused

### more than four arguments

```x
(do
  (import x/sys/callback)
  (write (guard (e (e msg)) (Callback make (fn (_ a b c d e) 0) 5)))
  (newline))
```
---
    "Callback make: a C caller passes 0 to 4 arguments"

### a freed callback answers address 0

```x
(do
  (import x/sys/callback)
  (def %cb-f (Callback make (fn (_) 1) 0))
  (%cb-f free!)
  (write (%cb-f address))
  (newline))
```
---
    0

## the stub again

### remake! writes the stub again, as the recache hook does after an image load, and it calls as before

```x
(do
  (import x/sys/callback)
  (def %cb-r (Callback make (fn (_ a) (* a 3)) 1))
  (%cb-r remake!)
  (write ((prim-ref (lit ptr) (lit call)) (Ptr from-int (%cb-r address)) 14))
  (newline))
```
---
    42

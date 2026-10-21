# @weight 1
## call/cc

### is a procedure

```x
(procedure? call/cc)
```
---
    #t

### immediate invoke returns the passed value

```x
(call/cc (fn (_ k) (k 9)))
```
---
    9

### fall-through returns the body value

```x
(call/cc (fn (_ k) 5))
```
---
    5

### escapes from a nested computation

```x
(+ 1 (call/cc (fn (_ k) (+ 10 (k 5)))))
```
---
    6

### invoking with no value returns nil

```x
(null? (call/cc (fn (_ k) (k))))
```
---
    #t

### continuation used as a value

```x
(do (def cell ())
    (set! cell (call/cc (fn (_ k) k)))
    (if (procedure? cell) (cell 42) ())
    cell)
```
---
    42

### a continuation captured inside a guard is marked after the raise

The guard's handler is popped before its clause runs, so the continuation's
state is the only path to the handler record; the collect there walks it,
error value and all (x-engine-c#96).

```x
(do (def kept ())
    (guard (e (Heap collect) (Heap collect))
      (set! kept (call/cc (fn (_ k) k)))
      (error "boom"))
    (procedure? kept))
```
---
    #t

## %cc-invoke -- deliberately not specced here

`%cc-invoke` is the continuation trampoline's internal entry point, called by
the evaluator with a raw pointer, a saved state object and an argument list.
It is plumbing rather than surface: reaching it from x-lang means fabricating
the state object the evaluator owns, and a malformed one is an invalid jump,
not an error. The behaviour it implements is what every `call/cc` case in
this file exercises.

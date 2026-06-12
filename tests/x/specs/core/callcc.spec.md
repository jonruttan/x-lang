## call/cc

### is a procedure

```scheme
(procedure? call/cc)
```
---
    #t

### immediate invoke returns the passed value

```scheme
(call/cc (fn (_ k) (k 9)))
```
---
    9

### fall-through returns the body value

```scheme
(call/cc (fn (_ k) 5))
```
---
    5

### escapes from a nested computation

```scheme
(+ 1 (call/cc (fn (_ k) (+ 10 (k 5)))))
```
---
    6

### invoking with no value returns nil

```scheme
(null? (call/cc (fn (_ k) (k))))
```
---
    #t

### continuation used as a value

```scheme
(do (def cell ())
    (set! cell (call/cc (fn (_ k) k)))
    (if (procedure? cell) (cell 42) ())
    cell)
```
---
    42

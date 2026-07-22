## %sigint-flag

### flag exists and starts at zero

```scheme
(%first-int %sigint-flag)
```
---
    0

## STOP via flag

### flag triggers STOP inside guard

```scheme
(guard (e (if (atom? e) (symbol->str e) e))
  (%set-first-int! %sigint-flag 1)
  (+ 1 2))
```
---
    "STOP"

### eval completes normally when flag is clear

```scheme
(guard (e 'caught)
  (%set-first-int! %sigint-flag 0)
  (+ 1 2))
```
---
    3

### STOP caught by innermost guard

```scheme
(guard (e 'outer)
  (guard (e 'inner)
    (%set-first-int! %sigint-flag 1)
    (+ 1 2)))
```
---
    'inner

## STOP breaks loops

### STOP breaks tail-recursive fn loop

```scheme
(do (def n 0)
    (guard (e n)
      ((fn (f)
        (set! n (+ n 1))
        (if (>= n 100) (%set-first-int! %sigint-flag 1))
        (f))
      )))
```
---
    100

### STOP breaks do loop

```scheme
(do (def n 0)
    (guard (e n)
      (do (def loop (fn (self)
            (set! n (+ n 1))
            (if (>= n 50) (%set-first-int! %sigint-flag 1))
            (self)))
          (loop))))
```
---
    50

## sigint-install and sigint-restore

### sigint-install returns nil

```scheme
(null? (sigint-install))
```
---
    #t

### sigint-restore returns nil

```scheme
(null? (sigint-restore))
```
---
    #t

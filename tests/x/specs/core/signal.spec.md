# @no-seam-collect
<!-- Sigint state is held on the C side (the installed handler's cells) where
     the mark cannot see it -- the same x-lang#283 family, and the "sigint"
     member the runner's pre-seam-collect note always named.  A seam collect
     frees it live: SIGSEGV on Linux, tolerated by macOS.  Runs alone. -->
# @weight 1
## %sigint-flag

### flag exists and starts at zero

```x
(%cell-int %sigint-flag)
```
---
    0

## STOP via flag

### flag triggers STOP inside guard

```x
(guard (e (if (atom? e) (symbol->str e) e))
  (%set-cell-int! %sigint-flag 1)
  (+ 1 2))
```
---
    "STOP"

### eval completes normally when flag is clear

```x
(guard (e 'caught)
  (%set-cell-int! %sigint-flag 0)
  (+ 1 2))
```
---
    3

### STOP caught by innermost guard

```x
(guard (e 'outer)
  (guard (e 'inner)
    (%set-cell-int! %sigint-flag 1)
    (+ 1 2)))
```
---
    'inner

## STOP breaks loops

### STOP breaks tail-recursive fn loop

```x
(do (def n 0)
    (guard (e n)
      ((fn (f)
        (set! n (+ n 1))
        (if (>= n 100) (%set-cell-int! %sigint-flag 1))
        (f))
      )))
```
---
    100

### STOP breaks do loop

```x
(do (def n 0)
    (guard (e n)
      (do (def loop (fn (self)
            (set! n (+ n 1))
            (if (>= n 50) (%set-cell-int! %sigint-flag 1))
            (self)))
          (loop))))
```
---
    50

## sigint-install and sigint-restore

### sigint-install returns nil

```x
(null? (sigint-install))
```
---
    #t

### sigint-restore returns nil

```x
(null? (sigint-restore))
```
---
    #t

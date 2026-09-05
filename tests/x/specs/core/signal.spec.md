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
(guard (e (%display-to-str e))
  (%set-cell-int! %sigint-flag 1)
  (+ 1 2))
```
---
    "STOP"

### the interrupt is recognised through Err stop?, not by lifting bytes

This is what the REPL's ctrl-c path tests. It matters that the predicate
is total over BOTH spellings -- the engine's ERR and a bare `(error
"STOP")` -- because reading the value's own bytes is the thing that keeps
breaking: an ERR answers `atom?` with `#t`, so the old
`(symbol->str err)` lift read a slot as a character pointer and compared
garbage, silently, exactly as it had for `Err` instances in #46.

```x
(list
  (Err stop? (guard (e e) (do (%set-cell-int! %sigint-flag 1) (+ 1 2))))
  (Err stop? (guard (e e) (error "STOP")))
  (Err stop? (guard (e e) nosuchsym))
  (Err stop? "not an error at all"))
```
---
    (#t #t #f #f)

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

# Lexical scope vs globals (GH #47)

Symbol lookup must resolve locals -- including ENCLOSING-frame captures --
ahead of same-named globals, without poisoning any other lexical chain.
The old model walked only the current frame before the global BST and
compensated with a process-global SHADOW bit on the interned symbol; that
broke in both directions:

- a param named after a global operative (`new`) made the global invisible
  to every OTHER chain -- `Err raise` died with "Unbound SYMBOL new";
- a top-level `(def e ...)` hijacked every op's env-param `e` (the BST won
  over the enclosing-frame binding), installing the global's VALUE as an
  environment -- unbound dotted params, or a segfault when `e` was an int.

Now env frame cells carry a FRAME mark and lookup walks the whole frame
region first; the shadow bit is retired.

## a param may shadow a global operative

### Err raise works with a caller param named new

```scheme
((fn (_ new) (guard (g (Err kind-of g)) (Err raise 'value "m" ()))) 1)
```
---
    'value

### the raised error carries through untouched

```scheme
((fn (_ new) (guard (g (g msg)) (Err raise 'value "boom" ()))) 1)
```
---
    "boom"

## a global may share an op env-param name

### def e then a dotted-param static method call

```scheme
(import x/num/random)
(def e (Err make 'io "decoy" ()))
(let ((r (Random sw 42))) (if (null? r) 'no 'ok))
```
---
    'ok

### def e as a plain int does not corrupt dispatch

```scheme
(import x/num/random)
(def e 42)
(let ((r (Random sw 7))) (if (null? r) 'no 'ok))
```
---
    'ok

## enclosing-frame locals beat globals

### a capture two frames up wins over a same-named global

```scheme
(def x-47 1)
((fn (_ x-47) ((fn (_ y) ((fn (_) x-47))) 9)) 2)
```
---
    2

### set! through two frames mutates the local, not the global

```scheme
(def z-47 1)
(list
  ((fn (_ z-47) ((fn (_ y) (do (set! z-47 5) z-47)) 9)) 2)
  z-47)
```
---
    (5 1)

## other chains still see the global during a shadowing extent

### a callee resolves the global while the caller shadows it

```scheme
(def g-47 (fn (_) (list 1 2)))
((fn (_ list) (g-47)) 1)
```
---
    (1 2)

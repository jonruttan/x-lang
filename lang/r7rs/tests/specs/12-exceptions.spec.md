## error

### error raises exception

```scheme
(guard (e #t) (error "boom"))
```
---
    #t

### error with string message

```scheme
(guard (e e) (error "boom"))
```
---
    "boom"

### error with number

```scheme
(guard (e e) (error 42))
```
---
    42

### error with symbol

```scheme
(guard (e e) (error (quote oops)))
```
---
    oops

## guard

### guard catches error

```scheme
(guard (e (list (quote caught) e)) (error "fail"))
```
---
    (caught "fail")

### guard returns body when no error

```scheme
(guard (e (quote caught)) (+ 1 2))
```
---
    3

### guard with multiple body forms

```scheme
(guard (e (quote caught)) 1 2 (+ 3 4))
```
---
    7

### guard handler uses error value

```scheme
(guard (e (+ e 1)) (error 41))
```
---
    42

### guard handler builds list

```scheme
(guard (e (list (quote err) e)) (error (list 1 2 3)))
```
---
    (err (1 2 3))

## guard with computation

### guard in let

```scheme
(let ((x 10)) (guard (e (+ x 1)) (error "fail")))
```
---
    11

### guard in define

```scheme
(define (safe-op) (guard (e 0) (error "fail"))) (safe-op)
```
---
    0

### guard passes through normal value

```scheme
(guard (e (quote bad)) (list 1 2 3))
```
---
    (1 2 3)

### guard passes through arithmetic

```scheme
(guard (e (quote bad)) (* 6 7))
```
---
    42


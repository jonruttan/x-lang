## error

### error raises exception

```scheme
(guard (e (#t #t)) (error "boom"))
```
---
    #t

### error with string message

```scheme
(guard (e (#t e)) (error "boom"))
```
---
    "boom"

### error with number

```scheme
(guard (e (#t e)) (error 42))
```
---
    42

### error with symbol

```scheme
(guard (e (#t e)) (error (quote oops)))
```
---
    oops

## guard

### guard catches error

```scheme
(guard (e (#t (list (quote caught) e))) (error "fail"))
```
---
    (caught "fail")

### guard returns body when no error

```scheme
(guard (e (#t (quote caught))) (+ 1 2))
```
---
    3

### guard with multiple body forms

```scheme
(guard (e (#t (quote caught))) 1 2 (+ 3 4))
```
---
    7

### guard handler uses error value

```scheme
(guard (e (#t (+ e 1))) (error 41))
```
---
    42

### guard handler builds list

```scheme
(guard (e (#t (list (quote err) e))) (error (list 1 2 3)))
```
---
    (err (1 2 3))

## guard with computation

### guard in let

```scheme
(let ((x 10)) (guard (e (#t (+ x 1))) (error "fail")))
```
---
    11

### guard in define

```scheme
(define (safe-op) (guard (e (#t 0)) (error "fail"))) (safe-op)
```
---
    0

### guard passes through normal value

```scheme
(guard (e (#t (quote bad))) (list 1 2 3))
```
---
    (1 2 3)

### guard passes through arithmetic

```scheme
(guard (e (#t (quote bad))) (* 6 7))
```
---
    42

## guard with cond clauses

### guard matches first clause

```scheme
(guard (e ((string? e) (string-append "Error: " e)) (#t "other"))
  (error "boom"))
```
---
    "Error: boom"

### guard matches second clause

```scheme
(guard (e ((number? e) (+ e 1)) (#t "other"))
  (error "not-a-number"))
```
---
    other

### guard with else clause

```scheme
(guard (e ((number? e) "number") (else "else"))
  (error "boom"))
```
---
    else

### guard multiple clauses with number

```scheme
(guard (e ((string? e) "string") ((number? e) (* e 2)) (else "other"))
  (error 21))
```
---
    42

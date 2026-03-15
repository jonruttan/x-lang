## eqv?

### eqv? same boolean true

```scheme
(eqv? #t #t)
```
---
    #t

### eqv? same boolean false

```scheme
(eqv? #f #f)
```
---
    #t

### eqv? same symbol

```scheme
(eqv? (quote a) (quote a))
```
---
    #t

### eqv? different symbols

```scheme
(not (eqv? (quote a) (quote b)))
```
---
    #t

### eqv? same number

```scheme
(eqv? 42 42)
```
---
    #t

### eqv? different numbers

```scheme
(not (eqv? 1 2))
```
---
    #t

### eqv? same char

```scheme
(eqv? #\a #\a)
```
---
    #t

### eqv? different chars

```scheme
(not (eqv? #\a #\b))
```
---
    #t

### eqv? empty lists

```scheme
(eqv? () ())
```
---
    #t

### eqv? string to symbol

```scheme
(not (eqv? "a" (quote a)))
```
---
    #t

### eqv? number to char

```scheme
(not (eqv? 65 #\A))
```
---
    #t

## eq?

### eq? same symbol

```scheme
(eq? (quote a) (quote a))
```
---
    #t

### eq? different symbols

```scheme
(not (eq? (quote a) (quote b)))
```
---
    #t

### eq? empty lists

```scheme
(eq? () ())
```
---
    #t

### eq? booleans

```scheme
(eq? #t #t)
```
---
    #t

## equal?

### equal? same lists

```scheme
(equal? (list 1 2 3) (list 1 2 3))
```
---
    #t

### equal? different lists

```scheme
(not (equal? (list 1 2) (list 1 3)))
```
---
    #t

### equal? nested lists

```scheme
(equal? (list 1 (list 2 3)) (list 1 (list 2 3)))
```
---
    #t

### equal? strings

```scheme
(equal? "abc" "abc")
```
---
    #t

### equal? different strings

```scheme
(not (equal? "abc" "abd"))
```
---
    #t

### equal? numbers

```scheme
(equal? 42 42)
```
---
    #t

### equal? mixed types

```scheme
(not (equal? 1 "1"))
```
---
    #t

### equal? dotted pairs

```scheme
(equal? (cons 1 2) (cons 1 2))
```
---
    #t

### equal? deep nested

```scheme
(equal? (list (list 1 (list 2)) (list 3)) (list (list 1 (list 2)) (list 3)))
```
---
    #t

### equal? chars

```scheme
(equal? #\a #\a)
```
---
    #t


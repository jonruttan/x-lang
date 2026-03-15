## type predicates

### number?

```scheme
(number? 42)
```
---
    #t

### number? false

```scheme
(not (number? "hello"))
```
---
    #t

### string?

```scheme
(string? "hello")
```
---
    #t

### string? false

```scheme
(not (string? 42))
```
---
    #t

### symbol?

```scheme
(symbol? (quote hello))
```
---
    #t

### symbol? false

```scheme
(not (symbol? 42))
```
---
    #t

### procedure? on lambda

```scheme
(procedure? (lambda (x) x))
```
---
    #t

### procedure? on builtin

```scheme
(procedure? car)
```
---
    #t

### procedure? false

```scheme
(not (procedure? 42))
```
---
    #t

### pair?

```scheme
(pair? (list 1 2))
```
---
    #t

### null? on empty

```scheme
(null? ())
```
---
    #t

### boolean? on #t

```scheme
(boolean? #t)
```
---
    #t

### boolean? on #f

```scheme
(boolean? #f)
```
---
    #t

### boolean? false

```scheme
(not (boolean? 42))
```
---
    #t

### char? on char

```scheme
(char? #\a)
```
---
    #t

### char? false

```scheme
(not (char? 42))
```
---
    #t

## equality

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

### equal? on lists

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

### eqv? on numbers

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

## list?

### list? on proper list

```scheme
(list? (list 1 2))
```
---
    #t

### list? on empty

```scheme
(list? ())
```
---
    #t

### list? on dotted pair

```scheme
(not (list? (cons 1 2)))
```
---
    #t

### list? on atom

```scheme
(not (list? 42))
```
---
    #t

## number predicates

### zero?

```scheme
(zero? 0)
```
---
    #t

### zero? false

```scheme
(not (zero? 1))
```
---
    #t

### zero? negative

```scheme
(not (zero? (- 0 1)))
```
---
    #t

### positive?

```scheme
(positive? 5)
```
---
    #t

### positive? false

```scheme
(not (positive? 0))
```
---
    #t

### negative?

```scheme
(negative? (- 0 3))
```
---
    #t

### negative? false

```scheme
(not (negative? 0))
```
---
    #t

### even?

```scheme
(even? 4)
```
---
    #t

### even? false

```scheme
(not (even? 3))
```
---
    #t

### even? zero

```scheme
(even? 0)
```
---
    #t

### odd?

```scheme
(odd? 3)
```
---
    #t

### odd? false

```scheme
(not (odd? 4))
```
---
    #t

## numeric operations

### abs positive

```scheme
(abs 5)
```
---
    5

### abs negative

```scheme
(abs (- 0 5))
```
---
    5

### abs zero

```scheme
(abs 0)
```
---
    0

### min

```scheme
(min 3 7)
```
---
    3

### max

```scheme
(max 3 7)
```
---
    7

### modulo

```scheme
(modulo 10 3)
```
---
    1


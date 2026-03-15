# R5RS Compliance

## equivalence predicates

### eqv? on booleans

```scheme
(eqv? #t #t)
```
---
    t

### eqv? on symbols

```scheme
(eqv? 'a 'a)
```
---
    t

### eqv? symbol mismatch

```scheme
(null? (eqv? 'a 'b))
```
---
    t

### eqv? on numbers

```scheme
(eqv? 2 2)
```
---
    t

### eqv? on empty lists

```scheme
(eqv? '() '())
```
---
    t

### eqv? on chars

```scheme
(eqv? #\a #\a)
```
---
    t

### eqv? char mismatch

```scheme
(null? (eqv? #\a #\b))
```
---
    t

### eqv? different types

```scheme
(null? (eqv? #t 'a))
```
---
    t

### eq? on symbols

```scheme
(eq? 'a 'a)
```
---
    t

### eq? on empty lists

```scheme
(eq? '() '())
```
---
    t

### eq? self identity

```scheme
(let ((x '(a)))
  (eq? x x))
```
---
    t

### eq? procedure identity

```scheme
(let ((p (lambda (x) x)))
  (eq? p p))
```
---
    t

### equal? on lists

```scheme
(equal? '(a b c) '(a b c))
```
---
    t

### equal? on nested lists

```scheme
(equal? '(a (b) c) '(a (b) c))
```
---
    t

### equal? on strings

```scheme
(equal? "abc" "abc")
```
---
    t

### equal? on vectors

```scheme
(equal? (vector 1 2 3) (vector 1 2 3))
```
---
    t

### equal? on numbers

```scheme
(equal? 2 2)
```
---
    t

## numeric operations

### quotient positive

```scheme
(quotient 13 4)
```
---
    3

### quotient negative dividend

```scheme
(quotient -13 4)
```
---
    -3

### quotient negative divisor

```scheme
(quotient 13 -4)
```
---
    -3

### quotient both negative

```scheme
(quotient -13 -4)
```
---
    3

### remainder positive

```scheme
(remainder 13 4)
```
---
    1

### remainder negative dividend

```scheme
(remainder -13 4)
```
---
    -1

### remainder negative divisor

```scheme
(remainder 13 -4)
```
---
    1

### remainder both negative

```scheme
(remainder -13 -4)
```
---
    -1

### modulo positive

```scheme
(modulo 13 4)
```
---
    1

### modulo negative dividend

```scheme
(modulo -13 4)
```
---
    3

### modulo negative divisor

```scheme
(modulo 13 -4)
```
---
    -3

### modulo both negative

```scheme
(modulo -13 -4)
```
---
    -1

### quotient-remainder invariant

```scheme
(= 13 (+ (* 4 (quotient 13 4)) (remainder 13 4)))
```
---
    t

### gcd

```scheme
(gcd 32 -36)
```
---
    4

### gcd with zero

```scheme
(gcd 0 5)
```
---
    5

### lcm

```scheme
(lcm 32 -36)
```
---
    288

### lcm with zero

```scheme
(lcm 0 5)
```
---
    0

### expt basic

```scheme
(expt 2 10)
```
---
    1024

### expt zero power

```scheme
(expt 5 0)
```
---
    1

### expt power of one

```scheme
(expt 7 1)
```
---
    7

## list operations

### append with improper list

```scheme
(append '(a b) '(c . d))
```
---
    (a b c . d)

### append empty to atom

```scheme
(append '() 'a)
```
---
    a

### list-tail

```scheme
(list-tail '(a b c d e) 2)
```
---
    (c d e)

### list-ref

```scheme
(list-ref '(a b c d) 2)
```
---
    c

### list? on proper list

```scheme
(list? '(a b c))
```
---
    t

### list? on empty

```scheme
(list? '())
```
---
    t

### list? on dotted pair

```scheme
(null? (list? '(a . b)))
```
---
    t

### memq found

```scheme
(memq 'a '(a b c))
```
---
    (a b c)

### memq middle

```scheme
(memq 'b '(a b c))
```
---
    (b c)

### memq not found

```scheme
(null? (memq 'a '(b c d)))
```
---
    t

### memv with numbers

```scheme
(memv 2 '(1 2 3))
```
---
    (2 3)

### assq found

```scheme
(assq 'b '((a 1) (b 2) (c 3)))
```
---
    (b 2)

### assq not found

```scheme
(null? (assq 'd '((a 1) (b 2) (c 3))))
```
---
    t

### assv with numbers

```scheme
(assv 2 '((1 one) (2 two) (3 three)))
```
---
    (2 two)

### assoc with strings

```scheme
(assoc "b" '(("a" 1) ("b" 2) ("c" 3)))
```
---
    ("b" 2)

## string operations

### string constructor from chars

```scheme
(string #\a #\b #\c)
```
---
    "abc"

### string->list round trip

```scheme
(equal? (string->list "abc") (list #\a #\b #\c))
```
---
    t

### list->string round trip

```scheme
(string=? (list->string '(#\a #\b #\c)) "abc")
```
---
    t

### string->list then list->string identity

```scheme
(string=? (list->string (string->list "hello")) "hello")
```
---
    t

### substring

```scheme
(string=? (substring "hello world" 6 11) "world")
```
---
    t

### string-copy

```scheme
(let ((s "hello"))
  (string=? (string-copy s) s))
```
---
    t

### string-append multiple

```scheme
(string=? (string-append "a" "b" "c") "abc")
```
---
    t

## control features

### apply with list

```scheme
(apply + '(3 4))
```
---
    7

### apply with extra args

```scheme
(apply + 1 2 '(3 4))
```
---
    10

### map basic

```scheme
(map car '((a b) (d e) (g h)))
```
---
    (a d g)

### map with lambda

```scheme
(map (lambda (n) (* n n)) '(1 2 3 4 5))
```
---
    (1 4 9 16 25)

### map with multiple lists

```scheme
(map + '(1 2 3) '(4 5 6))
```
---
    (5 7 9)

### for-each ordering

```scheme
(let ((v '()))
  (for-each (lambda (x) (set! v (cons x v))) '(1 2 3))
  v)
```
---
    (3 2 1)

## promises

### force delay

```scheme
(force (delay (+ 1 2)))
```
---
    3

### delay memoization

```scheme
(let ((count 0))
  (let ((p (delay (begin (set! count (+ count 1)) count))))
    (force p)
    (force p)
    count))
```
---
    1

### force non-promise

```scheme
(force 42)
```
---
    42

## boolean

### boolean? on true

```scheme
(boolean? #t)
```
---
    t

### boolean? on false

```scheme
(boolean? #f)
```
---
    t

### boolean? on number

```scheme
(null? (boolean? 0))
```
---
    t

### not true is false

```scheme
(null? (not #t))
```
---
    t

### not false is true

```scheme
(not #f)
```
---
    t

### not zero is false (zero is truthy)

```scheme
(null? (not 0))
```
---
    t

## procedure?

### procedure? on lambda

```scheme
(procedure? (lambda (x) x))
```
---
    t

### procedure? on builtin

```scheme
(procedure? car)
```
---
    t

### procedure? on symbol

```scheme
(null? (procedure? 'car))
```
---
    t

### procedure? on number

```scheme
(null? (procedure? 42))
```
---
    t

# cond and case enhancements

## cond => syntax

### cond => applies procedure to test value

```scheme
(cond (#f 'no) (42 => (lambda (x) (* x 2))))
```
---
    84

### cond => with list

```scheme
(cond ((assv 2 '((1 one) (2 two) (3 three))) => cdr))
```
---
    (two)

### cond => skips false clauses

```scheme
(cond (#f => (lambda (x) 'bad)) (#t 'good))
```
---
    good

## cond multi-expression bodies

### cond clause with multiple expressions

```scheme
(let ((x 0))
  (cond (#t (set! x 10) (+ x 5))))
```
---
    15

### cond else with multiple expressions

```scheme
(let ((x 0))
  (cond (#f 'no) (else (set! x 1) (+ x 2))))
```
---
    3

## case multi-expression bodies

### case clause with multiple expressions

```scheme
(let ((x 0))
  (case 2
    ((1) 'one)
    ((2) (set! x 10) (+ x 5))
    ((3) 'three)))
```
---
    15

### case else with multiple expressions

```scheme
(let ((x 0))
  (case 99
    ((1) 'one)
    (else (set! x 1) (+ x 2))))
```
---
    3

### case with datum lists

```scheme
(case (* 2 3)
  ((2 3 5 7) 'prime)
  ((1 4 6 8 9) 'composite))
```
---
    composite

### case with symbol matching

```scheme
(case (car '(c d))
  ((a e i o u) 'vowel)
  ((w y) 'semivowel)
  (else 'consonant))
```
---
    consonant

## do iteration

### do basic counting

```scheme
(let ((x '()))
  (do ((i 0 (+ i 1)))
    ((= i 5) x)
    (set! x (cons i x))))
```
---
    (4 3 2 1 0)

### do sum

```scheme
(let ((x '(1 3 5 7 9)))
  (do ((x x (cdr x))
       (sum 0 (+ sum (car x))))
    ((null? x) sum)))
```
---
    25

### do without step

```scheme
(do ((i 5))
  ((zero? i) 'done)
  (set! i (- i 1)))
```
---
    done

### do empty result

```scheme
(null? (do ((i 3 (- i 1)))
  ((zero? i))))
```
---
    #t

## named let

### named let loop

```scheme
(let loop ((n 10) (acc 0))
  (if (zero? n) acc
    (loop (- n 1) (+ acc n))))
```
---
    55

### named let fibonacci

```scheme
(let fib ((n 10) (a 0) (b 1))
  (if (zero? n) a
    (fib (- n 1) b (+ a b))))
```
---
    55

### named let list builder

```scheme
(let loop ((i 5) (acc '()))
  (if (zero? i) acc
    (loop (- i 1) (cons i acc))))
```
---
    (1 2 3 4 5)

# Closure and higher-order stress tests

## closure stress

### many independent closures

```scheme
(define (make-adder n) (lambda (x) (+ x n))) (let ((adders (map make-adder '(1 2 3 4 5 6 7 8 9 10)))) (fold + 0 (map (lambda (f) (f 100)) adders)))
```
---
    1055

### counter closures

```scheme
(define (make-counter) (let ((n 0)) (lambda () (set! n (+ n 1)) n))) (let ((c (make-counter))) (let loop ((i 0)) (if (= i 1000) (c) (begin (c) (loop (+ i 1))))))
```
---
    1001

## compose stress

### deep composition

```scheme
(define (compose f g) (lambda args (f (apply g args)))) (define (add1 x) (+ x 1)) (let ((f (compose add1 (compose add1 (compose add1 (compose add1 add1)))))) (f 0))
```
---
    5

## letrec mutual recursion

### even/odd deep recursion

```scheme
(letrec ((my-even? (lambda (n) (if (= n 0) #t (my-odd? (- n 1))))) (my-odd? (lambda (n) (if (= n 0) #f (my-even? (- n 1)))))) (list (my-even? 10000) (my-odd? 9999)))
```
---
    (#t #t)

## promise stress

### many forces same promise

```scheme
(let ((count 0)) (let ((p (delay (begin (set! count (+ count 1)) count)))) (let loop ((i 0)) (if (= i 100) (list (force p) count) (begin (force p) (loop (+ i 1)))))))
```
---
    (1 1)

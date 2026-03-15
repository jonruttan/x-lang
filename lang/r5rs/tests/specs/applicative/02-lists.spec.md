# List stress tests

## map stress

### map over large list

```scheme
(define (iota n) (let loop ((i (- n 1)) (acc '())) (if (< i 0) acc (loop (- i 1) (cons i acc))))) (length (map (lambda (x) (* x x)) (iota 5000)))
```
---
    5000

### map preserves order

```scheme
(define (iota n) (let loop ((i (- n 1)) (acc '())) (if (< i 0) acc (loop (- i 1) (cons i acc))))) (list-ref (map (lambda (x) (* x 2)) (iota 1000)) 999)
```
---
    1998

## fold stress

### fold over large list

```scheme
(define (iota n) (let loop ((i (- n 1)) (acc '())) (if (< i 0) acc (loop (- i 1) (cons i acc))))) (fold + 0 (iota 1000))
```
---
    499500

## append stress

### append many small lists

```scheme
(define (build n acc) (if (= n 0) acc (build (- n 1) (append acc (list n))))) (length (build 1000 '()))
```
---
    1000

## reverse stress

### reverse large list

```scheme
(define (iota n) (let loop ((i (- n 1)) (acc '())) (if (< i 0) acc (loop (- i 1) (cons i acc))))) (car (reverse (iota 5000)))
```
---
    4999

## filter stress

### filter large list

```scheme
(define (iota n) (let loop ((i (- n 1)) (acc '())) (if (< i 0) acc (loop (- i 1) (cons i acc))))) (length (filter even? (iota 10000)))
```
---
    5000

## for-each stress

### for-each over large list

```scheme
(define (iota n) (let loop ((i (- n 1)) (acc '())) (if (< i 0) acc (loop (- i 1) (cons i acc))))) (let ((count 0)) (for-each (lambda (x) (set! count (+ count 1))) (iota 5000)) count)
```
---
    5000

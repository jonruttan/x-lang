## TCO stress

### do loop 50000 iterations

```scheme
(do ((i 0 (+ i 1)))
    ((= i 50000) i))
```
---
    50000

### named let 50000 iterations

```scheme
(let loop ((n 50000))
  (if (= n 0) 0 (loop (- n 1))))
```
---
    0

### case-lambda dispatch 10000 times

```scheme
(let ((f (case-lambda
           ((x) x)
           ((x y) (+ x y)))))
  (do ((i 0 (+ i 1))
       (acc 0 (f acc i)))
      ((= i 10000) acc)))
```
---
    49995000

## promise stress

### force deeply chained promises

```scheme
(let loop ((i 0) (p (delay 42)))
  (if (= i 1000)
    (force p)
    (loop (+ i 1) (delay (force p)))))
```
---
    42

### make-promise many times

```scheme
(do ((i 0 (+ i 1))
     (p (make-promise 0) (make-promise i)))
    ((= i 10000) (force p)))
```
---
    9999

## values stress

### values round-trip 10000 times

```scheme
(do ((i 0 (+ i 1))
     (acc 0 (call-with-values (lambda () (values acc 1)) +)))
    ((= i 10000) acc))
```
---
    10000

## record stress

### create and access 5000 records

```scheme
(define-record-type <point> (make-point x y) point?
  (x point-x) (y point-y))
(do ((i 0 (+ i 1))
     (sum 0 (+ sum (point-x (make-point i 0)))))
    ((= i 5000) sum))
```
---
    12497500

## vector stress

### vector-map over 1000 elements

```scheme
(let ((v (do ((i 0 (+ i 1))
              (acc () (cons i acc)))
             ((= i 1000) (list->vector acc)))))
  (let ((v2 (vector-map (lambda (x) (+ x 1)) v)))
    (vector-length v2)))
```
---
    1000

### vector-append repeated

```scheme
(let ((v (vector 1 2)))
  (do ((i 0 (+ i 1))
       (acc v (vector-append acc acc)))
      ((= i 8) (vector-length acc))))
```
---
    512

## string stress

### string-map over 1000 chars

```scheme
(let ((s (make-string 1000 #\a)))
  (string-length (string-map char-upcase s)))
```
---
    1000

### string-for-each counter

```scheme
(let ((count 0))
  (string-for-each (lambda (c) (set! count (+ count 1)))
                   (make-string 1000 #\x))
  count)
```
---
    1000

## do iteration patterns

### nested do loops

```scheme
(do ((i 0 (+ i 1))
     (sum 0))
    ((= i 100)
     sum)
  (set! sum
    (do ((j 0 (+ j 1))
         (inner sum (+ inner 1)))
        ((= j 100) inner))))
```
---
    10000

### do with multiple step variables

```scheme
(do ((i 0 (+ i 1))
     (evens 0 (if (even? i) (+ evens 1) evens))
     (odds 0 (if (odd? i) (+ odds 1) odds)))
    ((= i 10000) (list evens odds)))
```
---
    (5000 5000)

## list-copy stress

### list-copy 1000 elements

```scheme
(let ((orig (do ((i 0 (+ i 1)) (acc () (cons i acc)))
                ((= i 1000) acc))))
  (let ((copy (list-copy orig)))
    (and (equal? orig copy) (length copy))))
```
---
    1000

## make-list stress

### make-list 2000 elements

```scheme
(length (make-list 2000 0))
```
---
    2000

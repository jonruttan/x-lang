# R5RS First-class Continuations

## escape continuations

### basic escape

```scheme
(call-with-current-continuation
  (lambda (k) (k 42) 99))
```
---
    42

### no escape returns normally

```scheme
(call-with-current-continuation
  (lambda (k) 77))
```
---
    77

### escape in arithmetic context

```scheme
(+ 1 (call/cc (lambda (k) (+ 2 (k 3)))))
```
---
    4

### early exit from for-each

```scheme
(call-with-current-continuation
  (lambda (exit)
    (for-each (lambda (x)
                (if (negative? x) (exit x)))
              '(54 0 37 -3 245 19))
    #t))
```
---
    -3

## upward continuations

### save and invoke later

```scheme
(let ((k-saved #f))
  (let ((x (+ 1 (call/cc (lambda (k) (set! k-saved k) 0)))))
    (if (< x 5)
      (k-saved x)
      x)))
```
---
    5

### continuation in loop

```scheme
(let ((saved #f)
      (n 0))
  (call/cc (lambda (k) (set! saved k)))
  (set! n (+ n 1))
  (if (< n 3) (saved))
  n)
```
---
    3

### continuation returns value

```scheme
(let ((k-saved #f)
      (done #f))
  (let ((x (+ 10 (call/cc (lambda (k) (set! k-saved k) 0)))))
    (if done x
      (begin (set! done #t) (k-saved 5)))))
```
---
    15

## multiple invocations

### same continuation invoked multiple times

```scheme
(let ((k-saved #f)
      (results '()))
  (let ((x (call/cc (lambda (k) (set! k-saved k) 0))))
    (set! results (cons x results))
    (if (< x 3)
      (k-saved (+ x 1))
      (reverse results))))
```
---
    (0 1 2 3)

## predicates

### call/cc is a procedure

```scheme
(procedure? call-with-current-continuation)
```
---
    #t

### call/cc alias works

```scheme
(eq? call/cc call-with-current-continuation)
```
---
    #t

## dynamic-wind

### after runs on escape

```scheme
(let ((r (list)))
  (call/cc
    (lambda (k)
      (dynamic-wind
        (lambda () (set! r (cons 'before r)))
        (lambda () (k 'escaped))
        (lambda () (set! r (cons 'after r))))))
  (reverse r))
```
---
    (before after)

### before runs on re-entry

```scheme
(let ((r (list)) (k-saved #f) (done #f))
  (dynamic-wind
    (lambda () (set! r (cons 'before r)))
    (lambda ()
      (call/cc (lambda (k) (set! k-saved k)))
      (set! r (cons 'body r)))
    (lambda () (set! r (cons 'after r))))
  (if done (reverse r)
    (begin (set! done #t) (k-saved))))
```
---
    (before body after before body after)

### nested unwind calls after thunks inner to outer

```scheme
(let ((r (list)))
  (call/cc
    (lambda (k)
      (dynamic-wind
        (lambda () (set! r (cons 1 r)))
        (lambda ()
          (dynamic-wind
            (lambda () (set! r (cons 2 r)))
            (lambda () (k 'done))
            (lambda () (set! r (cons 3 r)))))
        (lambda () (set! r (cons 4 r))))))
  (reverse r))
```
---
    (1 2 3 4)

### normal dynamic-wind without escape

```scheme
(let ((x 0))
  (dynamic-wind
    (lambda () (set! x (+ x 1)))
    (lambda () (+ x 10))
    (lambda () (set! x (+ x 100)))))
```
---
    11


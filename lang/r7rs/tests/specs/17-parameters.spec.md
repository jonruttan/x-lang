## make-parameter

### basic parameter

```scheme
(define p (make-parameter 10))
(p)
```
---
    10

### parameter with converter

```scheme
(define p (make-parameter "hello" string-length))
(p)
```
---
    5

### set parameter value

```scheme
(define p (make-parameter 42))
(p 99)
(p)
```
---
    99

### converter applied on init

```scheme
(define p (make-parameter 3 (lambda (x) (* x 2))))
(p)
```
---
    6

### converter applied on set

```scheme
(define p (make-parameter 0 (lambda (x) (* x 2))))
(p 5)
(p)
```
---
    10

## parameterize

### basic parameterize

```scheme
(define p (make-parameter 10))
(parameterize ((p 20))
  (p))
```
---
    20

### parameterize restores on exit

```scheme
(define p (make-parameter 10))
(parameterize ((p 20))
  (p))
(p)
```
---
    10

### nested parameterize

```scheme
(define p (make-parameter 1))
(parameterize ((p 2))
  (parameterize ((p 3))
    (p)))
```
---
    3

### nested parameterize restores correctly

```scheme
(define p (make-parameter 1))
(define result
  (parameterize ((p 2))
    (let ((inner (parameterize ((p 3)) (p))))
      (list inner (p)))))
result
```
---
    (3 2)

### parameterize with multiple bindings

```scheme
(define p1 (make-parameter 10))
(define p2 (make-parameter 20))
(parameterize ((p1 100) (p2 200))
  (list (p1) (p2)))
```
---
    (100 200)

### parameterize with converter

```scheme
(define p (make-parameter 0 (lambda (x) (* x 2))))
(parameterize ((p 5))
  (p))
```
---
    10


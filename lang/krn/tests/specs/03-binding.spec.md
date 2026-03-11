## $let

### binds locally

```scheme
($let ((x 10)) x)
```
---
    10

### multiple bindings

```scheme
($let ((x 1) (y 2)) (+ x y))
```
---
    3

## $let*

### sequential binding

```scheme
($let* ((x 1) (y (+ x 1))) (+ x y))
```
---
    3

### nested reference

```scheme
($let* ((a 2) (b (* a 3)) (c (+ a b))) c)
```
---
    8

### three-level chain

```scheme
($let* ((x 1) (y (+ x 1)) (z (+ y 1))) z)
```
---
    3


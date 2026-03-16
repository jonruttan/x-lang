## let-values

### single binding

```scheme
(let-values (((a b) (values 1 2)))
  (+ a b))
```
---
    3

### multiple bindings

```scheme
(let-values (((a b) (values 1 2))
             ((c) (values 3)))
  (+ a b c))
```
---
    6

### destructure three values

```scheme
(let-values (((x y z) (values 10 20 30)))
  (list x y z))
```
---
    (10 20 30)

### single value binding

```scheme
(let-values (((x) (values 42)))
  x)
```
---
    42

## let*-values

### sequential bindings

```scheme
(let*-values (((a b) (values 1 2))
              ((c) (values (+ a b))))
  c)
```
---
    3

### nested access

```scheme
(let*-values (((x) (values 10))
              ((y z) (values (* x 2) (* x 3))))
  (list x y z))
```
---
    (10 20 30)

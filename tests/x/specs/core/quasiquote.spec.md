## quasi

### returns a literal list

```scheme
(quasi (1 2 3))
```
---
    (1 2 3)

### returns a literal symbol

```scheme
(quasi foo)
```
---
    'foo

### returns nil for empty list

```scheme
(quasi ())
```
---

### returns a nested literal

```scheme
(quasi (a (b c) d))
```
---
    ('a ('b 'c) 'd)

## unquote

### substitutes a variable

```scheme
(do (def x 42) (quasi (a (unquote x) c)))
```
---
    ('a 42 'c)

### evaluates an expression

```scheme
(quasi (result (unquote (+ 1 2))))
```
---
    ('result 3)

### substitutes in first position

```scheme
(do (def op (lit +)) (quasi ((unquote op) 1 2)))
```
---
    ('+ 1 2)

### substitutes in last position

```scheme
(do (def x 99) (quasi (a b (unquote x))))
```
---
    ('a 'b 99)

### handles multiple unquotes

```scheme
(do (def a 1) (def b 2) (quasi ((unquote a) (unquote b))))
```
---
    (1 2)

## unquote-splicing

### splices a list

```scheme
(do (def xs (list 2 3)) (quasi (1 (unquote-splicing xs) 4)))
```
---
    (1 2 3 4)

### splices an empty list

```scheme
(quasi (a (unquote-splicing (list)) b))
```
---
    ('a 'b)

### splices at beginning

```scheme
(do (def xs (list 1 2)) (quasi ((unquote-splicing xs) 3)))
```
---
    (1 2 3)

### splices at end

```scheme
(do (def xs (list 3 4)) (quasi (1 2 (unquote-splicing xs))))
```
---
    (1 2 3 4)

### splices with unquote mixed

```scheme
(do (def x 1) (def ys (list 2 3)) (quasi ((unquote x) (unquote-splicing ys) 4)))
```
---
    (1 2 3 4)

## quasi edge cases

### handles integer atom

```scheme
(quasi 42)
```
---
    42

### handles string atom

```scheme
(quasi "hello")
```
---
    "hello"

### handles dotted pair

```scheme
(do (def x 2) (quasi (1 (unquote x))))
```
---
    (1 2)


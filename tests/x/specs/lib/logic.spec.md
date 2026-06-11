## boolean?

### true for #t

```scheme
(boolean? #t)
```
---
    #t

### true for #f

```scheme
(boolean? #f)
```
---
    #t

### false for number

```scheme
(if (boolean? 42) "y" "n")
```
---
    "n"

## default-to

### returns value when non-nil

```scheme
(Fn default-to 0 42)
```
---
    42

### returns default when nil

```scheme
(Fn default-to 0 ())
```
---
    0

## until

### iterates until predicate holds

```scheme
(Fn until (fn (_ x) (> x 10)) (method-ref Num inc) 1)
```
---
    11

## equal?

### compares numbers

```scheme
(equal? 5 5)
```
---
    #t

### compares different numbers

```scheme
(if (equal? 5 6) "y" "n")
```
---
    "n"

### compares strings

```scheme
(equal? "hi" "hi")
```
---
    #t

### compares nil

```scheme
(equal? () ())
```
---
    #t

### compares different symbols

```scheme
(if (equal? (lit a) (lit b)) "y" "n")
```
---
    "n"

### compares equal symbols

```scheme
(equal? (lit a) (lit a))
```
---
    #t

### compares different strings

```scheme
(if (equal? "foo" "bar") "y" "n")
```
---
    "n"

## until

### returns immediately when predicate holds

```scheme
(Fn until (fn (_ x) (> x 10)) (method-ref Num inc) 15)
```
---
    15


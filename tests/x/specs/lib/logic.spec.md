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
(if (equal? 'a 'b) "y" "n")
```
---
    "n"

### compares vectors elementwise

```scheme
(equal? #(1 2) #(1 2))
```
---
    #t

### different vector elements are not equal

```scheme
(if (equal? #(1 2) #(1 3)) "y" "n")
```
---
    "n"

### different vector lengths are not equal

```scheme
(if (equal? #(1 2) #(1 2 3)) "y" "n")
```
---
    "n"

### vectors nest inside pairs and other vectors

```scheme
(equal? (list #(1 #(2))) (list #(1 #(2))))
```
---
    #t

### includes? finds an equal vector

```scheme
(List includes? #(1 2) (list #(9) #(1 2)))
```
---
    #t

### compares equal symbols

```scheme
(equal? 'a 'a)
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


## truthiness (the two-falsy law)

### nil and #f are the only falsy values

```scheme
(list (if () "t" "f") (if #f "t" "f"))
```
---
    ("f" "f")

### zero is truthy

```scheme
(if 0 "t" "f")
```
---
    "t"

### the empty string is truthy

```scheme
(if "" "t" "f")
```
---
    "t"

### an empty vector is truthy (a real object, not nil)

```scheme
(if (Vector make 0 ()) "t" "f")
```
---
    "t"

### and normalizes failure to #f; or returns () when given nothing truthy

```scheme
(list (and 1 () 3) (or #f ()))
```
---
    (#f ())

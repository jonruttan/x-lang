# @weight 1
## boolean?

### true for #t

```x
(boolean? #t)
```
---
    #t

### true for #f

```x
(boolean? #f)
```
---
    #t

### false for number

```x
(if (boolean? 42) "y" "n")
```
---
    "n"

## default-to

### returns value when non-nil

```x
(Fn default-to 0 42)
```
---
    42

### returns default when nil

```x
(Fn default-to 0 ())
```
---
    0

## until

### iterates until predicate holds

```x
(Fn until (fn (_ x) (> x 10)) (method-ref Num inc) 1)
```
---
    11

## equal?

### compares numbers

```x
(equal? 5 5)
```
---
    #t

### compares different numbers

```x
(if (equal? 5 6) "y" "n")
```
---
    "n"

### compares strings

```x
(equal? "hi" "hi")
```
---
    #t

### compares nil

```x
(equal? () ())
```
---
    #t

### compares different symbols

```x
(if (equal? 'a 'b) "y" "n")
```
---
    "n"

### compares vectors elementwise

```x
(equal? #(1 2) #(1 2))
```
---
    #t

### different vector elements are not equal

```x
(if (equal? #(1 2) #(1 3)) "y" "n")
```
---
    "n"

### different vector lengths are not equal

```x
(if (equal? #(1 2) #(1 2 3)) "y" "n")
```
---
    "n"

### vectors nest inside pairs and other vectors

```x
(equal? (list #(1 #(2))) (list #(1 #(2))))
```
---
    #t

### includes? finds an equal vector

```x
(List includes? #(1 2) (list #(9) #(1 2)))
```
---
    #t

### compares equal symbols

```x
(equal? 'a 'a)
```
---
    #t

### compares different strings

```x
(if (equal? "foo" "bar") "y" "n")
```
---
    "n"

## until

### returns immediately when predicate holds

```x
(Fn until (fn (_ x) (> x 10)) (method-ref Num inc) 15)
```
---
    15


## truthiness (the two-falsy law)

### nil and #f are the only falsy values

```x
(list (if () "t" "f") (if #f "t" "f"))
```
---
    ("f" "f")

### zero is truthy

```x
(if 0 "t" "f")
```
---
    "t"

### the empty string is truthy

```x
(if "" "t" "f")
```
---
    "t"

### an empty vector is truthy (a real object, not nil)

```x
(if (Vector make 0 ()) "t" "f")
```
---
    "t"

### and normalizes failure to #f; or returns () when given nothing truthy

```x
(list (and 1 () 3) (or #f ()))
```
---
    (#f ())

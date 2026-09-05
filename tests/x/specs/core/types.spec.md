# @weight 1
## make-type

### creates a custom type with call handler

```x
(do (def %counter (Type make "COUNTER" (list (pair 'call (fn (_ self . args) (+ (first self) (first args))))))) (def c (Type make-instance %counter 10)) (c 5))
```
---
    15

### creates a custom type with write handler

```x
(do (def %tag (Type make "TAG" (list (pair 'write (fn (_ self) (display "<") (display (first self)) (display ">")))))) (write (Type make-instance %tag "hello")))
```
---
    <hello>

## make-instance

### stores data accessible via first

```x
(do (def my-t (Type make "MY-T" (list))) (def obj (Type make-instance my-t 42)) (first obj))
```
---
    42

### instance self-evaluates

```x
(do (def my-t (Type make "MY-T" (list))) (def obj (Type make-instance my-t 42)) (eq? obj obj))
```
---
    #t

## type?

### returns #t for matching type

```x
(do (def my-t (Type make "MY-T" (list))) (Type ? (Type make-instance my-t 42) my-t))
```
---
    #t

### returns nil for wrong type

```x
(do (def t1 (Type make "T1" (list))) (def t2 (Type make "T2" (list))) (if (Type ? (Type make-instance t1 1) t2) "y" "n"))
```
---
    "n"

### returns nil for non-instance

```x
(do (def my-t (Type make "MY-T" (list))) (if (Type ? 42 my-t) "y" "n"))
```
---
    "n"

## type-name

### returns VECTOR for a vector

```x
(Type name (Vector of 1))
```
---
    "VECTOR"

### returns LIST for a list

```x
(Type name (list 1 2))
```
---
    "LIST"

### returns INTEGER for a number

```x
(Type name 42)
```
---
    "INTEGER"

### returns STRING for a string

```x
(Type name "hi")
```
---
    "STRING"

### returns custom type name

```x
(do (def my-t (Type make "MY-T" (list))) (Type name (Type make-instance my-t 1)))
```
---
    "MY-T"

## score-match

### sets score length and reader



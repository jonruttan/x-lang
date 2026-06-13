## make-type

### creates a custom type with call handler

```scheme
(do (def %counter (Type make "COUNTER" (list (pair (lit call) (fn (_ self . args) (+ (first self) (first args))))))) (def c (Type make-instance %counter 10)) (c 5))
```
---
    15

### creates a custom type with write handler

```scheme
(do (def %tag (Type make "TAG" (list (pair (lit write) (fn (_ self) (display "<") (display (first self)) (display ">")))))) (write (Type make-instance %tag "hello")))
```
---
    <hello>

## make-instance

### stores data accessible via first

```scheme
(do (def my-t (Type make "MY-T" (list))) (def obj (Type make-instance my-t 42)) (first obj))
```
---
    42

### instance self-evaluates

```scheme
(do (def my-t (Type make "MY-T" (list))) (def obj (Type make-instance my-t 42)) (eq? obj obj))
```
---
    #t

## type?

### returns #t for matching type

```scheme
(do (def my-t (Type make "MY-T" (list))) (Type ? (Type make-instance my-t 42) my-t))
```
---
    #t

### returns nil for wrong type

```scheme
(do (def t1 (Type make "T1" (list))) (def t2 (Type make "T2" (list))) (if (Type ? (Type make-instance t1 1) t2) "y" "n"))
```
---
    "n"

### returns nil for non-instance

```scheme
(do (def my-t (Type make "MY-T" (list))) (if (Type ? 42 my-t) "y" "n"))
```
---
    "n"

## type-name

### returns VECTOR for a vector

```scheme
(Type name (Vector of 1))
```
---
    "VECTOR"

### returns LIST for a list

```scheme
(Type name (list 1 2))
```
---
    "LIST"

### returns INTEGER for a number

```scheme
(Type name 42)
```
---
    "INTEGER"

### returns STRING for a string

```scheme
(Type name "hi")
```
---
    "STRING"

### returns custom type name

```scheme
(do (def my-t (Type make "MY-T" (list))) (Type name (Type make-instance my-t 1)))
```
---
    "MY-T"

## score-match

### sets score length and reader



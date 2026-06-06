# @lib x-base.x

## type-of basics

### returns a handle for integers

```scheme
(not (null? (type-of 42)))
```
---
    #t

### returns a handle for strings

```scheme
(not (null? (type-of "hello")))
```
---
    #t

### returns nil for nil

```scheme
(null? (type-of ()))
```
---
    #t

## type-of equality (same type)

### same type handle for two ints

```scheme
(eq? (type-of 1) (type-of 999))
```
---
    #t

### same type handle for two strings

```scheme
(eq? (type-of "a") (type-of "zzz"))
```
---
    #t

### same type handle for two pairs

```scheme
(do (def a (type-of (pair 1 2))) (def b (type-of (pair 3 4))) (eq? a b))
```
---
    #t

### same type handle for two floats

```scheme
(eq? (type-of 1.0) (type-of 2.5))
```
---
    #t

### same type handle for two booleans

```scheme
(eq? (type-of #t) (type-of #t))
```
---
    #t

### same type handle for two chars

```scheme
(eq? (type-of #\a) (type-of #\z))
```
---
    #t

## type-of inequality (different types)

### int differs from string

```scheme
(not (eq? (type-of 1) (type-of "x")))
```
---
    #t

### int differs from float

```scheme
(not (eq? (type-of 1) (type-of 1.0)))
```
---
    #t

### string differs from pair

```scheme
(do (def a (type-of "x")) (def b (type-of (pair 1 2))) (not (eq? a b)))
```
---
    #t

### int differs from char

```scheme
(not (eq? (type-of 1) (type-of #\a)))
```
---
    #t

### float differs from string

```scheme
(not (eq? (type-of 1.0) (type-of "1.0")))
```
---
    #t

## type-of custom types

### custom type returns a handle

```scheme
(do (def %t (make-type "TEST-T" (list))) (def obj (make-instance %t 1)) (not (null? (type-of obj))))
```
---
    #t

### same custom type returns same handle

```scheme
(do (def %t (make-type "TEST-T" (list))) (def a (make-instance %t 1)) (def b (make-instance %t 2)) (eq? (type-of a) (type-of b)))
```
---
    #t

### different custom types differ

```scheme
(do (def %t1 (make-type "T1" (list))) (def %t2 (make-type "T2" (list))) (not (eq? (type-of (make-instance %t1 1)) (type-of (make-instance %t2 1)))))
```
---
    #t

### custom type differs from int

```scheme
(do (def %t (make-type "TEST-T" (list))) (not (eq? (type-of (make-instance %t 1)) (type-of 42))))
```
---
    #t

## type-of used in convert alist key

### type-of key matches int for int convert

```scheme
(float? (convert 42 %float))
```
---
    #t

### type-of key matches string for float

```scheme
(float? (convert "3.14" %float))
```
---
    #t

## write-to-str

### integer to string

```scheme
(write-to-str 42)
```
---
    "42"

### negative integer to string

```scheme
(write-to-str -7)
```
---
    "-7"

### zero to string

```scheme
(write-to-str 0)
```
---
    "0"

### string to quoted string

```scheme
(write-to-str "hello")
```
---
    "\"hello\""

### symbol to string

```scheme
(write-to-str (lit foo))
```
---
    "(lit foo)"

### boolean to string

```scheme
(write-to-str #t)
```
---
    "#t"

### nil to "()" string

```scheme
(write-to-str ())
```
---
    "()"

### pair to string

```scheme
(write-to-str (pair 1 2))
```
---
    "(1 . 2)"

### list to string

```scheme
(write-to-str (list 1 2 3))
```
---
    "(1 2 3)"

### char to string

```scheme
(write-to-str #\a)
```
---
    "#\\a"

### float to string

```scheme
(write-to-str 3.14)
```
---
    "3.14"

### nested list to string

```scheme
(write-to-str (list (list 1 2) 3))
```
---
    "((1 2) 3)"

### returns a string type

```scheme
(str? (write-to-str 42))
```
---
    #t

## convert nil handling

### convert nil returns nil

```scheme
(null? (convert () %float))
```
---
    #t

### convert nil to custom type returns nil

```scheme
(do (def %t (make-type "CNV-T" (list (pair (lit from) (list (pair (type-of 42) (fn (_ v) (make-instance %t v)))))))) (null? (convert () %t)))
```
---
    #t

## convert short-circuit (already target type)

### float to float is identity

```scheme
(def x 3.14) (eq? (convert x %float) x)
```
---
    #t

### custom type to same type is identity

```scheme
(do (def %t (make-type "ID-T" (list (pair (lit from) (list))))) (def obj (make-instance %t 42)) (eq? (convert obj %t) obj))
```
---
    #t

## convert alist dispatch

### exact match calls converter

```scheme
(convert 42 %float)
```
---
    42

### exact match result has target type

```scheme
(float? (convert 42 %float))
```
---
    #t

### no match returns nil

```scheme
(null? (convert #\a %float))
```
---
    #t

### convert negative int to float

```scheme
(convert -5 %float)
```
---
    -5

### convert zero to float

```scheme
(convert 0 %float)
```
---
    0

### convert zero result is float

```scheme
(float? (convert 0 %float))
```
---
    #t

## convert wildcard t entry

### wildcard matches any type

```scheme
(do (def %t (make-type "WILD-T" (list (pair (lit from) (list (pair #t (fn (_ v) (make-instance %t v)))))))) (type? (convert 42 %t) %t))
```
---
    #t

### wildcard catches string

```scheme
(do (def %t (make-type "WILD-T" (list (pair (lit from) (list (pair #t (fn (_ v) (make-instance %t v)))))))) (type? (convert "hello" %t) %t))
```
---
    #t

### exact match takes priority over wildcard

```scheme
(do (def %t (make-type "PRIO-T" (list (pair (lit from) (list (pair (type-of 42) (fn (_ v) (make-instance %t "exact"))) (pair #t (fn (_ v) (make-instance %t "wild")))))))) (first (convert 42 %t)))
```
---
    "exact"

### wildcard used when no exact match

```scheme
(do (def %t (make-type "PRIO-T" (list (pair (lit from) (list (pair (type-of 42) (fn (_ v) (make-instance %t "exact"))) (pair #t (fn (_ v) (make-instance %t "wild")))))))) (first (convert "hello" %t)))
```
---
    "wild"

## convert with no convert alist

### type with empty convert returns nil

```scheme
(do (def %t (make-type "EMPTY-T" (list (pair (lit from) (list))))) (null? (convert 42 %t)))
```
---
    #t

### type with no convert field returns nil

```scheme
(do (def %t (make-type "NO-CVT" (list))) (null? (convert 42 %t)))
```
---
    #t

## convert multi-type alist

### int converter works

```scheme
(do (def %t (make-type "MULTI-T" (list (pair (lit from) (list (pair (type-of 42) (fn (_ v) (make-instance %t (+ v 100)))) (pair (type-of "") (fn (_ v) (make-instance %t v)))))))) (first (convert 5 %t)))
```
---
    105

### string converter works

```scheme
(do (def %t (make-type "MULTI-T" (list (pair (lit from) (list (pair (type-of 42) (fn (_ v) (make-instance %t (+ v 100)))) (pair (type-of "") (fn (_ v) (make-instance %t v)))))))) (first (convert "hello" %t)))
```
---
    "hello"

### unregistered type returns nil

```scheme
(do (def %t (make-type "MULTI-T" (list (pair (lit from) (list (pair (type-of 42) (fn (_ v) (make-instance %t v)))))))) (null? (convert #\a %t)))
```
---
    #t

## convert string to float

### converts string to float

```scheme
(float? (convert "3.14" %float))
```
---
    #t

### converted string float has correct value

```scheme
(write-to-str (convert "3.14" %float))
```
---
    "3.14"

### converts integer string to float

```scheme
(float? (convert "42" %float))
```
---
    #t

## convert list to vector

### converts list to vector

```scheme
(vector? (convert (list 1 2 3) %vector))
```
---
    #t

### converted vector has correct contents

```scheme
(vector->list (convert (list 1 2 3) %vector))
```
---
    (1 2 3)

### nil returns nil not vector

```scheme
(null? (convert () %vector))
```
---
    #t

## convert outbound (to alist)

### float to int via convert

```scheme
(def x (convert 3.14 (type-of 42))) (integer? x)
```
---
    #t

### float to int value

```scheme
(convert 3.14 (type-of 42))
```
---
    3

### float to string via convert

```scheme
(str? (convert 3.14 (type-of "")))
```
---
    #t

### float to string value

```scheme
(convert 3.14 (type-of ""))
```
---
    "3.14"

### vector to list via convert

```scheme
(convert (vector 1 2 3) (type-of (pair 1 ())))
```
---
    (1 2 3)

### outbound no match returns nil

```scheme
(null? (convert 3.14 (type-of #\a)))
```
---
    #t


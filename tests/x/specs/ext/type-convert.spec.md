# @lib x-base.x
# @weight 3

## type-of basics

### returns a handle for integers

```x
(not (null? (Type of 42)))
```
---
    #t

### returns a handle for strings

```x
(not (null? (Type of "hello")))
```
---
    #t

### returns nil for nil

```x
(null? (Type of ()))
```
---
    #t

## type-of equality (same type)

### same type handle for two ints

```x
(eq? (Type of 1) (Type of 999))
```
---
    #t

### same type handle for two strings

```x
(eq? (Type of "a") (Type of "zzz"))
```
---
    #t

### same type handle for two pairs

```x
(do (def a (Type of (pair 1 2))) (def b (Type of (pair 3 4))) (eq? a b))
```
---
    #t

### same type handle for two floats

```x
(eq? (Type of 1.0) (Type of 2.5))
```
---
    #t

### same type handle for two booleans

```x
(eq? (Type of #t) (Type of #t))
```
---
    #t

### same type handle for two chars

```x
(eq? (Type of #\a) (Type of #\z))
```
---
    #t

## type-of inequality (different types)

### int differs from string

```x
(not (eq? (Type of 1) (Type of "x")))
```
---
    #t

### int differs from float

```x
(not (eq? (Type of 1) (Type of 1.0)))
```
---
    #t

### string differs from pair

```x
(do (def a (Type of "x")) (def b (Type of (pair 1 2))) (not (eq? a b)))
```
---
    #t

### int differs from char

```x
(not (eq? (Type of 1) (Type of #\a)))
```
---
    #t

### float differs from string

```x
(not (eq? (Type of 1.0) (Type of "1.0")))
```
---
    #t

## type-of custom types

### custom type returns a handle

```x
(do (def %t (Type make "TEST-T" (list))) (def obj (Type make-instance %t 1)) (not (null? (Type of obj))))
```
---
    #t

### same custom type returns same handle

```x
(do (def %t (Type make "TEST-T" (list))) (def a (Type make-instance %t 1)) (def b (Type make-instance %t 2)) (eq? (Type of a) (Type of b)))
```
---
    #t

### different custom types differ

```x
(do (def %t1 (Type make "T1" (list))) (def %t2 (Type make "T2" (list))) (not (eq? (Type of (Type make-instance %t1 1)) (Type of (Type make-instance %t2 1)))))
```
---
    #t

### custom type differs from int

```x
(do (def %t (Type make "TEST-T" (list))) (not (eq? (Type of (Type make-instance %t 1)) (Type of 42))))
```
---
    #t

## type-of used in convert alist key

### type-of key matches int for int convert

```x
(Float float? (Convert to 42 %float))
```
---
    #t

### type-of key matches string for float

```x
(Float float? (Convert to "3.14" %float))
```
---
    #t

## write-to-str

### integer to string

```x
(Io write-to-str 42)
```
---
    "42"

### negative integer to string

```x
(Io write-to-str -7)
```
---
    "-7"

### zero to string

```x
(Io write-to-str 0)
```
---
    "0"

### string to quoted string

```x
(Io write-to-str "hello")
```
---
    "\"hello\""

### symbol to string

```x
(Io write-to-str 'foo)
```
---
    "'foo"

### boolean to string

```x
(Io write-to-str #t)
```
---
    "#t"

### nil to "()" string

```x
(Io write-to-str ())
```
---
    "()"

### pair to string

```x
(Io write-to-str (pair 1 2))
```
---
    "(1 . 2)"

### list to string

```x
(Io write-to-str (list 1 2 3))
```
---
    "(1 2 3)"

### char to string

```x
(Io write-to-str #\a)
```
---
    "#\\a"

### float to string

```x
(Io write-to-str 3.14)
```
---
    "3.14"

### nested list to string

```x
(Io write-to-str (list (list 1 2) 3))
```
---
    "((1 2) 3)"

### returns a string type

```x
(str? (Io write-to-str 42))
```
---
    #t

## convert nil handling

### convert nil returns nil

```x
(null? (Convert to () %float))
```
---
    #t

### convert nil to custom type returns nil

```x
(do (def %t (Type make "CNV-T" (list (pair 'from (list (pair (Type of 42) (fn (_ v) (Type make-instance %t v)))))))) (null? (Convert to () %t)))
```
---
    #t

## convert short-circuit (already target type)

### float to float is identity

```x
(def x 3.14) (eq? (Convert to x %float) x)
```
---
    #t

### custom type to same type is identity

```x
(do (def %t (Type make "ID-T" (list (pair 'from (list))))) (def obj (Type make-instance %t 42)) (eq? (Convert to obj %t) obj))
```
---
    #t

## convert alist dispatch

### exact match calls converter

```x
(Convert to 42 %float)
```
---
    42.0

### exact match result has target type

```x
(Float float? (Convert to 42 %float))
```
---
    #t

### no match returns nil (the default miss policy)

```x
(null? (Convert to #\a %float))
```
---
    #t

### the miss policy is the dialect's (the Convert `missing` member)

```x
(do
  (def %saved-cm (Convert missing))
  (Convert missing (fn (_ v t) "missed"))
  (def %cm-r (Convert to #\a %float))
  (Convert missing %saved-cm)
  %cm-r)
```
---
    "missed"

### convert negative int to float

```x
(Convert to -5 %float)
```
---
    -5.0

### convert zero to float

```x
(Convert to 0 %float)
```
---
    0.0

### convert zero result is float

```x
(Float float? (Convert to 0 %float))
```
---
    #t

## convert wildcard t entry

### wildcard matches any type

```x
(do (def %t (Type make "WILD-T" (list (pair 'from (list (pair #t (fn (_ v) (Type make-instance %t v)))))))) (Type ? (Convert to 42 %t) %t))
```
---
    #t

### wildcard catches string

```x
(do (def %t (Type make "WILD-T" (list (pair 'from (list (pair #t (fn (_ v) (Type make-instance %t v)))))))) (Type ? (Convert to "hello" %t) %t))
```
---
    #t

### exact match takes priority over wildcard

```x
(do (def %t (Type make "PRIO-T" (list (pair 'from (list (pair (Type of 42) (fn (_ v) (Type make-instance %t "exact"))) (pair #t (fn (_ v) (Type make-instance %t "wild")))))))) (first (Convert to 42 %t)))
```
---
    "exact"

### wildcard used when no exact match

```x
(do (def %t (Type make "PRIO-T" (list (pair 'from (list (pair (Type of 42) (fn (_ v) (Type make-instance %t "exact"))) (pair #t (fn (_ v) (Type make-instance %t "wild")))))))) (first (Convert to "hello" %t)))
```
---
    "wild"

## convert with no convert alist

### type with empty convert returns nil

```x
(do (def %t (Type make "EMPTY-T" (list (pair 'from (list))))) (null? (Convert to 42 %t)))
```
---
    #t

### type with no convert field returns nil

```x
(do (def %t (Type make "NO-CVT" (list))) (null? (Convert to 42 %t)))
```
---
    #t

## convert multi-type alist

### int converter works

```x
(do (def %t (Type make "MULTI-T" (list (pair 'from (list (pair (Type of 42) (fn (_ v) (Type make-instance %t (+ v 100)))) (pair (Type of "") (fn (_ v) (Type make-instance %t v)))))))) (first (Convert to 5 %t)))
```
---
    105

### string converter works

```x
(do (def %t (Type make "MULTI-T" (list (pair 'from (list (pair (Type of 42) (fn (_ v) (Type make-instance %t (+ v 100)))) (pair (Type of "") (fn (_ v) (Type make-instance %t v)))))))) (first (Convert to "hello" %t)))
```
---
    "hello"

### unregistered type returns nil

```x
(do (def %t (Type make "MULTI-T" (list (pair 'from (list (pair (Type of 42) (fn (_ v) (Type make-instance %t v)))))))) (null? (Convert to #\a %t)))
```
---
    #t

## convert string to float

### converts string to float

```x
(Float float? (Convert to "3.14" %float))
```
---
    #t

### converted string float has correct value

```x
(Io write-to-str (Convert to "3.14" %float))
```
---
    "3.14"

### converts integer string to float

```x
(Float float? (Convert to "42" %float))
```
---
    #t

## convert ptr to string

### copies the C string back (FFI getenv path)

```x
(do (def s "hello") (Convert to (Convert to s %ptr) %string))
```
---
    "hello"

### copy is a new string, not the source

```x
(do (def s "hello") (not (eq? (Convert to (Convert to s %ptr) %string) s)))
```
---
    #t

## convert list to vector

### converts list to vector

```x
(Vector vector? (Convert to (list 1 2 3) %vector))
```
---
    #t

### converted vector has correct contents

```x
(Vector ->list (Convert to (list 1 2 3) %vector))
```
---
    (1 2 3)

### nil returns nil not vector

```x
(null? (Convert to () %vector))
```
---
    #t

## convert outbound (to alist)

### float to int via convert

```x
(def x (Convert to 3.14 (Type of 42))) (Float integer? x)
```
---
    #t

### float to int value

```x
(Convert to 3.14 (Type of 42))
```
---
    3

### float to string via convert

```x
(str? (Convert to 3.14 (Type of "")))
```
---
    #t

### float to string value

```x
(Convert to 3.14 (Type of ""))
```
---
    "3.14"

### vector to list via convert

```x
(Convert to (Vector of 1 2 3) (Type of (pair 1 ())))
```
---
    (1 2 3)

### outbound no match returns nil

```x
(null? (Convert to 3.14 (Type of #\a)))
```
---
    #t


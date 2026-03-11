# @lib x.x

== type-of basics

-- returns a handle for integers
(not (null? (type-of 42)))
---
t

-- returns a handle for strings
(not (null? (type-of "hello")))
---
t

-- returns nil for nil
(null? (type-of ()))
---
t

== type-of equality (same type)

-- same type handle for two ints
(eq? (type-of 1) (type-of 999))
---
t

-- same type handle for two strings
(eq? (type-of "a") (type-of "zzz"))
---
t

-- same type handle for two pairs
(do (def a (type-of (pair 1 2))) (def b (type-of (pair 3 4))) (eq? a b))
---
t

-- same type handle for two floats
(eq? (type-of 1.0) (type-of 2.5))
---
t

-- same type handle for two booleans
(eq? (type-of t) (type-of t))
---
t

-- same type handle for two chars
(eq? (type-of #\a) (type-of #\z))
---
t

== type-of inequality (different types)

-- int differs from string
(null? (eq? (type-of 1) (type-of "x")))
---
t

-- int differs from float
(null? (eq? (type-of 1) (type-of 1.0)))
---
t

-- string differs from pair
(do (def a (type-of "x")) (def b (type-of (pair 1 2))) (null? (eq? a b)))
---
t

-- int differs from char
(null? (eq? (type-of 1) (type-of #\a)))
---
t

-- float differs from string
(null? (eq? (type-of 1.0) (type-of "1.0")))
---
t

== type-of custom types

-- custom type returns a handle
(do (def %t (make-type "TEST-T" (list))) (def obj (make-instance %t 1)) (not (null? (type-of obj))))
---
t

-- same custom type returns same handle
(do (def %t (make-type "TEST-T" (list))) (def a (make-instance %t 1)) (def b (make-instance %t 2)) (eq? (type-of a) (type-of b)))
---
t

-- different custom types differ
(do (def %t1 (make-type "T1" (list))) (def %t2 (make-type "T2" (list))) (null? (eq? (type-of (make-instance %t1 1)) (type-of (make-instance %t2 1)))))
---
t

-- custom type differs from int
(do (def %t (make-type "TEST-T" (list))) (null? (eq? (type-of (make-instance %t 1)) (type-of 42))))
---
t

== type-of used in convert alist key

-- type-of key matches int for int convert
(float? (convert 42 %float))
---
t

-- type-of key matches string for float
(float? (convert "3.14" %float))
---
t

== write-to-string

-- integer to string
(write-to-string 42)
---
"42"

-- negative integer to string
(write-to-string -7)
---
"-7"

-- zero to string
(write-to-string 0)
---
"0"

-- string to quoted string
(write-to-string "hello")
---
"\"hello\""

-- symbol to string
(write-to-string (lit foo))
---
"foo"

-- boolean to string
(write-to-string t)
---
"t"

-- nil to empty string
(write-to-string ())
---
""

-- pair to string
(write-to-string (pair 1 2))
---
"(1 . 2)"

-- list to string
(write-to-string (list 1 2 3))
---
"(1 2 3)"

-- char to string
(write-to-string #\a)
---
"a"

-- float to string
(write-to-string 3.14)
---
"3.14"

-- nested list to string
(write-to-string (list (list 1 2) 3))
---
"((1 2) 3)"

-- returns a string type
(string? (write-to-string 42))
---
t

== convert nil handling

-- convert nil returns nil
(null? (convert () %float))
---
t

-- convert nil to custom type returns nil
(do (def %t (make-type "CNV-T" (list (pair (lit from) (list (pair (type-of 42) (fn (v) (make-instance %t v)))))))) (null? (convert () %t)))
---
t

== convert short-circuit (already target type)

-- float to float is identity
(def x 3.14) (eq? (convert x %float) x)
---
t

-- custom type to same type is identity
(do (def %t (make-type "ID-T" (list (pair (lit from) (list))))) (def obj (make-instance %t 42)) (eq? (convert obj %t) obj))
---
t

== convert alist dispatch

-- exact match calls converter
(convert 42 %float)
---
42

-- exact match result has target type
(float? (convert 42 %float))
---
t

-- no match returns nil
(null? (convert #\a %float))
---
t

-- convert negative int to float
(convert -5 %float)
---
-5

-- convert zero to float
(convert 0 %float)
---
0

-- convert zero result is float
(float? (convert 0 %float))
---
t

== convert wildcard t entry

-- wildcard matches any type
(do (def %t (make-type "WILD-T" (list (pair (lit from) (list (pair t (fn (v) (make-instance %t v)))))))) (type? (convert 42 %t) %t))
---
t

-- wildcard catches string
(do (def %t (make-type "WILD-T" (list (pair (lit from) (list (pair t (fn (v) (make-instance %t v)))))))) (type? (convert "hello" %t) %t))
---
t

-- exact match takes priority over wildcard
(do (def %t (make-type "PRIO-T" (list (pair (lit from) (list (pair (type-of 42) (fn (v) (make-instance %t "exact"))) (pair t (fn (v) (make-instance %t "wild")))))))) (first (convert 42 %t)))
---
"exact"

-- wildcard used when no exact match
(do (def %t (make-type "PRIO-T" (list (pair (lit from) (list (pair (type-of 42) (fn (v) (make-instance %t "exact"))) (pair t (fn (v) (make-instance %t "wild")))))))) (first (convert "hello" %t)))
---
"wild"

== convert with no convert alist

-- type with empty convert returns nil
(do (def %t (make-type "EMPTY-T" (list (pair (lit from) (list))))) (null? (convert 42 %t)))
---
t

-- type with no convert field returns nil
(do (def %t (make-type "NO-CVT" (list))) (null? (convert 42 %t)))
---
t

== convert multi-type alist

-- int converter works
(do (def %t (make-type "MULTI-T" (list (pair (lit from) (list (pair (type-of 42) (fn (v) (make-instance %t (+ v 100)))) (pair (type-of "") (fn (v) (make-instance %t v)))))))) (first (convert 5 %t)))
---
105

-- string converter works
(do (def %t (make-type "MULTI-T" (list (pair (lit from) (list (pair (type-of 42) (fn (v) (make-instance %t (+ v 100)))) (pair (type-of "") (fn (v) (make-instance %t v)))))))) (first (convert "hello" %t)))
---
"hello"

-- unregistered type returns nil
(do (def %t (make-type "MULTI-T" (list (pair (lit from) (list (pair (type-of 42) (fn (v) (make-instance %t v)))))))) (null? (convert #\a %t)))
---
t

== convert string to float

-- converts string to float
(float? (convert "3.14" %float))
---
t

-- converted string float has correct value
(write-to-string (convert "3.14" %float))
---
"3.14"

-- converts integer string to float
(float? (convert "42" %float))
---
t

== convert list to vector

-- converts list to vector
(vector? (convert (list 1 2 3) %vector))
---
t

-- converted vector has correct contents
(vector->list (convert (list 1 2 3) %vector))
---
(1 2 3)

-- nil returns nil not vector
(null? (convert () %vector))
---
t

== convert outbound (to alist)

-- float to int via convert
(def x (convert 3.14 (type-of 42))) (integer? x)
---
t

-- float to int value
(convert 3.14 (type-of 42))
---
3

-- float to string via convert
(string? (convert 3.14 (type-of "")))
---
t

-- float to string value
(convert 3.14 (type-of ""))
---
"3.14"

-- vector to list via convert
(convert (vector 1 2 3) (type-of (pair 1 ())))
---
(1 2 3)

-- outbound no match returns nil
(null? (convert 3.14 (type-of #\a)))
---
t

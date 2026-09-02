# Conformance: the type registry (profile `core`)

The C type-object protocol. x-lang's whole object system -- predicates, the numeric
tower, custom types like BIGINT and RATIONAL -- is built on these four
instructions, so an engine that files types loosely produces a library whose
`pair?` and `str?` answer confidently and wrongly.

### type ? tests a value against a type object

covers: type/?

This is what every predicate in `lib/x/core/predicates.x` is: `(type ? x T)`.

```x
(def %tof (%coord (lit type) (lit of)))
(def %is (%coord (lit type) (lit ?)))
(%ok (match ((%is 1 (%tof 1)) (match ((%is 1 (%tof "s")) ()) (#t 1))) (#t ())))
```
---
    *** ERROR: ok

### distinct kinds of value have distinct type objects

covers: type/of

```x
(def %tof (%coord (lit type) (lit of)))
(%ok (match ((same? (%tof 1) (%tof "s")) ()) (#t (match ((same? (%tof 1) (%tof (pair 1 2))) ()) (#t 1)))))
```
---
    *** ERROR: ok

### a custom type can be made

covers: type/make

`(type make "NAME" methods)` -- the door `lib/x/num/bigint.x` and its siblings use
to add a type the C knows nothing about.

```x
(def %mkt (%coord (lit type) (lit make)))
(def T (%mkt "CONFORM" ()))
(%ok (match ((eq? T ()) ()) (#t 1)))
```
---
    *** ERROR: ok

### an instance of a custom type reports that type

covers: type/make-instance type/of type/?

The property the numeric tower rests on: an instance must be recognisable as its
own type and not as any built-in one.

```x
(def %mkt (%coord (lit type) (lit make)))
(def %mki (%coord (lit type) (lit make-instance)))
(def %tof (%coord (lit type) (lit of)))
(def %is (%coord (lit type) (lit ?)))
(def T (%mkt "CONFORM" ()))
(def v (%mki T (pair 1 2)))
(%ok (match ((same? (%tof v) T) (match ((%is v T) (match ((%is v (%tof 1)) ()) (#t 1))) (#t ()))) (#t ())))
```
---
    *** ERROR: ok

### an instance carries its payload

covers: type/make-instance

```x
(def %mkt (%coord (lit type) (lit make)))
(def %mki (%coord (lit type) (lit make-instance)))
(def T (%mkt "CONFORM" ()))
(def v (%mki T (pair 7 8)))
(%ok (= (first (first v)) 7))
```
---
    *** ERROR: ok

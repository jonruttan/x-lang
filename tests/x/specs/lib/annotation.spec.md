# Annotation: the test of a value against a doc annotation
# @weight 1

An annotation is the type a `(param NAME T ...)` or `(returns T ...)` doc
form states. `(Annotation ? v T)` answers whether `v` is a value `T` names.

## runtime types

### a value satisfies the name of its runtime type

```x
(do (import x/type/annotation)
  (list (Annotation ? 7 'INTEGER) (Annotation ? "a" 'STRING)
        (Annotation ? 'a 'SYMBOL) (Annotation ? #\a 'CHARACTER)
        (Annotation ? #t 'BOOL) (Annotation ? (Vector of 1 2) 'VECTOR)))
```
---
    (#t #t #t #t #t #t)

### and no other runtime type's

```x
(list (Annotation ? "7" 'INTEGER) (Annotation ? 7 'STRING)
      (Annotation ? "a" 'SYMBOL) (Annotation ? (list 1) 'VECTOR))
```
---
    (#f #f #f #f)

### the annotation may be given as a string

```x
(list (Annotation ? 7 "INTEGER") (Annotation ? 7 "STRING"))
```
---
    (#t #f)

## unions

### a value satisfies a union when it satisfies any part

```x
(list (Annotation ? 7 'INTEGER|STRING) (Annotation ? "7" 'INTEGER|STRING)
      (Annotation ? 'x 'INTEGER|STRING) (Annotation ? (list 1) 'VECTOR|LIST|NUMBER))
```
---
    (#t #t #f #t)

## nil

### nil satisfies ANY, NIL, LIST and ALIST

```x
(list (Annotation ? () 'ANY) (Annotation ? () 'NIL)
      (Annotation ? () 'LIST) (Annotation ? () 'ALIST))
```
---
    (#t #t #t #t)

### and no other annotation

```x
(list (Annotation ? () 'STRING) (Annotation ? () 'INTEGER) (Annotation ? () 'PAIR)
      (Annotation ? () 'ATOM) (Annotation ? () 'NUMBER) (Annotation ? () 'CALLABLE)
      (Annotation ? () 'TYPE) (Annotation ? () 'BOOL))
```
---
    (#f #f #f #f #f #f #f #f)

### a union with NIL admits it

```x
(list (Annotation ? () 'STRING|NIL) (Annotation ? "a" 'STRING|NIL) (Annotation ? 7 'STRING|NIL))
```
---
    (#t #t #f)

### NIL is satisfied by nil alone

```x
(list (Annotation ? #f 'NIL) (Annotation ? 0 'NIL) (Annotation ? "" 'NIL))
```
---
    (#f #f #f)

## lists and pairs

### LIST and ALIST take any pair; the elements are not looked at

```x
(list (Annotation ? (list 1 2) 'LIST) (Annotation ? (pair 'a 1) 'LIST)
      (Annotation ? (list 1 2) 'ALIST) (Annotation ? (list (pair 'a 1)) 'ALIST)
      (Annotation ? 7 'LIST) (Annotation ? "ab" 'ALIST))
```
---
    (#t #t #t #t #f #f)

### PAIR is a pair, ATOM a value that is not one

```x
(list (Annotation ? (pair 'a 1) 'PAIR) (Annotation ? (list 1) 'PAIR) (Annotation ? 7 'PAIR)
      (Annotation ? 7 'ATOM) (Annotation ? "a" 'ATOM) (Annotation ? (list 1) 'ATOM))
```
---
    (#t #t #f #t #t #f)

### a pair the engine built is a pair too

A row of the type alist is built by the engine and carries a type the
registry does not hold.

```x
(let ((row (first (Type alist))))
  (list (Annotation ? row 'LIST) (Annotation ? row 'PAIR)
        (Annotation ? row 'STRING) (Annotation ? row 'ATOM) (Annotation ? row 'CALLABLE)))
```
---
    (#t #t #f #f #f)

## the listed names

### ANY is every value

```x
(list (Annotation ? 7 'ANY) (Annotation ? "a" 'ANY) (Annotation ? first 'ANY))
```
---
    (#t #t #t)

### NUMBER is what number? answers for

```x
(list (Annotation ? 7 'NUMBER) (Annotation ? -1 'NUMBER)
      (Annotation ? "7" 'NUMBER) (Annotation ? 'seven 'NUMBER))
```
---
    (#t #t #f #f)

### NUMBER admits a character, INTEGER does not

```x
(list (Annotation ? #\0 'NUMBER) (Annotation ? #\0 'INTEGER)
      (Annotation ? #\0 'CHARACTER))
```
---
    (#t #f #t)

### CALLABLE is a value whose type has a call handler

```x
(list (Annotation ? (fn (_ x) x) 'CALLABLE) (Annotation ? (op (x) e x) 'CALLABLE)
      (Annotation ? first 'CALLABLE) (Annotation ? (list 1 2) 'CALLABLE)
      (Annotation ? "abc" 'CALLABLE) (Annotation ? 7 'CALLABLE))
```
---
    (#t #t #t #t #t #t)

### a symbol and a boolean are not callable

```x
(list (Annotation ? 'first 'CALLABLE) (Annotation ? #t 'CALLABLE) (Annotation ? #f 'CALLABLE))
```
---
    (#f #f #f)

### TYPE is a runtime type's handle

```x
(list (Annotation ? (Type of 7) 'TYPE) (Annotation ? (Type of "a") 'TYPE)
      (Annotation ? 7 'TYPE) (Annotation ? "INTEGER" 'TYPE) (Annotation ? 'INTEGER 'TYPE))
```
---
    (#t #t #f #f #f)

### a type's handle is an atom and satisfies no runtime type's name

```x
(let ((h (Type of 7)))
  (list (Annotation ? h 'ATOM) (Annotation ? h 'INTEGER) (Annotation ? h 'CALLABLE)))
```
---
    (#t #f #f)

## classes

### an instance satisfies its class's name, and OBJECT

```x
(do
  (def-class AnnotationSpecPet ())
  (def-class AnnotationSpecCat (extends AnnotationSpecPet))
  (list (Annotation ? (new AnnotationSpecPet) 'AnnotationSpecPet)
        (Annotation ? (new AnnotationSpecPet) 'OBJECT)
        (Annotation ? 7 'AnnotationSpecPet)
        (Annotation ? 7 'OBJECT)))
```
---
    (#t #t #f #f)

### and the name of a class it descends from, never of one descended from it

```x
(list (Annotation ? (new AnnotationSpecCat) 'AnnotationSpecPet)
      (Annotation ? (new AnnotationSpecPet) 'AnnotationSpecCat)
      (Annotation ? (new AnnotationSpecCat) 'AnnotationSpecCat|STRING))
```
---
    (#t #f #t)

### a class is a CLASS, not an instance of itself

```x
(list (Annotation ? AnnotationSpecPet 'CLASS) (Annotation ? AnnotationSpecPet 'AnnotationSpecPet)
      (Annotation ? (new AnnotationSpecPet) 'CLASS))
```
---
    (#t #f #f)

## names that name nothing

### no value satisfies a name that is neither a runtime type's nor a loaded class's

```x
(list (Annotation ? 7 'NoSuchAnnotationZz) (Annotation ? (new AnnotationSpecPet) 'NoSuchAnnotationZz)
      (Annotation ? "a" 'first))
```
---
    (#f #f #f)

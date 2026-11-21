# Annotation checks

`tools/check/annotation-check.x` puts a form at the head of a documented closure's
body that tests each annotated argument at every call and records the ones
that do not fit. The doctest gate installs it on each module's entries.

## Install and findings

### a call whose arguments fit records nothing

```x
(include "tools/check/annotation-check.x")
(doc (def cc-spec-pair
  (fn (_ (param a INTEGER "The first") (param b INTEGER "The second")) (pair a b)))
  "A pair of two integers.")
(AnnotationCheck install! (list 'cc-spec-pair))
(cc-spec-pair 1 2)
(write (AnnotationCheck found))
```
---
    ()

### an argument that does not fit is recorded and the call still answers

```x
(write (list (cc-spec-pair "a" 2) (AnnotationCheck found)))
```
---
    (("a" . 2) (('cc-spec-pair 'a "INTEGER" "STRING")))

### a parameter is recorded once, however many calls miss it

```x
(cc-spec-pair "b" 2)
(cc-spec-pair "c" #t)
(write (AnnotationCheck found))
```
---
    (('cc-spec-pair 'a "INTEGER" "STRING") ('cc-spec-pair 'b "INTEGER" "BOOL"))

### a rest parameter's annotation is asked of each item

```x
(doc (def cc-spec-count
  (fn (_ . (param items STRING "The items")) (List length items)))
  "How many items.")
(AnnotationCheck install! (list 'cc-spec-count))
(write (list (cc-spec-count "a" "b") (cc-spec-count "a" 7) (List last (AnnotationCheck found))))
```
---
    (2 2 ('cc-spec-count 'items "STRING" "INTEGER"))

### a parameter annotated ANY is not tested

```x
(doc (def cc-spec-any
  (fn (_ (param v ANY "Anything")) v))
  "Its argument.")
(AnnotationCheck install! (list 'cc-spec-any))
(cc-spec-any "a")
(write (List length (AnnotationCheck found)))
```
---
    3

### nothing is tested while the checks are off

```x
(doc (def cc-spec-neg
  (fn (_ (param n INTEGER "A number")) n))
  "Its argument.")
(AnnotationCheck install! (list 'cc-spec-neg))
(AnnotationCheck off!)
(cc-spec-neg "a")
(AnnotationCheck on!)
(write (List length (AnnotationCheck found)))
```
---
    3

### installing twice puts one form in the body

```x
(AnnotationCheck install! (list 'cc-spec-neg))
(cc-spec-neg "a")
(write (List length (AnnotationCheck found)))
```
---
    4

# def-record: lightweight named-field data types
# @weight 1

A record IS a class -- construction, field access, and printing ride the
ordinary object doors -- plus the two methods a data carrier wants:
functional update (`with`, keys quoted: it is a method, so its arguments
evaluate) and structural equality (`=?`, a method by design: `eq?`/`same?`
keep identity semantics).

## construction and access

### positional construction fills fields in order

```x
(do
  (def-record Span start len (colour ()))
  (def s (new Span 3 5))
  (list (s start) (s len) (s colour)))
```
---
    (3 5 ())

### keyword construction and defaults

```x
(do
  (def-record Span start len (colour ()))
  (def s (new Span len 9))
  (list (s start) (s len) (s colour)))
```
---
    (() 9 ())

### fields write in place, like any member

```x
(do
  (def-record Pt x y)
  (def p (new Pt 1 2))
  (p x 10)
  (list (p x) (p y)))
```
---
    (10 2)

## functional update: with

### with copies; the original is untouched

```x
(do
  (def-record Span start len)
  (def s (new Span 3 5))
  (def s2 (s with 'len 9))
  (list (s2 start) (s2 len) (s len)))
```
---
    (3 9 5)

### with takes several replacements

```x
(do
  (def-record Span start len (colour ()))
  (def s2 ((new Span 3 5) with 'len 9 'colour 'red))
  (list (s2 len) (s2 colour)))
```
---
    (9 'red)

### an unknown key fails loudly

```x
(do
  (def-record Span start len)
  (guard (e 'bad-key) ((new Span 3 5) with 'nope 1)))
```
---
    'bad-key

## structural equality: =?

### equal fields, equal records; a changed field differs

```x
(do
  (def-record Pt x y)
  (def p (new Pt 1 2))
  (list (p =? (new Pt 1 2)) (p =? (new Pt 1 3)) (p =? 42)))
```
---
    (#t #f #f)

### records of different classes never compare equal

```x
(do
  (def-record A v)
  (def-record B v)
  ((new A 1) =? (new B 1)))
```
---
    #f

### positional and keyword construction build =? records

```x
(do
  (def-record Pt x y)
  ((new Pt 1 2) =? (new Pt x 1 y 2)))
```
---
    #t

## printing and methods

### the default write dump shows the fields

```x
(do
  (def-record Span start len)
  (guard (e 'no) (write (new Span 3 5))))
```
---
    #<Span start=3 len=5>

### %repr overrides printing, as on any class

```x
(do
  (def-class SpanR ()
    start len
    (method %repr (self) "#<span!>"))
  (write (new SpanR start 1 len 2)))
```
---
    #<span!>

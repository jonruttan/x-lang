# The decimal literal is a module of its own
# @weight 12

`x/num/decimal` is the library: the type, its arithmetic, its conversions
and its printer. It installs no reader syntax. `x/num/decimal/literal`
installs `1.5d` on the base that imports it.

## the library alone

### importing the library leaves the reader as it was

```x
(import x/num/decimal Decimal)
(write (guard (_ #f) (Decimal decimal? (first (Tok read-str (%base) "1.5d ")))))
```
---
    #f

### a decimal is read from text by the library's door

```x
(write (list (Decimal decimal? (Decimal from "1.5")) (Decimal ->str (Decimal from "-0.001"))))
```
---
    (#t "-0.001")

## the literal

### importing the literal module installs it

```x
(import x/num/decimal/literal)
(write (List map (fn (_ v) (Decimal ->str v)) (Tok read-str (%base) "1.5d -0.001d 3d 1.5e-8d ")))
```
---
    ("1.5" "-0.001" "3" "0.000000015")

### a decimal still prints with its suffix, and reads back

```x
(write (list (Decimal from "2.50") (Decimal decimal? (first (Tok read-str (%base) "2.50d ")))))
```
---
    (2.5d #t)

### a run without the suffix is not a decimal

With the float literal installed beside it, the float reader keeps the
token.

```x
(import x/num/float/literal)
(write (List map (fn (_ v) (list (Decimal decimal? v) (Float float? v)))
         (Tok read-str (%base) "1.5 15 ")))
```
---
    ((#f #t) (#f #f))

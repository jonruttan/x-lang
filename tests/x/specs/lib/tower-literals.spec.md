# Each tower literal is a module of its own
# @weight 12

`x/num/bigint`, `x/num/float`, `x/num/rational` and `x/num/complex` are
libraries: the type, its arithmetic, its conversions and its printer.
None installs reader syntax. The literal that writes each one's values is
`x/num/NAME/literal`, which installs it on the base that imports it.

## the libraries alone

### importing the four libraries leaves the reader as it was

```x
(import x/num/bigint)
(import x/num/float)
(import x/num/rational)
(import x/num/complex)
(write (List map (fn (_ s) (Type name (Type of (first (Tok read-str (%base) s)))))
         (list "1.5 " "1/3 " "3+4i " "18446744073709551616 ")))
```
---
    ("INTEGER" "INTEGER" "INTEGER" "INTEGER")

### a float is read from text where no float literal is installed

```x
(write (list (Float from "2.5") (Float from "-3.5e+01") (Float from "3") (Float from " 0.5 ")))
```
---
    (2.5 -35.0 3.0 0.5)

### text that is not one number converts to nothing

```x
(write (List map (fn (_ s) (guard (_ (lit none)) (Float from s)))
         (list "2.5x" "abc" "1 2" "" "1e3" "1/2")))
```
---
    ('none 'none 'none 'none 'none 'none)

### an integer's text of any length converts

```x
(write (Float from "12345678901234567890123"))
```
---
    1.23456789012346e+22

### a rational is converted from text, a long component by the bigint type

```x
(def %tl-cvt (prim-ref (lit convert) (lit to)))
(write (list (%tl-cvt "6/4" (Rational type))
             (%tl-cvt "1/100000000000000000000" (Rational type))))
```
---
    (3/2 1/100000000000000000000)

### a bigint is converted from text

```x
(write (Bigint bigint? ((prim-ref (lit convert) (lit to)) "18446744073709551616" (Bigint type))))
```
---
    #t

## the literals

### importing the float literal installs it

```x
(import x/num/float/literal)
(write (Tok read-str (%base) "1.5 -2.5e3 7 "))
```
---
    (1.5 -2500.0 7)

### importing the rational literal installs it

```x
(import x/num/rational/literal)
(write (Tok read-str (%base) "1/3 -6/4 4/2 "))
```
---
    (1/3 -3/2 2)

### importing the complex literal installs it

```x
(import x/num/complex/literal)
(write (Tok read-str (%base) "3+4i 2i -1-2i "))
```
---
    (3+4i 0+2i -1-2i)

### importing the bigint literal installs it, and a short literal stays an integer

```x
(import x/num/bigint/literal)
(write (List map (fn (_ v) (Bigint bigint? v))
         (Tok read-str (%base) "18446744073709551616 42 ")))
```
---
    (#t #f)

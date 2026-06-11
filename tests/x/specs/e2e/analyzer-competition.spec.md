# @lib x-base.x

## integer vs bignum

### small number stays integer

```scheme
(if (Bignum bignum? 42) "big" "int")
```
---
    "int"

### large number becomes bignum

```scheme
(if (Bignum bignum? 99999999999999999999) "big" "int")
```
---
    "big"

### hex integer

```scheme
(write 0xFF)
```
---
    255

## integer vs float

### integer without dot

```scheme
(if (Float float? 42) "float" "int")
```
---
    "int"

### float with dot

```scheme
(Float float? 1.5)
```
---
    #t

### float zero

```scheme
(Float float? 0.0)
```
---
    #t

## integer vs rational

### bare integer is not rational type

```scheme
(if (type? 42 %rational) "rat" "int")
```
---
    "int"

### slash notation is rational

```scheme
(type? 3/4 %rational)
```
---
    #t

### division in expression is not literal

```scheme
(write (/ 3 4))
```
---
    3/4

## regex literal

### regex does not conflict with division

```scheme
(write #/abc/)
```
---
    #/abc/

### regex vs hash

```scheme
(write #(1 2 3))
```
---
    #(1 2 3)

## mixed expressions

### arithmetic preserves types

```scheme
(do (def a 42) (def b 1.5) (def c 1/3) (Float float? (+ a b)))
```
---
    #t

### chained promotions

```scheme
(do (def x (* 999999999999 999999999999)) (Bignum bignum? x))
```
---
    #t

# @lib x-base.x
# @weight 4

## integer vs bigint

### small number stays integer

```x
(if (Bigint bigint? 42) "big" "int")
```
---
    "int"

### large number becomes bigint

```x
(if (Bigint bigint? 99999999999999999999) "big" "int")
```
---
    "big"

### hex integer

```x
(write 0xFF)
```
---
    255

### hex integer in operand position (#507)

The write form above passed even while the capped analyser awarded
`0xFF` a one-byte span -- the int reader's greedy value parse covered
it, and the stray `xFF` symbol was ignored by the fexpr call. An
operand position evaluates the stray symbol, so this check holds the
analyser to claiming the whole literal.

```x
(+ 0xFF 1)
```
---
    256

### hex at the 64-bit boundary stays int

```x
(if (Bigint bigint? 0x7FFFFFFFFFFFFFFF) "big" "int")
```
---
    "int"

## integer vs float

### integer without dot

```x
(if (Float float? 42) "float" "int")
```
---
    "int"

### float with dot

```x
(Float float? 1.5)
```
---
    #t

### float zero

```x
(Float float? 0.0)
```
---
    #t

## integer vs rational

### bare integer is not rational type

```x
(if (Type ? 42 %rational) "rat" "int")
```
---
    "int"

### slash notation is rational

```x
(Type ? 3/4 %rational)
```
---
    #t

### division in expression is not literal

```x
(write (/ 3 4))
```
---
    3/4

## regex literal

### regex does not conflict with division

```x
(write #/abc/)
```
---
    #/abc/

### regex vs hash

```x
(write #(1 2 3))
```
---
    #(1 2 3)

## mixed expressions

### arithmetic preserves types

```x
(do (def a 42) (def b 1.5) (def c 1/3) (Float float? (+ a b)))
```
---
    #t

### chained promotions

```x
(do (def x (* 999999999999 999999999999)) (Bigint bigint? x))
```
---
    #t

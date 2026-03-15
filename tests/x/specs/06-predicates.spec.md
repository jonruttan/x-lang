## eq?

### returns t for equal symbols

```scheme
(eq? (lit a) (lit a))
```
---
    t

### returns t for eq? on same binding

```scheme
(do (def x 5) (eq? x x))
```
---
    t

## =

### returns t for equal integers

```scheme
(= 3 3)
```
---
    t

### returns nil for unequal integers

```scheme
(= 3 4)
```
---

## <

### returns t for less than

```scheme
(< 1 2)
```
---
    t

### returns nil for equal

```scheme
(< 2 2)
```
---

### returns nil for greater than

```scheme
(< 3 2)
```
---

### handles negative numbers

```scheme
(< -5 0)
```
---
    t

## >

### returns t for greater than

```scheme
(> 3 2)
```
---
    t

### returns nil for equal

```scheme
(> 2 2)
```
---

### returns nil for less than

```scheme
(> 1 2)
```
---

### handles negative numbers

```scheme
(> 0 -5)
```
---
    t

## <=

### returns t for less than

```scheme
(<= 1 2)
```
---
    t

### returns t for equal

```scheme
(<= 2 2)
```
---
    t

### returns nil for greater than

```scheme
(<= 3 2)
```
---

## >=

### returns t for greater than

```scheme
(>= 3 2)
```
---
    t

### returns t for equal

```scheme
(>= 2 2)
```
---
    t

### returns nil for less than

```scheme
(>= 1 2)
```
---

## null?

### returns t for nil

```scheme
(null? (lit ()))
```
---
    t

### returns nil for non-nil

```scheme
(null? 1)
```
---

## pair?

### returns t for a list

```scheme
(pair? (list 1 2))
```
---
    t

### returns t for a pair

```scheme
(pair? (pair 1 2))
```
---
    t

### returns nil for an atom

```scheme
(pair? 42)
```
---

## atom?

### returns t for an integer

```scheme
(atom? 42)
```
---
    t

### returns t for a symbol

```scheme
(atom? (lit a))
```
---
    t

### returns nil for a list

```scheme
(atom? (list 1 2))
```
---

## number?

### true for integer

```scheme
(number? 42)
```
---
    t

### false for string

```scheme
(null? (number? "hello"))
```
---
    t

## string?

### true for string

```scheme
(string? "hello")
```
---
    t

### false for integer

```scheme
(null? (string? 42))
```
---
    t

## symbol?

### true for symbol

```scheme
(symbol? (lit hello))
```
---
    t

### false for integer

```scheme
(null? (symbol? 42))
```
---
    t

## procedure?

### true for fn

```scheme
(procedure? (fn (x) x))
```
---
    t

### true for builtin

```scheme
(procedure? first)
```
---
    t

### false for integer

```scheme
(null? (procedure? 42))
```
---
    t

## char?

### returns nil for number

```scheme
(null? (char? 42))
```
---
    t

### returns nil for string

```scheme
(null? (char? "hello"))
```
---
    t

### returns nil for symbol

```scheme
(null? (char? (lit a)))
```
---
    t

## char->integer

### converts lowercase letter

```scheme
(char->integer #\a)
```
---
    97

### converts uppercase letter

```scheme
(char->integer #\A)
```
---
    65

### converts digit character

```scheme
(char->integer #\0)
```
---
    48

## integer->char

### converts code point to character

```scheme
(integer->char 65)
```
---
    #\A

### round-trips with char->integer

```scheme
(= (char->integer (integer->char 97)) 97)
```
---
    t


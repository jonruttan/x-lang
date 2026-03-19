## eq?

### returns #t for equal symbols

```scheme
(eq? (lit a) (lit a))
```
---
    #t

### returns #t for eq? on same binding

```scheme
(do (def x 5) (eq? x x))
```
---
    #t

## =

### returns #t for equal integers

```scheme
(= 3 3)
```
---
    #t

### returns #f for unequal integers

```scheme
(= 3 4)
```
---
    #f

## <

### returns #t for less than

```scheme
(< 1 2)
```
---
    #t

### returns #f for equal

```scheme
(< 2 2)
```
---
    #f

### returns #f for greater than

```scheme
(< 3 2)
```
---
    #f

### handles negative numbers

```scheme
(< -5 0)
```
---
    #t

## >

### returns #t for greater than

```scheme
(> 3 2)
```
---
    #t

### returns #f for equal

```scheme
(> 2 2)
```
---
    #f

### returns #f for less than

```scheme
(> 1 2)
```
---
    #f

### handles negative numbers

```scheme
(> 0 -5)
```
---
    #t

## <=

### returns #t for less than

```scheme
(<= 1 2)
```
---
    #t

### returns #t for equal

```scheme
(<= 2 2)
```
---
    #t

### returns #f for greater than

```scheme
(<= 3 2)
```
---
    #f

## >=

### returns #t for greater than

```scheme
(>= 3 2)
```
---
    #t

### returns #t for equal

```scheme
(>= 2 2)
```
---
    #t

### returns #f for less than

```scheme
(>= 1 2)
```
---
    #f

## null?

### returns #t for nil

```scheme
(null? (lit ()))
```
---
    #t

### returns #f for non-nil

```scheme
(null? 1)
```
---
    #f

## pair?

### returns #t for a list

```scheme
(pair? (list 1 2))
```
---
    #t

### returns #t for a pair

```scheme
(pair? (pair 1 2))
```
---
    #t

### returns #f for an atom

```scheme
(pair? 42)
```
---
    #f

## atom?

### returns #t for an integer

```scheme
(atom? 42)
```
---
    #t

### returns #t for a symbol

```scheme
(atom? (lit a))
```
---
    #t

### returns #f for a list

```scheme
(atom? (list 1 2))
```
---
    #f

## number?

### true for integer

```scheme
(number? 42)
```
---
    #t

### false for string

```scheme
(number? "hello")
```
---
    #f

## string?

### true for string

```scheme
(string? "hello")
```
---
    #t

### false for integer

```scheme
(string? 42)
```
---
    #f

## symbol?

### true for symbol

```scheme
(symbol? (lit hello))
```
---
    #t

### false for integer

```scheme
(symbol? 42)
```
---
    #f

## procedure?

### true for fn

```scheme
(procedure? (fn (x) x))
```
---
    #t

### true for builtin

```scheme
(procedure? first)
```
---
    #t

### false for integer

```scheme
(procedure? 42)
```
---
    #f

## char?

### returns #t for a character

```scheme
(char? #\a)
```
---
    #t

### returns #f for number

```scheme
(char? 42)
```
---
    #f

### returns #f for string

```scheme
(char? "hello")
```
---
    #f

### returns #f for symbol

```scheme
(char? (lit a))
```
---
    #f

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
    #t


## eq?

### returns #t for equal symbols

```scheme
(eq? 'a 'a)
```
---
    #t

### returns #t for eq? on same binding

```scheme
(do (def x 5) (eq? x x))
```
---
    #t

### value-compares equal integers

```scheme
(eq? 5 5)
```
---
    #t

### distinguishes unequal integers

```scheme
(if (eq? 1 2) "y" "n")
```
---
    "n"

### value-compares equal characters

```scheme
(eq? #\a #\a)
```
---
    #t

### nil and booleans compare equal

```scheme
(list (eq? () ()) (eq? #t #t) (eq? #f #f))
```
---
    (#t #t #t)

### distinct pairs are not eq? (no deep compare)

```scheme
(if (eq? (list 1) (list 1)) "y" "n")
```
---
    "n"

## same?

### identical object is same?

```scheme
(do (def x (list 1)) (same? x x))
```
---
    #t

### interned symbols are same?

```scheme
(same? 'a 'a)
```
---
    #t

### equal integers are NOT same?

```scheme
(if (same? 5 5) "y" "n")
```
---
    "n"

### nil is same? to nil

```scheme
(same? () ())
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
(atom? 'a)
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

## str?

### true for string

```scheme
(str? "hello")
```
---
    #t

### false for integer

```scheme
(str? 42)
```
---
    #f

## symbol?

### true for symbol

```scheme
(symbol? 'hello)
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
(procedure? (fn (_ x) x))
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

### false for an operative

```scheme
(procedure? (op (_ x) x))
```
---
    #f

## operative?

### true for an op

```scheme
(operative? (op (_ x) x))
```
---
    #t

### false for a fn

```scheme
(operative? (fn (_ x) x))
```
---
    #f

### false for a builtin

```scheme
(operative? first)
```
---
    #f

### false for an integer

```scheme
(operative? 42)
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
(char? 'a)
```
---
    #f

## char to integer

### converts lowercase letter

```scheme
(Convert to #\a %int)
```
---
    97

### converts uppercase letter

```scheme
(Convert to #\A %int)
```
---
    65

### converts digit character

```scheme
(Convert to #\0 %int)
```
---
    48

## integer to char

### converts code point to character

```scheme
(Convert to 65 %char)
```
---
    #\A

### round-trips char/integer

```scheme
(= (Convert to (Convert to 97 %char) %int) 97)
```
---
    #t


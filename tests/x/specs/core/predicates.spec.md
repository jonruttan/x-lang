# @weight 1
## eq?

### returns #t for equal symbols

```x
(eq? 'a 'a)
```
---
    #t

### returns #t for eq? on same binding

```x
(do (def x 5) (eq? x x))
```
---
    #t

### value-compares equal integers

```x
(eq? 5 5)
```
---
    #t

### distinguishes unequal integers

```x
(if (eq? 1 2) "y" "n")
```
---
    "n"

### string literals are distinct objects

```x
(if (eq? "a" "a") "y" "n")
```
---
    "n"

### value-compares equal characters

```x
(eq? #\a #\a)
```
---
    #t

### nil and booleans compare equal

```x
(list (eq? () ()) (eq? #t #t) (eq? #f #f))
```
---
    (#t #t #t)

### distinct pairs are not eq? (no deep compare)

```x
(if (eq? (list 1) (list 1)) "y" "n")
```
---
    "n"

## same?

### identical object is same?

```x
(do (def x (list 1)) (same? x x))
```
---
    #t

### interned symbols are same?

```x
(same? 'a 'a)
```
---
    #t

### equal integers are NOT same?

```x
(if (same? 5 5) "y" "n")
```
---
    "n"

### nil is same? to nil

```x
(same? () ())
```
---
    #t

## =

### returns #t for equal integers

```x
(= 3 3)
```
---
    #t

### returns #f for unequal integers

```x
(= 3 4)
```
---
    #f

## <

### returns #t for less than

```x
(< 1 2)
```
---
    #t

### returns #f for equal

```x
(< 2 2)
```
---
    #f

### returns #f for greater than

```x
(< 3 2)
```
---
    #f

### handles negative numbers

```x
(< -5 0)
```
---
    #t

## >

### returns #t for greater than

```x
(> 3 2)
```
---
    #t

### returns #f for equal

```x
(> 2 2)
```
---
    #f

### returns #f for less than

```x
(> 1 2)
```
---
    #f

### handles negative numbers

```x
(> 0 -5)
```
---
    #t

## <=

### returns #t for less than

```x
(<= 1 2)
```
---
    #t

### returns #t for equal

```x
(<= 2 2)
```
---
    #t

### returns #f for greater than

```x
(<= 3 2)
```
---
    #f

## >=

### returns #t for greater than

```x
(>= 3 2)
```
---
    #t

### returns #t for equal

```x
(>= 2 2)
```
---
    #t

### returns #f for less than

```x
(>= 1 2)
```
---
    #f

## null?

### returns #t for nil

```x
(null? (lit ()))
```
---
    #t

### returns #f for non-nil

```x
(null? 1)
```
---
    #f

## pair?

### returns #t for a list

```x
(pair? (list 1 2))
```
---
    #t

### returns #t for a pair

```x
(pair? (pair 1 2))
```
---
    #t

### returns #f for an atom

```x
(pair? 42)
```
---
    #f

## atom?

### returns #t for an integer

```x
(atom? 42)
```
---
    #t

### returns #t for a symbol

```x
(atom? 'a)
```
---
    #t

### returns #f for a list

```x
(atom? (list 1 2))
```
---
    #f

## number?

### true for integer

```x
(number? 42)
```
---
    #t

### false for string

```x
(number? "hello")
```
---
    #f

## str?

### true for string

```x
(str? "hello")
```
---
    #t

### false for integer

```x
(str? 42)
```
---
    #f

## symbol?

### true for symbol

```x
(symbol? 'hello)
```
---
    #t

### false for integer

```x
(symbol? 42)
```
---
    #f

## procedure?

### true for fn

```x
(procedure? (fn (_ x) x))
```
---
    #t

### true for builtin

```x
(procedure? first)
```
---
    #t

### false for integer

```x
(procedure? 42)
```
---
    #f

### false for an operative

```x
(procedure? (op (_ x) x))
```
---
    #f

## operative?

### true for an op

```x
(operative? (op (_ x) x))
```
---
    #t

### false for a fn

```x
(operative? (fn (_ x) x))
```
---
    #f

### false for a builtin

```x
(operative? first)
```
---
    #f

### false for an integer

```x
(operative? 42)
```
---
    #f

## char?

### returns #t for a character

```x
(char? #\a)
```
---
    #t

### returns #f for number

```x
(char? 42)
```
---
    #f

### returns #f for string

```x
(char? "hello")
```
---
    #f

### returns #f for symbol

```x
(char? 'a)
```
---
    #f

## char to integer

### converts lowercase letter

```x
(Convert to #\a %int)
```
---
    97

### converts uppercase letter

```x
(Convert to #\A %int)
```
---
    65

### converts digit character

```x
(Convert to #\0 %int)
```
---
    48

## integer to char

### converts code point to character

```x
(Convert to 65 %char)
```
---
    #\A

### round-trips char/integer

```x
(= (Convert to (Convert to 97 %char) %int) 97)
```
---
    #t


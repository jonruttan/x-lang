## backtick reader

### backtick produces a literal list

```scheme
`(1 2 3)
```
---
    (1 2 3)

### backtick quotes a symbol

```scheme
`foo
```
---
    'foo

### backtick quotes nil

```scheme
`()
```
---

### backtick quotes a nested list

```scheme
`(a (b c) d)
```
---
    ('a ('b 'c) 'd)

### backtick quotes an integer atom

```scheme
`42
```
---
    42

### backtick quotes a string atom

```scheme
`"hello"
```
---
    "hello"

## comma reader

### comma substitutes a variable

```scheme
(do (def x 42) `(a ,x c))
```
---
    ('a 42 'c)

### comma evaluates an expression

```scheme
`(result ,(+ 1 2))
```
---
    ('result 3)

### comma in first position

```scheme
(do (def op (lit +)) `(,op 1 2))
```
---
    ('+ 1 2)

### comma in last position

```scheme
(do (def x 99) `(a b ,x))
```
---
    ('a 'b 99)

### multiple commas

```scheme
(do (def a 1) (def b 2) `(,a ,b))
```
---
    (1 2)

## comma-at reader

### comma-at splices a list

```scheme
(do (def xs (list 2 3)) `(1 ,@xs 4))
```
---
    (1 2 3 4)

### comma-at splices empty list

```scheme
`(a ,@(list) b)
```
---
    ('a 'b)

### comma-at at beginning

```scheme
(do (def xs (list 1 2)) `(,@xs 3))
```
---
    (1 2 3)

### comma-at at end

```scheme
(do (def xs (list 3 4)) `(1 2 ,@xs))
```
---
    (1 2 3 4)

### comma and comma-at mixed

```scheme
(do (def x 1) (def ys (list 2 3)) `(,x ,@ys 4))
```
---
    (1 2 3 4)

## write shorthand

### write outputs backtick for quasi

```scheme
(write (lit (quasi (a (unquote b)))))
```
---
    `('a ,'b)

### write outputs comma-at for splicing

```scheme
(write (lit (quasi (a (unquote-splicing xs)))))
```
---
    `('a ,@'xs)

### write outputs backtick for simple quasi

```scheme
(write (lit (quasi foo)))
```
---
    `'foo

## backward compatibility

### explicit quasi syntax still works

```scheme
(do (def x 42) (quasi (a (unquote x) c)))
```
---
    ('a 42 'c)

### explicit unquote-splicing still works

```scheme
(do (def xs (list 2 3)) (quasi (1 (unquote-splicing xs) 4)))
```
---
    (1 2 3 4)

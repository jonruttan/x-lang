# @weight 1
## backtick reader

### backtick produces a literal list

```x
`(1 2 3)
```
---
    (1 2 3)

### backtick quotes a symbol

```x
`foo
```
---
    'foo

### backtick quotes nil

```x
`()
```
---

### backtick quotes a nested list

```x
`(a (b c) d)
```
---
    ('a ('b 'c) 'd)

### backtick quotes an integer atom

```x
`42
```
---
    42

### backtick quotes a string atom

```x
`"hello"
```
---
    "hello"

## comma reader

### comma substitutes a variable

```x
(do (def x 42) `(a ,x c))
```
---
    ('a 42 'c)

### comma evaluates an expression

```x
`(result ,(+ 1 2))
```
---
    ('result 3)

### comma in first position

```x
(do (def %qq-op (lit +)) `(,%qq-op 1 2))
```
---
    ('+ 1 2)

### comma in last position

```x
(do (def x 99) `(a b ,x))
```
---
    ('a 'b 99)

### multiple commas

```x
(do (def a 1) (def b 2) `(,a ,b))
```
---
    (1 2)

## comma-at reader

### comma-at splices a list

```x
(do (def xs (list 2 3)) `(1 ,@xs 4))
```
---
    (1 2 3 4)

### comma-at splices empty list

```x
`(a ,@(list) b)
```
---
    ('a 'b)

### comma-at at beginning

```x
(do (def xs (list 1 2)) `(,@xs 3))
```
---
    (1 2 3)

### comma-at at end

```x
(do (def xs (list 3 4)) `(1 2 ,@xs))
```
---
    (1 2 3 4)

### comma and comma-at mixed

```x
(do (def x 1) (def ys (list 2 3)) `(,x ,@ys 4))
```
---
    (1 2 3 4)

## write shorthand

### write outputs backtick for quasi

```x
(write (lit (quasi (a (unquote b)))))
```
---
    `('a ,'b)

### write outputs comma-at for splicing

```x
(write (lit (quasi (a (unquote-splicing xs)))))
```
---
    `('a ,@'xs)

### write outputs backtick for simple quasi

```x
(write (lit (quasi foo)))
```
---
    `'foo

## backward compatibility

### explicit quasi syntax still works

```x
(do (def x 42) (quasi (a (unquote x) c)))
```
---
    ('a 42 'c)

### explicit unquote-splicing still works

```x
(do (def xs (list 2 3)) (quasi (1 (unquote-splicing xs) 4)))
```
---
    (1 2 3 4)

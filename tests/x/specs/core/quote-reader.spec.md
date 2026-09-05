# @weight 1
## quote reader

### quote produces a literal list

```x
'(1 2 3)
```
---
    (1 2 3)

### quote quotes a symbol

```x
'foo
```
---
    'foo

### quote quotes nil

```x
'()
```
---

### quote quotes a nested list

```x
'(a (b c) d)
```
---
    ('a ('b 'c) 'd)

### quote quotes an integer atom

```x
'42
```
---
    42

### quote quotes a string atom

```x
'"hello"
```
---
    "hello"

### nested quote

```x
''x
```
---
    ('lit 'x)

## interaction

### quote is the shorthand for lit

```x
(if (eq? 'foo (lit foo)) 1 0)
```
---
    1

### first of a quoted list

```x
(first '(a b c))
```
---
    'a

### a quoted list passed to a function

```x
(List map (fn (_ x) (* x 10)) '(1 2 3))
```
---
    (10 20 30)

### quote terminates an adjacent token

```x
(list 'a'b)
```
---
    ('a 'b)

## backward compatibility

### explicit lit syntax still works

```x
(lit (1 2 3))
```
---
    (1 2 3)

### quasiquote reader still works alongside quote

```x
(do (def x 5) `(a ,x b))
```
---
    ('a 5 'b)

## other readers unaffected

### an apostrophe inside a string is just a character

```x
"it's a string"
```
---
    "it's a string"

### the apostrophe character literal still reads

```x
(Char ->int #\')
```
---
    39

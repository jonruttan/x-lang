## quote reader

### quote produces a literal list

```scheme
'(1 2 3)
```
---
    (1 2 3)

### quote quotes a symbol

```scheme
'foo
```
---
    (lit foo)

### quote quotes nil

```scheme
'()
```
---

### quote quotes a nested list

```scheme
'(a (b c) d)
```
---
    ((lit a) ((lit b) (lit c)) (lit d))

### quote quotes an integer atom

```scheme
'42
```
---
    42

### quote quotes a string atom

```scheme
'"hello"
```
---
    "hello"

### nested quote

```scheme
''x
```
---
    ((lit lit) (lit x))

## interaction

### quote is the shorthand for lit

```scheme
(if (eq? 'foo (lit foo)) 1 0)
```
---
    1

### first of a quoted list

```scheme
(first '(a b c))
```
---
    (lit a)

### a quoted list passed to a function

```scheme
(map (fn (_ x) (* x 10)) '(1 2 3))
```
---
    (10 20 30)

### quote terminates an adjacent token

```scheme
(list 'a'b)
```
---
    ((lit a) (lit b))

## backward compatibility

### explicit lit syntax still works

```scheme
(lit (1 2 3))
```
---
    (1 2 3)

### quasiquote reader still works alongside quote

```scheme
(do (def x 5) `(a ,x b))
```
---
    ((lit a) 5 (lit b))

## other readers unaffected

### an apostrophe inside a string is just a character

```scheme
"it's a string"
```
---
    "it's a string"

### the apostrophe character literal still reads

```scheme
(Char ->int #\')
```
---
    39

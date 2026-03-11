## curly-infix empty

### empty braces produce nil

```scheme
(null? {})
```
---
    t

## curly-infix single

### single element is identity

```scheme
{42}
```
---
    42

### single symbol

```scheme
(define x 10)
{x}
```
---
    10

## curly-infix simple

### addition

```scheme
{1 + 2}
```
---
    3

### multiplication

```scheme
{3 * 4}
```
---
    12

### comparison

```scheme
{5 > 3}
```
---
    t

### subtraction

```scheme
{10 - 3}
```
---
    7

## curly-infix two-element

### unary minus

```scheme
{- 5}
```
---
    -5

### not returns nil

```scheme
(null? {not #t})
```
---
    t

## curly-infix variadic

### same operator folds

```scheme
{1 + 2 + 3}
```
---
    6

### five operands

```scheme
{1 + 2 + 3 + 4 + 5}
```
---
    15

## curly-infix mixed

### mixed ops produce nfx form

```scheme
(write {1 + 2 * 3})
```
---
    ($nfx$ 1 + 2 * 3)

## curly-infix nested

### nested curlies

```scheme
{2 * {3 + 4}}
```
---
    14

### deeply nested

```scheme
{{1 + 2} * {3 + 4}}
```
---
    21

## curly-infix with sexp

### curly inside sexp

```scheme
(if {3 > 2} "yes" "no")
```
---
    "yes"

### sexp inside curly

```scheme
{(+ 1 2) + (+ 3 4)}
```
---
    10


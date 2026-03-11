## indentation single-line

### tokens on one line form a list

```scheme
define x 42
```
---
    42

### function call on one line

```scheme
+ 1 2
```
---
    3

## indentation basic grouping

### indented body becomes child

```scheme
define x
  42
x
```
---
    42

### indented function call

```scheme
define x
  + 1 2
x
```
---
    3

### multiple head tokens with child

```scheme
if #t
  42
```
---
    42

## indentation if expression

### if with two branches

```scheme
if {3 > 2}
  "yes"
  "no"
```
---
    "yes"

### if false branch

```scheme
if {3 < 2}
  "yes"
  "no"
```
---
    "no"

## indentation nested

### two levels of nesting

```scheme
define x
  +
    1
    2
x
```
---
    3

### define with lambda

```scheme
define double
  lambda (n)
    * n 2
double 7
```
---
    14

## indentation factorial

### recursive factorial

```scheme
define factorial
  lambda (n)
    if {n <= 1}
      1
      {n * (factorial {n - 1})}
factorial 5
```
---
    120

## indentation with parens

### parens override indentation

```scheme
(define x
  42)
x
```
---
    42

### sexp inside sweet

```scheme
define x (+ 1 2)
x
```
---
    3

## indentation with curlies

### curly infix in indented position

```scheme
define x
  {3 + 4}
x
```
---
    7

## indentation blank lines

### blank lines between expressions

```scheme
define x 10
x
```
---
    10

## indentation comments

### comment line is transparent

```scheme
define x
  ; this is a comment
  42
x
```
---
    42


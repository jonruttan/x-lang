## if

### true branch

```scheme
(if #t 1 2)
```
---
    1

### false branch

```scheme
(if #f 1 2)
```
---
    2

### no else returns nil

```scheme
(null? (if #f 1))
```
---
    t

### non-boolean truthy

```scheme
(if 42 1 2)
```
---
    1

### nested if

```scheme
(if (> 3 2) (if (< 1 0) (quote a) (quote b)) (quote c))
```
---
    b

### if with expression in test

```scheme
(if (= (+ 1 1) 2) (quote yes) (quote no))
```
---
    yes

## when

### evaluates body when true

```scheme
(when (= 1 1) (+ 10 20))
```
---
    30

### returns nil when false

```scheme
(null? (when (= 1 2) 42))
```
---
    t

### supports multiple body forms

```scheme
(when #t 1 2 3)
```
---
    3

## unless

### evaluates body when false

```scheme
(unless (= 1 2) 99)
```
---
    99

### returns nil when true

```scheme
(null? (unless (= 1 1) 42))
```
---
    t

## cond

### evaluates matching clause

```scheme
(cond ((= 1 2) 10) ((= 1 1) 20) (#t 30))
```
---
    20

### falls through to else

```scheme
(cond ((= 1 2) 10) (#t 99))
```
---
    99

### returns nil when no match

```scheme
(null? (cond (#f 1)))
```
---
    t

## and

### all true returns last

```scheme
(and 1 2 3)
```
---
    3

### short-circuits on false

```scheme
(null? (and 1 #f 3))
```
---
    t

### no args returns true

```scheme
(and)
```
---
    t

### single true arg

```scheme
(and 42)
```
---
    42

## or

### returns first true

```scheme
(or 1 2 3)
```
---
    1

### skips false values

```scheme
(or #f #f 3)
```
---
    3

### no args returns false

```scheme
(null? (or))
```
---
    t

### single false arg

```scheme
(null? (or #f))
```
---
    t

## not

### not true

```scheme
(null? (not #t))
```
---
    t

### not false

```scheme
(not #f)
```
---
    t

### not on non-boolean

```scheme
(null? (not 42))
```
---
    t


## $if

### true branch

```scheme
($if #t 1 2)
```
---
    1

### false branch

```scheme
($if #f 1 2)
```
---
    2

### with expression test

```scheme
($if (> 5 3) "yes" "no")
```
---
    "yes"

## $when

### evaluates body when true

```scheme
($define! x 0) ($when #t ($define! x 42)) x
```
---
    42

### skips body when false

```scheme
($define! x 0) ($when #f ($define! x 42)) x
```
---
    0

## $unless

### evaluates body when false

```scheme
($define! x 0) ($unless #f ($define! x 42)) x
```
---
    42

### skips body when true

```scheme
($define! x 0) ($unless #t ($define! x 42)) x
```
---
    0

## $cond

### matches first true

```scheme
($cond (#f 1) (#t 2) (#t 3))
```
---
    2

### with expressions

```scheme
($define! x 5) ($cond ((> x 10) "big") ((> x 3) "medium") (#t "small"))
```
---
    "medium"


# rn.x smoke (dialect entry points)

End-to-end smoke of the experimental tower dialect launcher (#70).  Its
forms go through the x-lang REPL reader -- the path #49 lived on.  One
file per dialect so the boots schedule in parallel (#320); the family
story is in this directory's README.md.

# @weight 6

# @lib rn.x

## rn.x -- radon, the experimental tower dialect

### multiplication

```scheme
(* 2 3)
```
---
    6

### complex multiplication

```scheme
(* 1+2i 3+4i)
```
---
    -5+10i

### rationals (#49)

```scheme
(+ 1/3 1/6)
```
---
    1/2

### a leading sign no longer crashes the repl reader (#49)

```scheme
(- 5 3)
```
---
    2

### $-interpolation survives the compiled-analyser swap

```scheme
(do (def w 3) $"n={w}/x")
```
---
    "n=3/x"

### Dict is loaded by default (common containers)

```scheme
(do (def d (Dict make)) (d set! (lit k) 1) (d get (lit k)))
```
---
    1

### Set is loaded by default (common containers)

```scheme
((Set of 1 2 2 3) length)
```
---
    3

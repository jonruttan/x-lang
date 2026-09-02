# xe.x smoke (dialect entry points)

End-to-end smoke of the stable tower dialect launcher (#70).  Its forms
go through the x-lang REPL reader -- the path #49 lived on.  One file
per dialect so the boots schedule in parallel (#320); the family story
is in this directory's README.md.

# @weight 6

# @lib xe.x

## xe.x -- xenon, the stable tower dialect

### multiplication

```x
(* 2 3)
```
---
    6

### complex multiplication -- the README's own snippet

```x
(* 1+2i 3+4i)
```
---
    -5+10i

### rationals -- the README's other tower snippet (#49)

Crashed until #49: the compiled rational analyser captured an unrooted
anonymous closure for its sign state, so a collect freed the code the next
leading `+`/`-` jumped into.

```x
(+ 1/3 1/6)
```
---
    1/2

### a leading sign no longer crashes the repl reader (#49)

```x
(- 5 3)
```
---
    2

### signed literals read correctly (#49)

```x
(+ -7 2)
```
---
    -5

### $-interpolation survives the compiled-analyser swap

```x
(do (def w 3) $"n={w}/x")
```
---
    "n=3/x"

### Dict is loaded by default (common containers)

```x
(do (def d (Dict make)) (d set! "k" 1) (d get "k"))
```
---
    1

### Set is loaded by default (common containers)

```x
((Set of 1 2 2 3) length)
```
---
    3

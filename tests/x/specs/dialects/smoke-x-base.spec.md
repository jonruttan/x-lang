# x-base.x smoke (dialect entry points)

End-to-end smoke of the tower base entry (#70).  `x-base.x` has no
`(repl)`, so these forms reach the C read-eval loop -- the path the
dialect entries do NOT take.  One file per dialect so the boots schedule
in parallel (#320); the family story is in this directory's README.md.

# @weight 4

# @lib x-base.x

## x-base.x -- the tower, no repl

### rationals

```x
(+ 1/3 1/6)
```
---
    1/2

### complex

```x
(* 1+2i 3+4i)
```
---
    -5+10i

### integers still work

```x
(* 2 3)
```
---
    6

### $-interpolation survives the compiled-analyser swap

```x
(do (def w 3) $"n={w}/x")
```
---
    "n=3/x"

# x.x smoke (dialect entry points)

End-to-end smoke of the default pointer `x.x` (bare `sh x.sh` boots
helium through it), exactly as the README documents it (#70).  One file
per dialect so the boots schedule in parallel (#320); the family story
is in this directory's README.md.

# @lib x.x

## x.x -- the default pointer (boots helium)

### arithmetic through the pointer

```scheme
(+ 2 3)
```
---
    5

### the standard library is loaded through the pointer

```scheme
(List length (list 1 2 3))
```
---
    3

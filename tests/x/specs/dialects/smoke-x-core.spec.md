# x-core.x smoke (dialect entry points)
# @weight 1

End-to-end smoke of the bare core library entry (#70).  One file per
dialect so the boots schedule in parallel (#320); the family story is in
this directory's README.md.

# @lib x-core.x

## x-core.x -- the core library (no tower, no banner)

### arithmetic

```scheme
(+ 2 3)
```
---
    5

### classes are available

```scheme
(List length (list 1 2 3))
```
---
    3

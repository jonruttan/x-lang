# he.x smoke (dialect entry points)

End-to-end smoke of the shipped `he.x` launcher, exactly as the README
documents it (#70).  One file per dialect so the boots schedule in
parallel (#320); the family story is in this directory's README.md.

# @lib he.x

## he.x -- helium, the light dialect

### arithmetic

```scheme
(+ 2 3)
```
---
    5

### the standard library is loaded

```scheme
(List length (list 1 2 3))
```
---
    3

### strings

```scheme
(Str upcase "abc")
```
---
    "ABC"

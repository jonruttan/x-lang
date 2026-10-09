# Crypt
# @weight 2

crypt(3)'s traditional DES password hash, pure x-lang.  Every hash here is
what busybox's `cryptpw -S SALT PASSWORD` answers for the same password and
salt.  A hash is twenty-five DES encryptions, a fifth of a second, so the
file carries a little weight.

## des

### a short password, a salt of letters

```x
(do
  (import x/codec/crypt)
  (display (Crypt des "pw" "ab")))
```
---
    abzlUXK5ed5rs

### eight bytes exactly, and more than eight -- only the first eight count

```x
(do
  (import x/codec/crypt)
  (display (list (Crypt des "password" "Xy") (Crypt des "longerthaneight" "./") (Crypt des "longerth" "./"))))
```
---
    (Xy2PtsPf0839Y ./haKoGjqSo/Y ./haKoGjqSo/Y)

### the salt's characters across crypt's base-64, and the empty password

```x
(do
  (import x/codec/crypt)
  (display (list (Crypt des "x" "zz") (Crypt des "test" "9a") (Crypt des "" "ab"))))
```
---
    (zzXjar5EX/ECI 9aaxEmXjPttFc abmF1QH4PEr.E)

### a salt of fewer than two characters is refused

```x
(do
  (import x/codec/crypt)
  (display (list (guard (e (Err label e)) (Crypt des "pw" "a")) (guard (e (Err label e)) (Crypt des "pw" "")))))
```
---
    (value value)

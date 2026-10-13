# Crypt
# @weight 15
# @timeout-scale 4

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

## md5

### $1$: the salt up to its first $, at most eight characters; any password length

Every hash is busybox's `cryptpw -m md5 PASSWORD SALT`.

```x
(do
  (import x/codec/crypt)
  (write (list (Crypt md5 "pw" "saltsalt") (Crypt md5 "" "abcd") (Crypt md5 "Hello world!" "saltstring")
               (Crypt md5 "a much longer password than eight bytes" "0123456789abcdefXYZ")
               (Crypt md5 "x" "ab$cd") (Crypt md5 "x" "rounds=1000$roundsalt"))))
```
---
    ("$1$saltsalt$6SNdNaZLKst2LlSm7oPPL1" "$1$abcd$CwbBDotm4UoKv5fATTtzT." "$1$saltstri$YMyguxXMBpd2TEZ.vS/3q1" "$1$01234567$gY732/v8cGd0kz4HtZf/C1" "$1$ab$e2KlfqG5YBMTjSz7XF.Eu1" "$1$rounds=1$mQoLoiI6SdN3sfWTuHeXv0")

## sha256

### $5$ at the default 5000 rounds, which the hash does not name

```x
(do
  (import x/codec/crypt)
  (write (Crypt sha256 "pw" "saltsalt")))
```
---
    "$5$saltsalt$0rl.MZtoLLPP3X0Rdl8riRnphIcAXJY27/aOAyK2hB5"

### rounds=N$ named in the hash, held to 1000 at least; the salt up to its first $, at most sixteen characters

```x
(do
  (import x/codec/crypt)
  (write (list (Crypt sha256 "" "rounds=1000$abcd") (Crypt sha256 "Hello world!" "rounds=1000$saltstring")
               (Crypt sha256 "a much longer password than eight bytes" "rounds=1000$0123456789abcdefXYZ")
               (Crypt sha256 "x" "rounds=1000$ab$cd") (Crypt sha256 "x" "rounds=10$abc"))))
```
---
    ("$5$rounds=1000$abcd$OvE6oFZ9uSaS6o9bpkjmpDprXymykXkIQAzPMyVXYi/" "$5$rounds=1000$saltstring$z/y8l95GSjij6uHx2xAJer7YCODLtrhIxItWC13D4g5" "$5$rounds=1000$0123456789abcdef$l2IH4hqTXWtriBLUJLCigrmNT72dcoHke46GvyfBOW9" "$5$rounds=1000$ab$lMxgB9r4O0h7N8Fc22csLTwDjQhj47dburbojE4s.sD" "$5$rounds=1000$abc$UxKib5kobt2BZp/yfOEWbjik.BPMiS9MzbXyO6zXMC0")

## sha512

### $6$ at the default 5000 rounds

```x
(do
  (import x/codec/crypt)
  (write (Crypt sha512 "pw" "saltsalt")))
```
---
    "$6$saltsalt$pauPrmdmG4BTE9h2HPmywiw152IFch6BJCEsaY6D.PLTfpV8sqvXwWdyfsgVgozkYH9B80bAip/08R2BPH2xk/"

### rounds=N$ and the salt, as $5$ takes them

```x
(do
  (import x/codec/crypt)
  (write (list (Crypt sha512 "" "rounds=1000$abcd") (Crypt sha512 "Hello world!" "rounds=1000$saltstring")
               (Crypt sha512 "a much longer password than eight bytes" "rounds=1000$0123456789abcdefXYZ")
               (Crypt sha512 "x" "rounds=1000$ab$cd") (Crypt sha512 "x" "rounds=10$abc"))))
```
---
    ("$6$rounds=1000$abcd$2yt1GyxelqZREONggCckkaFjAfO.fq7xpFvFzkhIB1/Pt1XNZL.Ohdudqvxo7dLBda9tCdTv8ij4g4wwbV78X/" "$6$rounds=1000$saltstring$Zu2Vknok2/f53APfN687ADnzeNBLcsEgTwvcBHMD2./07rZQAt8vsuKVufD15dyZh.LOLB/uZKf6I3GyON4bp/" "$6$rounds=1000$0123456789abcdef$SVifqBT9xNyg92utDhq0L6ytqSgwMYY1LBq7rvo9CorCUlohnfFr0JrTM.g9nPNvdVA0j0mcDWNT9jvjPkLHS1" "$6$rounds=1000$ab$PjG1Vkf5LHNL84dByLtuSYjVz6Hy575FC7tz8wX4DtJ2WMsZQu0/miZCNEiAa8uwa8QG5xPQJgcyUioQ0Ac/G/" "$6$rounds=1000$abc$zaWpAwySRl8PX4W2aEMJwxpN82bCKtDZP0RBdOD6W7BQlilBqAsWnAZuS10iUyJZneS8Ob1gxs1BZkqJi1nTi.")

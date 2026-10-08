# Sha1
# @weight 2

## sha1: FIPS 180-4 vectors

### the empty string

```x
(do
  (import x/codec/sha1)
  (display (Sha1 hex "")))
```
---
    da39a3ee5e6b4b0d3255bfef95601890afd80709

### one block

```x
(do
  (import x/codec/sha1)
  (display (Sha1 hex "abc")))
```
---
    a9993e364706816aba3e25717850c26c9cd0d89d

### 56 bytes forces the padding into a second block

```x
(do
  (import x/codec/sha1)
  (display (Sha1 hex "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")))
```
---
    84983e441c3bd26ebaae4aa1f95129e5e54670f1

### three blocks

```x
(do
  (import x/codec/sha1)
  (display (Sha1 hex (Str8 pad-right 150 #\y "x"))))
```
---
    cc73267d5f4a6519da0e95634e0e424d7e0ca61e

## binary input

### hex-n digests past a NUL, as git's object header needs

A git blob is named by the SHA-1 of `blob 6`, a NUL, then its bytes.

```x
(do
  (import x/codec/sha1)
  (def %s1-set (prim-ref (lit ptr) (lit set!)))
  (def %s1-r ((prim-ref (lit str) (lit make)) 13))
  (def %s1-p ((prim-ref (lit str) (lit ->ptr)) %s1-r))
  ((fn (self i bs)
     (unless (null? bs) (do (%s1-set %s1-p i (first bs) 1) (self (+ i 1) (rest bs)))))
   0 (list 98 108 111 98 32 54 0 104 101 108 108 111 10))
  (display (Sha1 hex-n %s1-r 13)))
```
---
    ce013625030ba8dba906f756967f9e9ca394464a

### hex stops at the first NUL, hex-n does not

```x
(do
  (import x/codec/sha1)
  (def %s1-set (prim-ref (lit ptr) (lit set!)))
  (def %s1-r ((prim-ref (lit str) (lit make)) 5))
  (def %s1-p ((prim-ref (lit str) (lit ->ptr)) %s1-r))
  ((fn (self i bs)
     (unless (null? bs) (do (%s1-set %s1-p i (first bs) 1) (self (+ i 1) (rest bs)))))
   0 (list 65 0 66 0 67))
  (write (list (str=? (Sha1 hex %s1-r) (Sha1 hex "A")) (Sha1 hex-n %s1-r 5))))
```
---
    (#t "5635f81ec946a90d77a52148a185aeb5ac5517cf")

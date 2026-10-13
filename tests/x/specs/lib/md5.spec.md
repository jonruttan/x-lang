# Md5
# @weight 2

The MD5 digest (RFC 1321) in pure x-lang: the suite of test vectors the RFC
itself gives, a digest past a NUL by count, and the raw bytes crypt's $1$
hash reads.

## the RFC 1321 test suite

### the empty string, one letter, three, and a phrase

```x
(do
  (import x/codec/md5)
  (write (list (Md5 hex "") (Md5 hex "a") (Md5 hex "abc") (Md5 hex "message digest"))))
```
---
    ("d41d8cd98f00b204e9800998ecf8427e" "0cc175b9c0f1b6a831c399e269772661" "900150983cd24fb0d6963f7d28e17f72" "f96b697d7cb7938d525a2f31aaf161d0")

### the alphabet, the alphanumerics, and eighty digits -- two blocks

```x
(do
  (import x/codec/md5)
  (write (list (Md5 hex "abcdefghijklmnopqrstuvwxyz")
               (Md5 hex "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
               (Md5 hex "12345678901234567890123456789012345678901234567890123456789012345678901234567890"))))
```
---
    ("c3fcd3d76192e4007dfb496cca67e13b" "d174ab98d277d9f5a5611c2c9f419d9f" "57edf4a22be3c955ac49da2e2107b67a")

## binary input

### hex-n digests past a NUL; bytes-n gives the same digest as raw bytes

```x
(do
  (import x/codec/md5)
  (import x/codec/hex)
  (def %m5-set (prim-ref (lit ptr) (lit set!)))
  (def %m5-ref (prim-ref (lit str) (lit byte-ref)))
  (def %m5-int (prim-ref (lit char) (lit ->int)))
  (def %m5-r ((prim-ref (lit str) (lit make)) 5))
  (def %m5-p ((prim-ref (lit str) (lit ->ptr)) %m5-r))
  ((fn (self i bs)
     (unless (null? bs) (do (%m5-set %m5-p i (first bs) 1) (self (+ i 1) (rest bs)))))
   0 (list 65 0 66 0 67))
  (def %m5-d (Md5 bytes-n %m5-r 5))
  (write (list (Md5 hex-n %m5-r 5)
               (str=? (Hex encode-bytes (List map (fn (_ i) (%m5-int (%m5-ref %m5-d i))) (List range 0 16)))
                      (Md5 hex-n %m5-r 5)))))
```
---
    ("60b460ba736af736293fafe8130d72a3" #t)

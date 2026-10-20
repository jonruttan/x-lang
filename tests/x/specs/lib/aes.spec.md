# AES
# @weight 2

The block cipher of FIPS 197 and its counter mode, pure x-lang.  The
block vectors are FIPS 197's Appendix C, the counter vectors SP 800-38A's
F.5.5; each is also what the system openssl answers for the same key
(`openssl enc -aes-256-ecb -nopad`, `-aes-256-ctr -iv COUNTER`).  Output
is binary, so every case reads it back by its length, through
`Hex encode-bytes`.

## blocks

### C.1, C.2, C.3: one plaintext under 128-, 192- and 256-bit keys

```x
(do
  (import x/codec/hex)
  (import x/codec/aes)
  (def %ae-bref (prim-ref (lit str) (lit byte-ref)))
  (def %ae-c->i (prim-ref (lit char) (lit ->int)))
  (def %ae-hex
    (fn (_ s n)
      (Hex encode-bytes
        ((fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (%ae-c->i (%ae-bref s i)) acc))))
         (- n 1) ()))))
  (def %ae-pt (Hex decode "00112233445566778899aabbccddeeff"))
  (def %ae-key (Hex decode "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"))
  (write (List map (fn (_ size) (%ae-hex (Aes encrypt-block %ae-key size %ae-pt) 16)) (list 16 24 32))))
```
---
    ("69c4e0d86a7b0430d8cdb78070b4c55a" "dda97ca4864cdfe06eaf70a0ec0d7191" "8ea2b7ca516745bfeafc49904b496089")

### a key size the cipher has not is refused

```x
(do
  (import x/codec/aes)
  (write (guard (e (e msg)) (Aes encrypt-block "0123456789abcdef0123" 20 "0123456789abcdef"))))
```
---
    "Aes: the key must be 16, 24 or 32 bytes"

## counter mode

### F.5.5: CTR-AES256, four blocks

```x
(do
  (import x/codec/hex)
  (import x/codec/aes)
  (def %ae-bref (prim-ref (lit str) (lit byte-ref)))
  (def %ae-c->i (prim-ref (lit char) (lit ->int)))
  (def %ae-hex
    (fn (_ s n)
      (Hex encode-bytes
        ((fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (%ae-c->i (%ae-bref s i)) acc))))
         (- n 1) ()))))
  (def %ae-key (Hex decode "603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4"))
  (def %ae-pt (Hex decode "6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e5130c81c46a35ce411e5fbc1191a0a52eff69f2445df4f9b17ad2b417be66c3710"))
  (display (%ae-hex (Aes ctr %ae-key 32 (Hex decode "f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff") %ae-pt 0 64) 64)))
```
---
    601ec313775789a5b7a7f504bbf3d228f443e3ca4d62b59aca84e990cacaf5c52b0930daa23de94ce87017ba2d84988ddfc9c58db67aada613c2dd08457941a6

### the counter carries across all sixteen bytes; a region ending inside a block uses its leading bytes

```x
(do
  (import x/codec/hex)
  (import x/codec/aes)
  (def %ae-bref (prim-ref (lit str) (lit byte-ref)))
  (def %ae-c->i (prim-ref (lit char) (lit ->int)))
  (def %ae-hex
    (fn (_ s n)
      (Hex encode-bytes
        ((fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (%ae-c->i (%ae-bref s i)) acc))))
         (- n 1) ()))))
  (def %ae-key (Hex decode "603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4"))
  (def %ae-pt (Hex decode "6bc1bee22e409f96e93d7e117393172aae2d8a57"))
  (display (%ae-hex (Aes ctr %ae-key 32 (Hex decode "00ffffffffffffffffffffffffffffff") %ae-pt 0 20) 20)))
```
---
    813bbd361ec949ffac3e7c16af842f07cd92c5b9

### one operation encrypts and decrypts

```x
(do
  (import x/codec/aes)
  (def %ae-k (Str8 pad-right 16 #\k ""))
  (def %ae-iv (Str8 pad-right 16 #\i ""))
  (write (Aes ctr %ae-k 16 %ae-iv (Aes ctr %ae-k 16 %ae-iv "the quick brown fox jumps" 0 25) 0 25)))
```
---
    "the quick brown fox jumps"

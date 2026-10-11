# Mont
# @weight 19

Montgomery arithmetic on 26-bit limbs, modulo P-256's prime and P-384's
order.  The operands are random; every expected value is `bc`'s, which
works on whole numbers in hex: a b mod p, a^65537 mod p, and a^-1 mod m
as a^(m-2).  Pure x, the inverses are most of the file's nineteen seconds.

## modulo P-256's prime

### a product, a power and an inverse, through the form and out

```x
(do
  (import x/codec/mont mont-modulus mont-n mont-one mont-bytes mont-number mont-bytes-of mont-below? mont-mul mont-add mont-sub mont-to mont-from mont-pow mont-inv mont-zero? mont-eq?)
  (import x/codec/bytes)
  (def %mo-p (Bytes of-hex "ffffffff00000001000000000000000000000000ffffffffffffffffffffffff"))
  (def %mo-m (mont-modulus (first %mo-p) 0 32))
  (def %mo-in (fn (_ hex) (mont-to %mo-m (mont-number %mo-m (first (Bytes of-hex hex)) 0 32))))
  (def %mo-out (fn (_ v) (Bytes hex (list (mont-bytes-of %mo-m (mont-from %mo-m v)) 0 32))))
  (def %mo-a (%mo-in "17219d9e6e454cf9d79132b4e98772f2e40205e2b43d6fa7104a77b887ee2a33"))
  (def %mo-b (%mo-in "93d224856cacc1f6dbe624d0d37effd5a49d12e7e221e46ae1a100f7693a3422"))
  (def %mo-e (Bytes of-hex "010001"))
  (write (list (%mo-out (mont-mul %mo-m %mo-a %mo-b))
               (%mo-out (mont-pow %mo-m %mo-a (first %mo-e) 0 3))
               (%mo-out (mont-inv %mo-m %mo-a))
               (%mo-out (mont-mul %mo-m %mo-a (mont-inv %mo-m %mo-a))))))
```
---
    ("27c3dd5a8f0d4be5ab2859afd6aee1785381cf5067c04f05caaac9ca15fd9b7d" "683754d6f827613383a3bdad0ff3465fa47ab5030bdb8f33e77ddf9f0e1c2b2d" "e54d4ae400ee6dd74eb256f961523badbd190666d9130ae9c532c817d4d312ae" "0000000000000000000000000000000000000000000000000000000000000001")

### add and sub wrap modulo p; p itself reduces to zero

```x
(do
  (import x/codec/mont mont-modulus mont-n mont-one mont-bytes mont-number mont-bytes-of mont-below? mont-mul mont-add mont-sub mont-to mont-from mont-pow mont-inv mont-zero? mont-eq?)
  (import x/codec/bytes)
  (def %ms-p (Bytes of-hex "ffffffff00000001000000000000000000000000ffffffffffffffffffffffff"))
  (def %ms-m (mont-modulus (first %ms-p) 0 32))
  (def %ms-in (fn (_ hex) (mont-number %ms-m (first (Bytes of-hex hex)) 0 32)))
  (def %ms-hex (fn (_ v) (Bytes hex (list (mont-bytes-of %ms-m v) 0 32))))
  (def %ms-top (%ms-in "ffffffff00000001000000000000000000000000fffffffffffffffffffffffe"))
  (def %ms-two (%ms-in "0000000000000000000000000000000000000000000000000000000000000002"))
  (write (list (%ms-hex (mont-add %ms-m %ms-top %ms-two))
               (%ms-hex (mont-sub %ms-m %ms-two (%ms-in "0000000000000000000000000000000000000000000000000000000000000003")))
               (mont-zero? %ms-m (%ms-in "ffffffff00000001000000000000000000000000ffffffffffffffffffffffff"))
               (mont-below? %ms-m (first %ms-p) 0 32))))
```
---
    ("0000000000000000000000000000000000000000000000000000000000000001" "ffffffff00000001000000000000000000000000fffffffffffffffffffffffe" #t #f)

## modulo P-384's order

### an inverse over fifteen limbs

```x
(do
  (import x/codec/mont mont-modulus mont-n mont-one mont-bytes mont-number mont-bytes-of mont-below? mont-mul mont-add mont-sub mont-to mont-from mont-pow mont-inv mont-zero? mont-eq?)
  (import x/codec/bytes)
  (def %mn-n (Bytes of-hex "ffffffffffffffffffffffffffffffffffffffffffffffffc7634d81f4372ddf581a0db248b0a77aecec196accc52973"))
  (def %mn-m (mont-modulus (first %mn-n) 0 48))
  (def %mn-a (mont-to %mn-m (mont-number %mn-m (first (Bytes of-hex "84880a80cde03a52a0e5f34145420754193686446127fe7a252d7017a4dc3b4a0d713d008779179543a60e009c9937d6")) 0 48)))
  (write (list (mont-n %mn-m)
               (Bytes hex (list (mont-bytes-of %mn-m (mont-from %mn-m (mont-inv %mn-m %mn-a))) 0 48)))))
```
---
    (15 "d2d0622bfbaada19c33ace6ac129af9e19ff14ac13cc14706e835ed6fc11a4bb8a7af7efeaf26b6cdd1ba99b9cd7896d")

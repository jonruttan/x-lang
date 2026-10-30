# GHASH
# @weight 2

GCM's universal hash (NIST SP 800-38D 6.4), pure x-lang.  H is AES's
cipher of the zero block; the values are McGrew and Viega's GCM test
case 2 (H under the zero key, one ciphertext block, no additional data)
and test case 4's, the additional data and the ciphertext both ending
inside a block.  The answer is 16 binary bytes, read back by count.

## the hash

### test cases 2 and 4, and nothing hashed at all

```x
(do
  (import x/codec/hex)
  (import x/codec/ghash)
  (def %gh-bref (prim-ref (lit str) (lit byte-ref)))
  (def %gh-c->i (prim-ref (lit char) (lit ->int)))
  (def %gh-hex
    (fn (_ s n)
      (Hex encode-bytes
        ((fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (%gh-c->i (%gh-bref s i)) acc))))
         (- n 1) ()))))
  (def %gh-h2 (Hex decode "66e94bd4ef8a2c3b884cfa59ca342b2e"))
  (def %gh-c2 (Hex decode "0388dace60b6a392f328c2b971b2fe78"))
  (def %gh-h4 (Hex decode "b83b533708bf535d0aa6e52980d53b78"))
  (def %gh-a4 (Hex decode "feedfacedeadbeeffeedfacedeadbeefabaddad2"))
  (def %gh-c4 (Hex decode "42831ec2217774244b7221b784d0d49ce3aa212f2c02a4e035c17e2329aca12e21d514b25466931c7d8f6a5aac84aa051ba30b396a0aac973d58e091"))
  (display (list
    (%gh-hex (Ghash hash %gh-h2 "" 0 0 %gh-c2 0 16) 16)
    (%gh-hex (Ghash hash %gh-h4 %gh-a4 0 20 %gh-c4 0 60) 16)
    (%gh-hex (Ghash hash %gh-h2 "" 0 0 "" 0 0) 16))))
```
---
    (f38cbb1ad69223dcc3457ae5b6b0f885 698e57f70e6ecc7fd9463b7260a9ae5f 00000000000000000000000000000000)

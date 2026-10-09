# Hmac
# @weight 4

HMAC (RFC 2104) over SHA-256, SHA-384 and SHA-512.  The cases are RFC
4231's -- a short key, a key shorter than the tag, a key and message of
repeated bytes, and a key longer than the block, hashed first -- and a
key and message with NULs inside.  Every tag here is also what
`openssl dgst -mac HMAC` answers.  Binary keys are built from hex into a
buffer, since a decoded string's length stops at its first NUL.

## RFC 4231

### test case 1: a 20-byte key, "Hi There"

```x
(do
  (import x/codec/hmac)
  (def %hm1-key ((prim-ref (lit str) (lit make)) 20))
  ((fn (self i) (unless (= i 20) (do ((prim-ref (lit ptr) (lit set!)) ((prim-ref (lit str) (lit ->ptr)) %hm1-key) i 11 1) (self (+ i 1))))) 0)
  (display (Hmac hex (lit sha256) (list %hm1-key 0 20) "Hi There"))
  (newline)
  (display (Hmac hex (lit sha384) (list %hm1-key 0 20) "Hi There"))
  (newline)
  (display (Hmac hex (lit sha512) (list %hm1-key 0 20) "Hi There")))
```
---
```output
b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7
afd03944d84895626b0825f4ab46907f15f9dadbe4101ec682aa034c7cebc59cfaea9ea9076ede7f4af152e8b2fa9cb6
87aa7cdea5ef619d4ff0b4241a1d6cb02379f4e2ce4ec2787ad0b30545e17cdedaa833b7d6b8a702038b274eaea3f4e4be9d914eeb61f1702e696c203a126854
```

### test case 2: a key shorter than the tag

```x
(do
  (import x/codec/hmac)
  (display (Hmac hex (lit sha256) "Jefe" "what do ya want for nothing?"))
  (newline)
  (display (Hmac hex (lit sha384) "Jefe" "what do ya want for nothing?"))
  (newline)
  (display (Hmac hex (lit sha512) "Jefe" "what do ya want for nothing?")))
```
---
```output
5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843
af45d2e376484031617f78d2b58a6b1b9c7ef464f5a01b47e42ec3736322445e8e2240ca5e69e2c78b3239ecfab21649
164b7a7bfcf819e2e395fbe73b56e0a387bd64222e831fd610270cd7ea2505549758bf75c05a994a6d034f65f8f0e6fdcaeab1a34d4a6b4b636e070a38bce737
```

### test case 3: twenty 0xaa, fifty 0xdd

```x
(do
  (import x/codec/hmac)
  (def %hm3-fill (fn (_ n b) (do (def s ((prim-ref (lit str) (lit make)) n)) ((fn (self i) (unless (= i n) (do ((prim-ref (lit ptr) (lit set!)) ((prim-ref (lit str) (lit ->ptr)) s) i b 1) (self (+ i 1))))) 0) s)))
  (def %hm3-key (%hm3-fill 20 170))
  (def %hm3-msg (%hm3-fill 50 221))
  (display (Hmac hex (lit sha256) (list %hm3-key 0 20) (list %hm3-msg 0 50)))
  (newline)
  (display (Hmac hex (lit sha384) (list %hm3-key 0 20) (list %hm3-msg 0 50)))
  (newline)
  (display (Hmac hex (lit sha512) (list %hm3-key 0 20) (list %hm3-msg 0 50))))
```
---
```output
773ea91e36800e46854db8ebd09181a72959098b3ef8c122d9635514ced565fe
88062608d3e6ad8a0aa2ace014c8a86f0aa635d947ac9febe83ef4e55966144b2a5ab39dc13814b94e3ab6e101a34f27
fa73b0089d56a284efb0f0756c890be9b1b5dbdd8ee81a3655f83e33b2279d39bf3e848279a722c806b485a47e67c807b946a337bee8942674278859e13292fb
```

### test case 6: a 131-byte key, longer than the block, is hashed first

```x
(do
  (import x/codec/hmac)
  (def %hm6-key ((prim-ref (lit str) (lit make)) 131))
  ((fn (self i) (unless (= i 131) (do ((prim-ref (lit ptr) (lit set!)) ((prim-ref (lit str) (lit ->ptr)) %hm6-key) i 170 1) (self (+ i 1))))) 0)
  (display (Hmac hex (lit sha256) (list %hm6-key 0 131) "Test Using Larger Than Block-Size Key - Hash Key First"))
  (newline)
  (display (Hmac hex (lit sha384) (list %hm6-key 0 131) "Test Using Larger Than Block-Size Key - Hash Key First"))
  (newline)
  (display (Hmac hex (lit sha512) (list %hm6-key 0 131) "Test Using Larger Than Block-Size Key - Hash Key First")))
```
---
```output
60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54
4ece084485813e9088d2c63a041bc5b44f9ef1012a2b588f3cd11f05033ac4c60c2ef6ab4030fe8296248df163f44952
80b24263c7c1a3ebb71493c1dd7be8b49b46d1f41b4aeec1121b013783f8f3526b56d037e05f2598bd0fd2215d6a1e5295e64f73f63f0aec8b915a985d786598
```

## binary

### NULs in the key and the message are bytes like any other

The key is `61 00 62` after a NUL, the message `00 00 ff 00`, both as
regions of a larger buffer.

```x
(do
  (import x/codec/hmac)
  (def %hmb-s ((prim-ref (lit str) (lit make)) 10))
  ((fn (self i bs) (unless (null? bs) (do ((prim-ref (lit ptr) (lit set!)) ((prim-ref (lit str) (lit ->ptr)) %hmb-s) i (first bs) 1) (self (+ i 1) (rest bs)))))
   0 (list 120 0 97 0 98 0 0 255 0 120))
  (display (Hmac hex (lit sha256) (list %hmb-s 1 4) (list %hmb-s 5 4)))
  (newline)
  (display (Hmac hex (lit sha384) (list %hmb-s 1 4) (list %hmb-s 5 4)))
  (newline)
  (display (Hmac hex (lit sha512) (list %hmb-s 1 4) (list %hmb-s 5 4))))
```
---
```output
4f50d129e0cbe157db47c06f45d4531fe24c4e313cb5a218379855ad6b85bb2b
1f64239c967606c079100e70ebc2e05fa942717dea3147a90aa5050bf3d7ac910ef9473306d722cfd1bd1772ece9ba56
e872fd86097d8fd724e9c8d66a0063fb22945429f4b95cb7d5e63b0642db541f250937b6e7e460611b4e5bd1ab4b64dc11e65fa3386d8b874a1f76c7d25ba550
```

### mac answers a buffer of the tag's bytes, digest of joined regions

```x
(do
  (import x/codec/hmac)
  (def %hmd-t (Hmac mac (lit sha384) "Jefe" "what do ya want for nothing?"))
  (write (list (str=? (Hmac to-hex %hmd-t 48) (Hmac hex (lit sha384) "Jefe" "what do ya want for nothing?"))
               (Hmac size (lit sha384)) (Hmac size (lit sha256)) (Hmac size (lit sha512))
               (Hmac to-hex (Hmac digest (lit sha256) "a" (list "xbcx" 1 2)) 32))))
```
---
    (#t 48 32 64 "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")

### an unknown hash is refused

```x
(do
  (import x/codec/hmac)
  (write (guard (e (e msg)) (Hmac mac (lit md5) "k" "m"))))
```
---
    "Hmac: no hash named md5"

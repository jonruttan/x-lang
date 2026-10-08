# ChaCha20
# @weight 2

The stream cipher of RFC 8439, pure x-lang.  The vectors are the RFC's;
each is also what the system openssl answers for the same key and IV
(`openssl enc -chacha20 -K KEY -iv COUNTER+NONCE`).  Output is binary,
so every case reads it back by its length, through `Hex encode-bytes`.

## keystream blocks

### A.1 #1: the zero key and nonce, block 0

```x
(do
  (import x/codec/hex)
  (import x/codec/chacha20)
  (def %cc-bref (prim-ref (lit str) (lit byte-ref)))
  (def %cc-c->i (prim-ref (lit char) (lit ->int)))
  (def %cc-hex
    (fn (_ s n)
      (Hex encode-bytes
        ((fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (%cc-c->i (%cc-bref s i)) acc))))
         (- n 1) ()))))
  (display (%cc-hex (ChaCha20 block (Hex decode (Str8 pad-right 64 #\0 ""))
                                    (Hex decode (Str8 pad-right 32 #\0 "")))
                    64)))
```
---
    76b8e0ada0f13d90405d6ae55386bd28bdd219b8a08ded1aa836efcc8b770dc7da41597c5157488d7724e03fb8d84a376a43b8f41518a11cc387b669b2ee6586

### A.1 #2: block 1 -- the counter is the IV's first word

```x
(do
  (import x/codec/hex)
  (import x/codec/chacha20)
  (def %cc-bref (prim-ref (lit str) (lit byte-ref)))
  (def %cc-c->i (prim-ref (lit char) (lit ->int)))
  (def %cc-hex
    (fn (_ s n)
      (Hex encode-bytes
        ((fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (%cc-c->i (%cc-bref s i)) acc))))
         (- n 1) ()))))
  (display (%cc-hex (ChaCha20 block (Hex decode (Str8 pad-right 64 #\0 ""))
                                    (Hex decode "01000000000000000000000000000000"))
                    64)))
```
---
    9f07e7be5551387a98ba977c732d080dcb0f29a048e3656912c6533e32ee7aed29b721769ce64e43d57133b074d839d531ed1f28510afb45ace10a1f4b794d6f

### 2.3.2: the RFC's block function test

Key 00..1f, nonce 00:00:00:09:00:00:00:4a:00:00:00:00, counter 1.

```x
(do
  (import x/codec/hex)
  (import x/codec/chacha20)
  (def %cc-bref (prim-ref (lit str) (lit byte-ref)))
  (def %cc-c->i (prim-ref (lit char) (lit ->int)))
  (def %cc-hex
    (fn (_ s n)
      (Hex encode-bytes
        ((fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (%cc-c->i (%cc-bref s i)) acc))))
         (- n 1) ()))))
  (display (%cc-hex (ChaCha20 block
                      (Hex decode "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
                      (Hex decode "01000000000000090000004a00000000"))
                    64)))
```
---
    10f1e7e4d13b5915500fdd1fa32071c4c7d1f4c733c068030422aa9ac3d46c4ed2826446079faa0914c2d705d98b02a2b5129cd1de164eb9cbd083e8a2503c4e

## encryption

### 2.4.2: 114 bytes, two blocks, from counter 1

```x
(do
  (import x/codec/hex)
  (import x/codec/chacha20)
  (def %cc-bref (prim-ref (lit str) (lit byte-ref)))
  (def %cc-c->i (prim-ref (lit char) (lit ->int)))
  (def %cc-hex
    (fn (_ s n)
      (Hex encode-bytes
        ((fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (%cc-c->i (%cc-bref s i)) acc))))
         (- n 1) ()))))
  (def %cc-msg "Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it.")
  (display (%cc-hex (ChaCha20 xor
                      (Hex decode "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
                      (Hex decode "01000000000000000000004a00000000")
                      %cc-msg)
                    114)))
```
---
    6e2e359a2568f98041ba0728dd0d6981e97e7aec1d4360c20a27afccfd9fae0bf91b65c5524733ab8f593dabcd62b3571639d624e65152ab8f530c359f0861d807ca0dbf500d6a6156a38e088a22b65e52bc514d16ccf806818ce91ab77937365af90bbf74a35be6b40b8eedf2785e42874d

### decrypting is the same operation

```x
(do
  (import x/codec/hex)
  (import x/codec/chacha20)
  (def %cc-k (Str8 pad-right 32 #\k ""))
  (def %cc-iv (Str8 pad-right 16 #\i ""))
  (def %cc-c (ChaCha20 xor %cc-k %cc-iv "attack at dawn"))
  (display (list (Hex encode %cc-c) (ChaCha20 xor %cc-k %cc-iv %cc-c 0 14))))
```
---
    (a896db21d4152bc58ab7f08c17c1 attack at dawn)

### a region: START and LENGTH pick the bytes, and the counter starts there

The region's first byte is the keystream's first byte, whatever START is.

```x
(do
  (import x/codec/hex)
  (import x/codec/chacha20)
  (def %cc-k (Str8 pad-right 32 #\k ""))
  (def %cc-iv (Str8 pad-right 16 #\i ""))
  (display (list (Hex encode (ChaCha20 xor %cc-k %cc-iv "xxabcxx" 2 3))
                 (Hex encode (ChaCha20 xor %cc-k %cc-iv "abc")))))
```
---
    (a880cc a880cc)

### the openssh nonce shape: a 64-bit counter then a 64-bit nonce

chacha20-poly1305@openssh.com runs the original cipher with the packet
sequence number as an eight-byte nonce; the IV is the same sixteen bytes
read as two 64-bit little-endian words, so block 2^32 carries into word
13.  A counter of 2^32 - 1 followed by one more block is the carry.

```x
(do
  (import x/codec/hex)
  (import x/codec/chacha20)
  (def %cc-bref (prim-ref (lit str) (lit byte-ref)))
  (def %cc-c->i (prim-ref (lit char) (lit ->int)))
  (def %cc-hex
    (fn (_ s n)
      (Hex encode-bytes
        ((fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (%cc-c->i (%cc-bref s i)) acc))))
         (- n 1) ()))))
  (def %cc-k (Str8 pad-right 32 #\k ""))
  (def %cc-in (Str8 pad-right 128 #\q ""))
  ; two blocks from counter ffffffff: the second is block 1_00000000
  (def %cc-two (ChaCha20 xor %cc-k (Hex decode "ffffffff000000000000000000000000") %cc-in))
  ; one block from the carried counter, directly
  (def %cc-one (ChaCha20 xor %cc-k (Hex decode "00000000010000000000000000000000") %cc-in 0 64))
  (display (str=? (%cc-hex %cc-two 128)
                  (Str8 append (%cc-hex (ChaCha20 xor %cc-k (Hex decode "ffffffff000000000000000000000000") %cc-in 0 64) 64)
                               (%cc-hex %cc-one 64)))))
```
---
    #t

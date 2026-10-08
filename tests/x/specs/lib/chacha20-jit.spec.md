# ChaCha20 JIT engine

# @weight 15
# @timeout-scale 4

The compiled block engine behind `(ChaCha20 jit!)`, built by
x/codec/chacha20-jit: one function that enters on a sentinel, runs a
double round a call, and on the tenth sums the state in, XORs the block
into the output and carries the counter.  It is adopted only after the
maker's own differential check against the pure-x cipher; these cases
re-prove agreement through the class.  The file builds an engine, so it
carries the weight of one.

## the engine builds and is adopted

### jit! reports the engine active, and is idempotent

```x
(do
  (import x/codec/chacha20)
  (display (list (ChaCha20 jit!) (ChaCha20 jit!) ((Compiled named (lit chacha20)) state))))
```
---
    (#t #t compiled)

### the RFC vectors hold through the engine

```x
(do
  (import x/codec/hex)
  (import x/codec/chacha20)
  (ChaCha20 jit!)
  (def %cc-bref (prim-ref (lit str) (lit byte-ref)))
  (def %cc-c->i (prim-ref (lit char) (lit ->int)))
  (def %cc-hex
    (fn (_ s n)
      (Hex encode-bytes
        ((fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (%cc-c->i (%cc-bref s i)) acc))))
         (- n 1) ()))))
  (def %cc-msg "Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it.")
  (display (%cc-hex (ChaCha20 block (Hex decode (Str8 pad-right 64 #\0 ""))
                                    (Hex decode (Str8 pad-right 32 #\0 "")))
                    64))
  (newline)
  (display (%cc-hex (ChaCha20 xor
                      (Hex decode "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
                      (Hex decode "01000000000000000000004a00000000")
                      %cc-msg)
                    114)))
```
---
```output
76b8e0ada0f13d90405d6ae55386bd28bdd219b8a08ded1aa836efcc8b770dc7da41597c5157488d7724e03fb8d84a376a43b8f41518a11cc387b669b2ee6586
6e2e359a2568f98041ba0728dd0d6981e97e7aec1d4360c20a27afccfd9fae0bf91b65c5524733ab8f593dabcd62b3571639d624e65152ab8f530c359f0861d807ca0dbf500d6a6156a38e088a22b65e52bc514d16ccf806818ce91ab77937365af90bbf74a35be6b40b8eedf2785e42874d
```

### the engine agrees with pure-x on lengths the vectors do not cover

Every way a region can end: inside the first block (1, 63), on a block
boundary (64), one byte into the next (65), in a later block (200), and
past the on-its-own threshold (5000), where xor builds the engine itself.
The pure-x side is the module's own cipher, read through its environment.

```x
(do
  (import x/codec/hex)
  (import x/codec/chacha20)
  (ChaCha20 jit!)
  (def %cc-bref (prim-ref (lit str) (lit byte-ref)))
  (def %cc-c->i (prim-ref (lit char) (lit ->int)))
  (def %cc-hex
    (fn (_ s n)
      (Hex encode-bytes
        ((fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (%cc-c->i (%cc-bref s i)) acc))))
         (- n 1) ()))))
  (def %cc-ref (eval (lit %xor-bytes) (module x/codec/chacha20)))
  (def %cc-st (eval (lit %state) (module x/codec/chacha20)))
  (def %cc-k (Hex decode "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"))
  (def %cc-iv (Hex decode "01000000000000090000004a00000000"))
  (def %cc-in (Str8 pad-right 5000 #\q "z"))
  (def %cc-agree
    (fn (_ n)
      (str=? (%cc-hex (ChaCha20 xor %cc-k %cc-iv %cc-in 0 n) n)
             (%cc-hex (%cc-ref (%cc-st %cc-k %cc-iv) %cc-in 0 n) n))))
  (display (list (%cc-agree 1) (%cc-agree 63) (%cc-agree 64) (%cc-agree 65) (%cc-agree 200) (%cc-agree 5000))))
```
---
    (#t #t #t #t #t #t)

### binary input: every byte value, NULs included, through the engine

The region is bytes 0..255 repeated; the engine and pure-x must agree
on all of it, and the output's length is the region's.

```x
(do
  (import x/codec/hex)
  (import x/codec/chacha20)
  (ChaCha20 jit!)
  (def %cc-bref (prim-ref (lit str) (lit byte-ref)))
  (def %cc-c->i (prim-ref (lit char) (lit ->int)))
  (def %cc-set (prim-ref (lit ptr) (lit set!)))
  (def %cc-hex
    (fn (_ s n)
      (Hex encode-bytes
        ((fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (%cc-c->i (%cc-bref s i)) acc))))
         (- n 1) ()))))
  (def %cc-ref (eval (lit %xor-bytes) (module x/codec/chacha20)))
  (def %cc-st (eval (lit %state) (module x/codec/chacha20)))
  (def %cc-k (Str8 pad-right 32 #\k ""))
  (def %cc-iv (Str8 pad-right 16 #\i ""))
  (def %cc-in ((prim-ref (lit str) (lit make)) 1000))
  (def %cc-p ((prim-ref (lit str) (lit ->ptr)) %cc-in))
  ((fn (self i) (unless (= i 1000) (do (%cc-set %cc-p i (& i 255) 1) (self (+ i 1))))) 0)
  (def %cc-out (ChaCha20 xor %cc-k %cc-iv %cc-in 0 1000))
  (def %cc-back (ChaCha20 xor %cc-k %cc-iv %cc-out 0 1000))
  (display (list (str=? (%cc-hex %cc-out 1000) (%cc-hex (%cc-ref (%cc-st %cc-k %cc-iv) %cc-in 0 1000) 1000))
                 ; decrypting the binary gives the ramp back
                 (%cc-hex %cc-back 8)
                 (str=? (%cc-hex %cc-back 1000) (%cc-hex %cc-in 1000)))))
```
---
    (#t 0001020304050607 #t)

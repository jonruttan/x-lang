# AES JIT engine

# @weight 15
# @timeout-scale 4

The compiled counter mode behind `(Aes jit!)`, built by x/codec/aes-jit:
the T-table rounds, one function taking a round a call and going on to
the next block while the run and the region allow.  It is adopted only
after the maker's own differential check against the pure-x counter
mode; these cases re-prove agreement through the class.  The file builds
an engine, so it carries the weight of one.

## the engine builds and is adopted

### jit! reports the engine active, and is idempotent

```x
(do
  (import x/codec/aes)
  (display (list (Aes jit!) (Aes jit!) ((Compiled named (lit aes)) state))))
```
---
    (#t #t compiled)

### F.5.5 and test case 16 hold through the engine

```x
(do
  (import x/codec/hex)
  (import x/codec/aes)
  (Aes jit!)
  (def %ae-bref (prim-ref (lit str) (lit byte-ref)))
  (def %ae-c->i (prim-ref (lit char) (lit ->int)))
  (def %ae-hex
    (fn (_ s n)
      (Hex encode-bytes
        ((fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (%ae-c->i (%ae-bref s i)) acc))))
         (- n 1) ()))))
  (def %ae-key (Hex decode "603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4"))
  (def %ae-pt (Hex decode "6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e5130c81c46a35ce411e5fbc1191a0a52eff69f2445df4f9b17ad2b417be66c3710"))
  (display (%ae-hex (Aes ctr %ae-key 32 (Hex decode "f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff") %ae-pt 0 64) 64))
  (newline)
  (display
    ((fn (_ r) (list (%ae-hex (first r) 60) (%ae-hex (rest r) 16)))
     (Aes gcm-seal (Hex decode "feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308") 32
       (Hex decode "cafebabefacedbaddecaf888")
       (Hex decode "feedfacedeadbeeffeedfacedeadbeefabaddad2d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39")
       0 20 20 60))))
```
---
```output
601ec313775789a5b7a7f504bbf3d228f443e3ca4d62b59aca84e990cacaf5c52b0930daa23de94ce87017ba2d84988ddfc9c58db67aada613c2dd08457941a6
(522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f662 76fc6ece0f4e1768cddf8853bb2d551b)
```

### the engine agrees with pure-x on every way a region can end

The pure-x side is the module's own counter loop, read through its
environment.  The lengths cover a byte, a block, one over, and a long
region from an odd start; the counter starts where its low bytes carry,
and the three key sizes each take a turn.

```x
(do
  (import x/codec/hex)
  (import x/codec/aes)
  (Aes jit!)
  (def %ae-bref (prim-ref (lit str) (lit byte-ref)))
  (def %ae-c->i (prim-ref (lit char) (lit ->int)))
  (def %ae-hex
    (fn (_ s n)
      (Hex encode-bytes
        ((fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (%ae-c->i (%ae-bref s i)) acc))))
         (- n 1) ()))))
  (def %ae-pure (eval (lit %ctr-bytes) (module x/codec/aes)))
  (def %ae-schedule (eval (lit %schedule) (module x/codec/aes)))
  (def %ae-eng ((Compiled named (lit aes)) compiled))
  (def %ae-ramp
    (fn (_ n from step)
      (def r ((prim-ref (lit str) (lit make)) n))
      (def p ((prim-ref (lit str) (lit ->ptr)) r))
      ((fn (self i) (unless (= i n) (do ((prim-ref (lit ptr) (lit set!)) p i (& (+ from (* i step)) 255) 1) (self (+ i 1))))) 0)
      r))
  (def %ae-in (%ae-ramp 5000 3 97))
  (def %ae-iv (Hex decode "000102030405060708090a0bfffffffe"))
  (def %ae-agree
    (fn (_ size start n)
      (def ks (%ae-schedule (%ae-ramp 32 9 41) size))
      (str=? (%ae-hex (%ae-eng ks %ae-iv %ae-in start n) n)
             (%ae-hex (%ae-pure ks %ae-iv %ae-in start n) n))))
  (display (list (%ae-agree 16 0 1) (%ae-agree 24 0 16) (%ae-agree 32 0 17)
                 (%ae-agree 32 7 4993) (%ae-agree 16 5 1000))))
```
---
    (#t #t #t #t #t)

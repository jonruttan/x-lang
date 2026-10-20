# Mont-jit
# @weight 15
# @timeout-scale 4

The compiled Montgomery engine (x/codec/mont-jit) for P-256's prime and
P-384's order: built, checked against x/codec/mont when it is made, and
here run beside the pure engine -- the same slots and calls over mont.x's
arithmetic -- on the same numbers.  Multiply, add, subtract, copy, the
zero and equality tests, a program and the inverse must all agree.  The
first engine compiles the five functions every engine shares, so the file
carries an engine's weight.

## agreement with the pure engine

### every operation, a program and the inverse, on two moduli

```x
(do
  (import x/codec/bytes)
  (import x/codec/mont mont-modulus mont-number mont-n)
  (import x/codec/mont-jit mont-jit-make mont-jit-pure mont-jit-compiled? mont-jit-load! mont-jit-store
          mont-jit-mul mont-jit-add mont-jit-sub mont-jit-copy! mont-jit-zero? mont-jit-eq? mont-jit-to!
          mont-jit-inv! mont-jit-program mont-jit-run!)
  (def %mjs-run
    (fn (_ e m len)
      (def x (Bytes of-hex (Str8 pad-right (* 2 len) #\7 "")))
      (def y (Bytes of-hex (Str8 pad-right (* 2 len) #\3 "")))
      (mont-jit-load! e 0 (mont-number m (first x) 0 len))
      (mont-jit-load! e 1 (mont-number m (first y) 0 len))
      (mont-jit-to! e 0 0)
      (mont-jit-to! e 1 1)
      (mont-jit-mul e 2 0 1)
      (mont-jit-add e 3 2 0)
      (mont-jit-sub e 4 1 3)
      (mont-jit-run! e (mont-jit-program e (list (list (lit mul) 5 4 4) (list (lit sub) 5 5 2) (list (lit copy) 6 5))))
      (mont-jit-inv! e 7 6)
      (mont-jit-mul e 8 7 6)
      (mont-jit-sub e 9 6 6)
      (def limbs (fn (_ v) ((fn (self i acc) (if (= i 0) acc (self (- i 1) (pair ((prim-ref (lit obj) (lit ref)) v i) acc)))) (mont-n m) ())))
      (list (List map (fn (_ k) (limbs (mont-jit-store e k))) (list 2 3 4 5 6 7 8))
            (mont-jit-zero? e 9) (mont-jit-zero? e 8) (mont-jit-eq? e 5 6) (mont-jit-eq? e 4 5))))
  (def %mjs-same
    (fn (_ hex len)
      (def r (Bytes of-hex hex))
      (def m (mont-modulus (first r) 0 len))
      (def c (mont-jit-make m))
      (def a (%mjs-run c m len))
      (def b (%mjs-run (mont-jit-pure m) m len))
      (list (mont-jit-compiled? c) (equal? (first a) (first b)) (rest a))))
  (write (list (%mjs-same "ffffffff00000001000000000000000000000000ffffffffffffffffffffffff" 32)
               (%mjs-same "ffffffffffffffffffffffffffffffffffffffffffffffffc7634d81f4372ddf581a0db248b0a77aecec196accc52973" 48))))
```
---
    ((#t #t (#t #f #t #f)) (#t #t (#t #f #t #f)))

## an RSA modulus

### a 2048-bit modulus: every operation but the inverse, against the pure engine

The same five functions serve seventy-nine limbs, the byte doors among
them.  The inverse is left out: the pure engine's would take two thousand
of its multiplies.

```x
(do
  (import x/codec/bytes)
  (import x/codec/mont mont-modulus mont-number mont-n)
  (import x/codec/mont-jit mont-jit-make mont-jit-pure mont-jit-compiled? mont-jit-load! mont-jit-store
          mont-jit-load-bytes! mont-jit-store-bytes
          mont-jit-mul mont-jit-add mont-jit-sub mont-jit-copy! mont-jit-zero? mont-jit-eq? mont-jit-to! mont-jit-from!
          mont-jit-program mont-jit-run!)
  (def %mjl-run
    (fn (_ e m len)
      (def x (Bytes of-hex (Str8 pad-right (* 2 len) #\7 "")))
      (def y (Bytes of-hex (Str8 pad-right (* 2 len) #\3 "")))
      ; x in through the byte door, y through a limb vector
      (mont-jit-load-bytes! e 0 (first x) 0 len)
      (mont-jit-load! e 1 (mont-number m (first y) 0 len))
      (mont-jit-to! e 0 0)
      (mont-jit-to! e 1 1)
      (mont-jit-mul e 2 0 1)
      (mont-jit-add e 3 2 0)
      (mont-jit-sub e 4 1 3)
      (mont-jit-run! e (mont-jit-program e (list (list (lit mul) 5 4 4) (list (lit sub) 5 5 2) (list (lit copy) 6 5))))
      (mont-jit-from! e 7 6)
      (mont-jit-sub e 8 6 6)
      (def limbs (fn (_ v) ((fn (self i acc) (if (= i 0) acc (self (- i 1) (pair ((prim-ref (lit obj) (lit ref)) v i) acc)))) (mont-n m) ())))
      (list (list (List map (fn (_ k) (limbs (mont-jit-store e k))) (list 2 3 4 5 6 7))
                  (Bytes hex (list (mont-jit-store-bytes e 7) 0 len)))
            (mont-jit-zero? e 8) (mont-jit-zero? e 7) (mont-jit-eq? e 5 6) (mont-jit-eq? e 4 5))))
  (def %mjl-r (Bytes of-hex "aa54ba0b4cb8044c63065f6d657dd178ccc247acff7c095803e784b5fd8fee2eb0fd26f5cfbf5c072a8662b5fa2d53f1fa9d266060c6b4b4d461ed0af452390c9a36ef6e7df3b47644118c906216f5bd091549f8683e00112847c7e15a4e815695002deb15c1569984970865fa99c30743c6f8303e24834d4cc91713f5c16fbb0c84029dbcebcd6e95f175eb997f413185a0a681643e0b6646ca4711a21f59e6b87d157ed56866c70aff35908b234f66dc2aee57e6ef0f9e4b85363323d32bbf37b77f85feaf9bcefe0ba3bad005c7beea5949169d0b161cb65e777d9ec6ade3b0cb382b4c8b847b9ec4df0d991cfc69c189f43e5f9f0bf9a6345e772ee37331"))
  (def %mjl-m (mont-modulus (first %mjl-r) 0 256))
  (def %mjl-c (mont-jit-make %mjl-m))
  (def %mjl-a (%mjl-run %mjl-c %mjl-m 256))
  (def %mjl-b (%mjl-run (mont-jit-pure %mjl-m) %mjl-m 256))
  (write (list (mont-jit-compiled? %mjl-c) (equal? (first %mjl-a) (first %mjl-b)) (rest %mjl-a) (rest %mjl-b))))
```
---
    (#t #t (#t #f #t #f) (#t #f #t #f))

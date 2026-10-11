# Mont-jit
# @weight 15
# @timeout-scale 4

The compiled Montgomery engine (x/codec/mont-jit) for P-256's prime and
P-384's order: built, checked against x/codec/mont when it is made, and
here run beside the pure engine -- the same slots and calls over mont.x's
arithmetic -- on the same numbers.  Multiply, add, subtract, copy, the
zero and equality tests, a program and the inverse must all agree.  The
file builds two engines, so it carries an engine's weight.

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

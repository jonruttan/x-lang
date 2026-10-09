# Hkdf
# @weight 4

HKDF (RFC 5869): Extract and Expand over HMAC.  The cases are the RFC's
own A.1 and A.3 for SHA-256 -- a salt and context, then neither -- and a
SHA-384 expansion of 100 bytes, more than two of its blocks, with NULs in
every input.  Every output here is also what `openssl kdf HKDF` answers.

## RFC 5869

### A.1: the pseudorandom key and 42 bytes

```x
(do
  (import x/codec/hkdf)
  (import x/codec/hmac)
  (def %hk-of (fn (_ bs) (do (def s ((prim-ref (lit str) (lit make)) (List length bs))) ((fn (self i l) (unless (null? l) (do ((prim-ref (lit ptr) (lit set!)) ((prim-ref (lit str) (lit ->ptr)) s) i (first l) 1) (self (+ i 1) (rest l))))) 0 bs) s)))
  (def %hk1-ikm (%hk-of (List repeat 22 11)))
  (def %hk1-salt (%hk-of (list 0 1 2 3 4 5 6 7 8 9 10 11 12)))
  (def %hk1-info (%hk-of (list 240 241 242 243 244 245 246 247 248 249)))
  (def %hk1-prk (Hkdf extract (lit sha256) (list %hk1-salt 0 13) (list %hk1-ikm 0 22)))
  (display (Hmac to-hex %hk1-prk 32))
  (newline)
  (display (Hmac to-hex (Hkdf expand (lit sha256) %hk1-prk (list %hk1-info 0 10) 42) 42)))
```
---
```output
077709362c2e32df0ddc3f0dc47bba6390b6c73bb50f9c3122ec844ad7c2b3e5
3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865
```

### A.3: an empty salt and an empty context

```x
(do
  (import x/codec/hkdf)
  (import x/codec/hmac)
  (def %hk3-ikm ((prim-ref (lit str) (lit make)) 22))
  ((fn (self i) (unless (= i 22) (do ((prim-ref (lit ptr) (lit set!)) ((prim-ref (lit str) (lit ->ptr)) %hk3-ikm) i 11 1) (self (+ i 1))))) 0)
  (display (Hmac to-hex (Hkdf expand (lit sha256) (Hkdf extract (lit sha256) "" (list %hk3-ikm 0 22)) "" 42) 42)))
```
---
    8da4e775a563c18f715f802a063c5a31b8a11f5c5ee1879ec3454e5f3c738d2d9d201395faa4b61a96c8

## SHA-384

### 100 bytes from three blocks, NULs in the salt and the context

```x
(do
  (import x/codec/hkdf)
  (import x/codec/hmac)
  (def %hk4-of (fn (_ bs) (do (def s ((prim-ref (lit str) (lit make)) (List length bs))) ((fn (self i l) (unless (null? l) (do ((prim-ref (lit ptr) (lit set!)) ((prim-ref (lit str) (lit ->ptr)) s) i (first l) 1) (self (+ i 1) (rest l))))) 0 bs) s)))
  (def %hk4-ikm (%hk4-of (List repeat 22 11)))
  (def %hk4-out (Hkdf expand (lit sha384) (Hkdf extract (lit sha384) (list (%hk4-of (list 0 255 0)) 0 3) (list %hk4-ikm 0 22)) (list (%hk4-of (list 0)) 0 1) 100))
  (display (Hmac to-hex %hk4-out 100)))
```
---
    9450384813e6ace47624b8b040a0912e8c4004e8e106135e2732509f2c40a5285b238e1f59490a15bdf86ec96841ad062d619221150c2ac3f84e5213acda0e5e6ab297d889e4bdb66d567b73a20ac3f946d83c1f0e20aa2a1422b926a3dfdd497efec196

### more than 255 blocks is refused

```x
(do
  (import x/codec/hkdf)
  (import x/codec/hmac)
  (write (guard (e (e msg)) (Hkdf expand (lit sha256) "k" "" 8161))))
```
---
    "Hkdf expand: more than 255 blocks asked for"

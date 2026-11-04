# Base64 encoder JIT engine
# @weight 8
# @timeout-scale 4

The compiled encoder behind `(Base64 encode-region)`, built by
x/codec/base64-encode-jit for an input of 4 KB or more, or at once by
`encode-jit!`, and adopted only after it encodes the codec's check inputs
byte for byte as the pure-x encoder does.  The inputs here are byte i+1
holding (i+1)*7 mod 256 -- NULs and high bytes among them -- 5000, 5001 and
5002 bytes long, so the last group is two bytes, three and one.  The
lengths and SHA-256 of the text are the system `base64`'s on the same
bytes.  The file builds an engine, so it carries the weight of one.

## the engine builds and is adopted

### encode-jit! reports the encoder active, and is idempotent

```x
(do
  (import x/codec/base64)
  (write (list (Base64 encode-jit!) (Base64 encode-jit!))))
```
---
    (#t #t)

## agreement with the system base64

### 5000, 5001 and 5002 bytes from offset 1, built for on their own

```x
(do (import x/codec/base64) (import x/codec/bytes) (import x/codec/sha256)
  (def %bk-n ((prim-ref (lit str) (lit make)) 5003))
  ((fn (self i) (when (< i 5003) (do ((prim-ref (lit ptr) (lit set!)) ((prim-ref (lit str) (lit ->ptr)) %bk-n) i (% (* i 7) 256) 1) (self (+ i 1))))) 0)
  (def %bk-sum
    (fn (_ len)
      (def e (Base64 encode-region (list %bk-n 1 len)))
      (list (Bytes length e) (Sha256 hex-n (first e) (Bytes length e)))))
  (write (list (%bk-sum 5000) (%bk-sum 5001) (%bk-sum 5002))))
```
---
    ((6668 "8903a3b7af1398132f683c96205e0e81be00d1c4b21da591c7ce427320ee7a16") (6668 "a84a6de24616933ff2dd6abb56f3983ba9905b017013f6b5b5450d3fe28f0802") (6672 "61896a5570d968c9047ec23bfb80f8e85c432a6701e9a219d4a05466874dc85b"))

### the compiled text decodes back to the bytes

```x
(do (import x/codec/base64) (import x/codec/bytes)
  (def %bk-n ((prim-ref (lit str) (lit make)) 5003))
  ((fn (self i) (when (< i 5003) (do ((prim-ref (lit ptr) (lit set!)) ((prim-ref (lit str) (lit ->ptr)) %bk-n) i (% (* i 7) 256) 1) (self (+ i 1))))) 0)
  (Base64 encode-jit!)
  (write (Bytes same? (Base64 decode-region (Base64 encode-region (list %bk-n 1 5002)))
                      (list %bk-n 1 5002))))
```
---
    #t

# Md5 JIT engine

# @weight 15
# @timeout-scale 4

The compiled digest engine behind `(Md5 jit!)`, built by x/codec/sha-jit
from the same driver as SHA-1's and SHA-256's, with MD5's little-endian fill
and its sixty-four steps.  It is adopted only after the maker's own
differential check against the pure-x digest; these cases re-prove
agreement through the class.

## the engine builds and is adopted

### jit! reports the engine active, and is idempotent

```x
(do
  (import x/codec/md5)
  (display (list (Md5 jit!) (Md5 jit!) ((Compiled named (lit md5)) state))))
```
---
    (#t #t compiled)

### the RFC 1321 vectors hold through the engine

```x
(do
  (import x/codec/md5)
  (Md5 jit!)
  (display (Md5 hex "abc"))(newline)
  (display (Md5 hex ""))(newline)
  (display (Md5 hex "12345678901234567890123456789012345678901234567890123456789012345678901234567890")))
```
---
```output
900150983cd24fb0d6963f7d28e17f72
d41d8cd98f00b204e9800998ecf8427e
57edf4a22be3c955ac49da2e2107b67a
```

### the engine agrees with pure-x on lengths the vectors do not cover

Every length class the padding branches on: one under the length-tail
boundary (55), one over it (57), a block multiple (64) and three blocks.
The pure-x side is the module's own digest, read through its environment.

```x
(do
  (import x/codec/md5)
  (Md5 jit!)
  (def %m5j-ref (eval (lit %digest-words) (module x/codec/md5)))
  (def %m5j-hex (eval (lit %hex) (module x/codec/md5)))
  (def %m5j-mk (fn (_ n) (Str8 pad-right n #\q "z")))
  (def %m5j-agree
    (fn (_ n) (str=? (Md5 hex (%m5j-mk n)) (%m5j-hex (%m5j-ref (%m5j-mk n))))))
  (display (list (%m5j-agree 55) (%m5j-agree 57) (%m5j-agree 64) (%m5j-agree 150))))
```
---
    (#t #t #t #t)

### SHA-1's engine still agrees after MD5's is built in the same process

The two share one module and one driver; each keeps its own scratch and H.

```x
(do
  (import x/codec/md5)
  (import x/codec/sha1)
  (Md5 jit!)
  (Sha1 jit!)
  (display (list (Md5 hex "abc") (Sha1 hex "abc"))))
```
---
    (900150983cd24fb0d6963f7d28e17f72 a9993e364706816aba3e25717850c26c9cd0d89d)

### bytes-into writes the engine's digest into a buffer it is handed, again and again

```x
(do
  (import x/codec/md5)
  (import x/codec/hex)
  (Md5 jit!)
  (def %bi-ref (prim-ref (lit str) (lit byte-ref)))
  (def %bi-int (prim-ref (lit char) (lit ->int)))
  (def %bi-out ((prim-ref (lit str) (lit make)) 16))
  (def %bi-hex
    (fn (_ s)
      (do (Md5 bytes-into s (Str8 length s) %bi-out)
          (Hex encode-bytes
            (List map (fn (_ i) (%bi-int (%bi-ref %bi-out i)))
                      (List range 0 16))))))
  (def %bi-long (Str8 pad-right 300 #\q "z"))
  (write (list (str=? (%bi-hex "abc") (Md5 hex "abc"))
               (str=? (%bi-hex %bi-long) (Md5 hex %bi-long))
               (str=? (%bi-hex "") (Md5 hex "")))))
```
---
    (#t #t #t)

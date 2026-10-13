# Crc32: the CRC-32 in pure x
# @weight 2

The CRC-32 of ISO 3309, set against the system libz's through
`Zlib crc32` on the same bytes: a known value, an empty input, bytes with
NULs and high values, a long input, and a sum carried across pieces.

## against libz

### the check value, and an empty input

```x
(do (import x/codec/crc32) (import x/codec/zlib)
  (write (list (Crc32 of "123456789") (Zlib crc32 0 "123456789" 9) (Crc32 of "") (Zlib crc32 0 "" 0))))
```
---
    (3421780262 3421780262 0 0)

### 70000 bytes with NULs and high bytes, read by their count, whole and in spans

```x
(do (import x/codec/crc32) (import x/codec/zlib)
  (def %cr-r ((prim-ref (lit str) (lit make)) 70000))
  (def %cr-p ((prim-ref (lit str) (lit ->ptr)) %cr-r))
  ((fn (self i) (when (< i 70000) (do ((prim-ref (lit ptr) (lit set!)) %cr-p i (& (* i 7) 255) 1) (self (+ i 1))))) 0)
  (write (list (= (Crc32 of %cr-r 0 70000) (Zlib crc32 0 %cr-r 70000))
               (= (Crc32 of %cr-r 1000 2000) (Crc32 update 0 %cr-r 1000 2000))
               (= (Crc32 update (Crc32 of %cr-r 0 1000) %cr-r 1000 69000) (Zlib crc32 0 %cr-r 70000)))))
```
---
    (#t #t #t)

### a sum carried across pieces is the sum of the whole

```x
(do (import x/codec/crc32) (import x/codec/zlib)
  (def %cr-a "The quick brown fox ")
  (def %cr-b "jumps over the lazy dog")
  (write (list (Crc32 update (Crc32 update 0 %cr-a) %cr-b)
               (Crc32 of (Str8 append %cr-a %cr-b))
               (Zlib crc32 (Zlib crc32 0 %cr-a 20) %cr-b 23))))
```
---
    (1095738169 1095738169 1095738169)

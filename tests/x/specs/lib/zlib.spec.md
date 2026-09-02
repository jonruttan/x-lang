# Zlib codec: compression via the system zlib over FFI (#373)
# @weight 3

The ruled strategy: bind libz the way Float binds libm -- dlopen FFI,
no new C. Byte lists both ways (compressed data is binary; strings
truncate at NUL). Cross-validated manually against the system gzip
CLI in both directions at build time; these specs pin the pure round
trips, the buffer-doubling path, and the error contract.

## zlib-format one-shots

### compress shrinks repetitive data; decompress round-trips exactly

```x
(do (import x/codec/zlib)
  (def data (List flat-map (fn (_ i) (list 1 2 3 4 5 6 7 8)) (List range 0 100)))
  (def z (Zlib compress data))
  (list (List length data) (< (List length z) 80) (equal? (Zlib decompress z) data)))
```
---
    (800 #t #t)

### the destination doubles from a too-small hint until it fits

```x
(do (import x/codec/zlib)
  (def data (List flat-map (fn (_ i) (list 7 7 7 7)) (List range 0 200)))
  (equal? (Zlib decompress (Zlib compress data 9) 1) data))
```
---
    #t

### corrupt and empty input raise 'value

```x
(do (import x/codec/zlib)
  (list (guard (e (Err kind-of e)) (Zlib decompress (list 1 2 3 4 5)))
        (guard (e (Err kind-of e)) (Zlib decompress ()))))
```
---
    ('value 'value)

## the gzip file doors

### gz-write-all / gz-read-all round-trip through a real file

```x
(do (import x/codec/zlib) (import x/sys/posix) (import x/sys/file)
  (def p "/tmp/x-373-spec.gz")
  (def payload (List flat-map (fn (_ i) (list 65 66 67 0 68)) (List range 0 50)))
  (Zlib gz-write-all p payload)
  (def back (Zlib gz-read-all p))
  (File unlink p)
  (list (equal? back payload) (List length back)))
```
---
    (#t 250)

### a missing .gz raises 'io

```x
(do (import x/codec/zlib)
  (list (guard (e (Err kind-of e)) (Zlib gz-read-all "/tmp/x-373-definitely-not.gz"))))
```
---
    ('io)

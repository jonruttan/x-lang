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
  (list (guard (e (Err label e)) (Zlib decompress (list 1 2 3 4 5)))
        (guard (e (Err label e)) (Zlib decompress ()))))
```
---
    ('value 'value)

## the gzip file doors

### gz-write-all / gz-read-all round-trip through a real file

```x
(do (import x/codec/zlib) (import x/sys/posix) (import x/sys/file)
  (def tmp (File temp "/tmp/x-373-spec-gz-"))
  (File close (first tmp))
  (def p (rest tmp))
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
  (list (guard (e (Err label e)) (Zlib gz-read-all "/tmp/x-373-definitely-not.gz"))))
```
---
    ('io)

## streams

A stream takes and fills buffers in place -- an offset and a count each
side -- so a caller reading a file a block at a time never builds a list.

### the fixture: buffers made and filled, compared, and a stream run to its end

```x
(do (import x/codec/zlib)
  (def zs-make (prim-ref (lit str) (lit make)))
  (def zs-ref (prim-ref (lit str) (lit byte-ref)))
  (def zs-int (prim-ref (lit char) (lit ->int)))
  (def zs-ptr (prim-ref (lit str) (lit ->ptr)))
  (def zs-set (prim-ref (lit ptr) (lit set!)))
  ; N bytes, byte I of them (I*7) mod 13 -- NULs among them
  (def zs-bytes (fn (_ n)
    (let ((b (zs-make n)))
      (do (let fill ((i 0)) (when (< i n) (do (zs-set (zs-ptr b) i (% (* i 7) 13) 1) (fill (+ i 1)))))
          b))))
  (def zs-same? (fn (_ a b n)
    (let go ((i 0)) (if (>= i n) #t (if (= (zs-ref a i) (zs-ref b i)) (go (+ i 1)) #f)))))
  ; S fed N bytes of IN in pieces of PIECE, its output in rooms of ROOM:
  ; (MADE . STATUSES), the output in OUT
  (def zs-run (fn (_ s in n piece out room finish)
    (let feed ((off 0) (at 0) (seen ()))
      (let ((k (if (< (- n off) piece) (- n off) piece)))
        (let ((r (Zlib step s in off k out at room (if finish (= (+ off k) n) #f))))
          (let ((used (first r)) (made (first (rest r))) (st (first (rest (rest r)))))
            (if (if (eq? st (lit end)) #t (if (>= (+ off used) n) (< made room) #f))
              (pair (+ at made) (List reverse (pair st seen)))
              (feed (+ off used) (+ at made) (pair st seen)))))))))
  (display "made"))
```
---
    made

### a raw deflate fed a thousand bytes at a time inflates back to the same 3000, NULs and all

```x
(do (def zs-src (zs-bytes 3000))
  (def zs-mid (zs-make 4096))
  (def zs-d (Zlib deflater 6 (lit raw)))
  (def zs-c (zs-run zs-d zs-src 3000 1000 zs-mid 4096 #t))
  (Zlib end zs-d)
  (def zs-out (zs-make 3000))
  (def zs-i (Zlib inflater (lit raw)))
  (def zs-r (Zlib step zs-i zs-mid 0 (first zs-c) zs-out 0 3000 #f))
  (Zlib end zs-i)
  (list (< (first zs-c) 100) (rest zs-r) (zs-same? zs-src zs-out 3000)))
```
---
    (#t (3000 'end) #t)

### a room too small for the output is filled, and the stream goes on into the next

```x
(do (def zs-src (zs-bytes 500))
  (def zs-mid (zs-make 1024))
  (def zs-d (Zlib deflater 0 (lit raw)))
  (def zs-c (zs-run zs-d zs-src 500 500 zs-mid 64 #t))
  (Zlib end zs-d)
  (def zs-out (zs-make 512))
  (def zs-i (Zlib inflater (lit raw)))
  (def zs-b (zs-run zs-i zs-mid (first zs-c) 7 zs-out 512 #f))
  (Zlib end zs-i)
  (list (> (List length (rest zs-c)) 2) (List last (rest zs-c)) (first zs-b) (zs-same? zs-src zs-out 500)))
```
---
    (#t 'end 500 #t)

### gzip's wrapper, written and read

```x
(do (def zs-src (zs-bytes 200))
  (def zs-mid (zs-make 512))
  (def zs-d (Zlib deflater 9 (lit gzip)))
  (def zs-c (zs-run zs-d zs-src 200 200 zs-mid 512 #t))
  (Zlib end zs-d)
  (def zs-out (zs-make 200))
  (def zs-i (Zlib inflater (lit gzip)))
  (def zs-r (Zlib step zs-i zs-mid 0 (first zs-c) zs-out 0 200 #f))
  (Zlib end zs-i)
  (list (zs-int (zs-ref zs-mid 0)) (zs-int (zs-ref zs-mid 1)) (rest zs-r) (zs-same? zs-src zs-out 200)))
```
---
    (31 139 (200 'end) #t)

### inflate stops at the stream's end and says how much it used, leaving what follows

```x
(do (def zs-mid (zs-make 64))
  (def zs-d (Zlib deflater 6 (lit raw)))
  (def zs-c (zs-run zs-d "hello" 5 5 zs-mid 56 #t))
  (Zlib end zs-d)
  ; eight bytes more after the stream, as a gzip trailer follows it
  (zs-set (zs-ptr zs-mid) (first zs-c) 0 8)
  (def zs-out (zs-make 16))
  (def zs-i (Zlib inflater (lit raw)))
  (def zs-r (Zlib step zs-i zs-mid 0 (+ (first zs-c) 8) zs-out 0 16 #f))
  (Zlib end zs-i)
  (list (= (first zs-r) (first zs-c)) (rest zs-r)))
```
---
    (#t (5 'end))

### bad data raises 'value with zlib's message; a format zlib has not is refused

```x
(do (def zs-out (zs-make 16))
  (def zs-i (Zlib inflater (lit raw)))
  (def zs-bad (zs-make 4))
  (let fill ((i 0)) (when (< i 4) (do (zs-set (zs-ptr zs-bad) i 255 1) (fill (+ i 1)))))
  (def zs-e (guard (e (list (Err label e) (e msg))) (Zlib step zs-i zs-bad 0 4 zs-out 0 16 #f)))
  (Zlib end zs-i)
  (list zs-e (guard (e (Err label e)) (Zlib deflater 6 (lit bzip2)))))
```
---
    (('value "Zlib: invalid block type") 'value)

### crc32: the check value, and the same CRC taken in two pieces

```x
(list (Zlib crc32 0 "123456789" 9)
      (Zlib crc32 (Zlib crc32 0 "1234" 4) ((prim-ref (lit str) (lit byte-sub)) "123456789" 4 5) 5))
```
---
    (3421780262 3421780262)

# Unlzma: lzma in pure x-lang
# @weight 3

The decoder is checked against streams `xz --format=lzma -9` wrote, carried
here in hex.  `%lz-region` puts a byte list into a byte region and
`%lz-bytes` reads one back.  Every stream here declares an unknown output
size, which is what the tool writes when it is not told one, so each
decodes to its end marker.

## whatever was loaded first

### the codec read after Bigint

The range coder masks to 32 bits.  On a 4-byte word a decimal literal past
the word is a Bigint once Bigint is loaded, and no integer door masks with
one, so the mask is spelled in hex, which reads the word's bits either way.
This case comes first so that the codec is read with Bigint already there,
the order a long session meets it in.

```x
(do (import x/num/bigint) (import x/codec/unlzma) (import x/codec/hex)
  (def %lz-region (fn (_ bs) (let ((r ((prim-ref (lit str) (lit make)) (List length bs))))
    (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
      (do ((fn (self i l) (unless (null? l) (do ((prim-ref (lit ptr) (lit set!)) p i (first l) 1) (self (+ i 1) (rest l))))) 0 bs) r)))))
  (def %lz-z (Hex decode-bytes "5d00000004ffffffffffffffff00341949ee8def8c80b1e6f35b7bffffb5c80000"))
  (rest (Unlzma decode (%lz-region %lz-z) 0 (List length %lz-z))))
```
---
    (13 33)

## whole streams

### a short input

```x
(do (import x/codec/unlzma) (import x/codec/hex)
  (def %lz-region (fn (_ bs) (let ((r ((prim-ref (lit str) (lit make)) (List length bs))))
    (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
      (do ((fn (self i l) (unless (null? l) (do ((prim-ref (lit ptr) (lit set!)) p i (first l) 1) (self (+ i 1) (rest l))))) 0 bs) r)))))
  (def %lz-bytes (fn (_ r n) (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
    ((fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (& ((prim-ref (lit ptr) (lit ref)) p i 1) 255) acc)))) (- n 1) ()))))
  (def %lz-z (Hex decode-bytes "5d00000004ffffffffffffffff00341949ee8def8c80b1e6f35b7bffffb5c80000"))
  (def %lz-r (Unlzma decode (%lz-region %lz-z) 0 (List length %lz-z)))
  (write (list (equal? (%lz-bytes (first %lz-r) (first (rest %lz-r)))
                       (list 104 101 108 108 111 44 32 104 101 108 108 111 10))
               (first (rest %lz-r))
               (first (rest (rest %lz-r))))))
```
---
    (#t 13 33)

### nothing to decompress: the end marker alone

```x
(do (import x/codec/unlzma) (import x/codec/hex)
  (def %lz-region (fn (_ bs) (let ((r ((prim-ref (lit str) (lit make)) (List length bs))))
    (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
      (do ((fn (self i l) (unless (null? l) (do ((prim-ref (lit ptr) (lit set!)) p i (first l) 1) (self (+ i 1) (rest l))))) 0 bs) r)))))
  (def %lz-z (Hex decode-bytes "5d00000004ffffffffffffffff0083fffbffffc0000000"))
  (rest (Unlzma decode (%lz-region %lz-z) 0 (List length %lz-z))))
```
---
    (0 23)

### a varied input: every literal context, and matches

The stream is 114 bytes and the decoder reads 113 of them: the end marker
comes before the last byte of the coder's flush, and `xz` itself decodes
all 300 bytes from the first 113.  USED is what the stream needed, which
is what a caller looking for what follows a stream wants to know.

```x
(do (import x/codec/unlzma) (import x/codec/hex)
  (def %lz-region (fn (_ bs) (let ((r ((prim-ref (lit str) (lit make)) (List length bs))))
    (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
      (do ((fn (self i l) (unless (null? l) (do ((prim-ref (lit ptr) (lit set!)) p i (first l) 1) (self (+ i 1) (rest l))))) 0 bs) r)))))
  (def %lz-bytes (fn (_ r n) (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
    ((fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (& ((prim-ref (lit ptr) (lit ref)) p i 1) 255) acc)))) (- n 1) ()))))
  (def %lz-z (Hex decode-bytes (Str8 append
    "5d00000004ffffffffffffffff00108a02422f67f733b151a1d36e0c9da6c72b40733a7bc54ba9b95426f2b05a5060c409"
    "9d67235e242d7247c96fe356681a86fb2ebcd2cc3730f8427156eec93b1ad7c9f32a8eafa1fe0369379e4f31cc05aef55d"
    "5fa4930b5115db9a0f5bffff7a880000")))
  (def %lz-r (Unlzma decode (%lz-region %lz-z) 0 (List length %lz-z)))
  (write (list (equal? (%lz-bytes (first %lz-r) (first (rest %lz-r)))
                       (List map (fn (_ i) (+ 33 (% (* i 7) 90))) (List range 0 300)))
               (first (rest %lz-r))
               (first (rest (rest %lz-r))))))
```
---
    (#t 300 113)

### a run, which is a match one byte behind itself

```x
(do (import x/codec/unlzma) (import x/codec/hex)
  (def %lz-region (fn (_ bs) (let ((r ((prim-ref (lit str) (lit make)) (List length bs))))
    (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
      (do ((fn (self i l) (unless (null? l) (do ((prim-ref (lit ptr) (lit set!)) p i (first l) 1) (self (+ i 1) (rest l))))) 0 bs) r)))))
  (def %lz-bytes (fn (_ r n) (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
    ((fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (& ((prim-ref (lit ptr) (lit ref)) p i 1) 255) acc)))) (- n 1) ()))))
  (def %lz-z (Hex decode-bytes "5d00000004ffffffffffffffff0030ee1262d0fd3d5f7fffffe0180000"))
  (def %lz-r (Unlzma decode (%lz-region %lz-z) 0 (List length %lz-z)))
  (write (list (equal? (%lz-bytes (first %lz-r) (first (rest %lz-r)))
                       (List append (List map (fn (_ i) 97) (List range 0 30))
                                    (List append (List map (fn (_ i) 98) (List range 0 4)) (list 10))))
               (first (rest %lz-r)))))
```
---
    (#t 35)

### a repeating input, where one distance is used again and again

```x
(do (import x/codec/unlzma) (import x/codec/hex)
  (def %lz-region (fn (_ bs) (let ((r ((prim-ref (lit str) (lit make)) (List length bs))))
    (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
      (do ((fn (self i l) (unless (null? l) (do ((prim-ref (lit ptr) (lit set!)) p i (first l) 1) (self (+ i 1) (rest l))))) 0 bs) r)))))
  (def %lz-bytes (fn (_ r n) (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
    ((fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (& ((prim-ref (lit ptr) (lit ref)) p i 1) 255) acc)))) (- n 1) ()))))
  (def %lz-z (Hex decode-bytes "5d00000004ffffffffffffffff00309888a3b7621554f98982b3ffffb7e50000"))
  (def %lz-nth (fn (self i l) (if (< i 1) (first l) (self (- i 1) (rest l)))))
  (def %lz-r (Unlzma decode (%lz-region %lz-z) 0 (List length %lz-z)))
  (write (list (equal? (%lz-bytes (first %lz-r) (first (rest %lz-r)))
                       (List map (fn (_ i) (%lz-nth (% i 5) (list 97 98 99 97 98))) (List range 0 300)))
               (first (rest %lz-r)))))
```
---
    (#t 300)

### more output than the window holds, so the window wraps

The dictionary is 4096 bytes (`--lzma1=dict=4KiB`) and the output is
16384, so the window fills and wraps four times: each time it is written
out whole and the distances behind the write position reach its end.

Sixteen thousand bytes are compared as a region rather than as a list:
`equal?` over two lists that long recurses per element in the engine and
takes the C stack with it.

```x
(do (import x/codec/unlzma) (import x/codec/hex)
  (def %lz-region (fn (_ bs) (let ((r ((prim-ref (lit str) (lit make)) (List length bs))))
    (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
      (do ((fn (self i l) (unless (null? l) (do ((prim-ref (lit ptr) (lit set!)) p i (first l) 1) (self (+ i 1) (rest l))))) 0 bs) r)))))
  (def %lz-want (fn (_ n f) (let ((r ((prim-ref (lit str) (lit make)) n)))
    (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
      (do ((fn (self i) (when (< i n) (do ((prim-ref (lit ptr) (lit set!)) p i (f i) 1) (self (+ i 1))))) 0) r)))))
  (def %lz-z (Hex decode-bytes (Str8 append
    "5d00100000ffffffffffffffff003098c8e25de1f04e8ff4b440f478025cf20601bd7bd42fc2d8d02d9a269b3609cc03b5"
    "8c1c21a1fd665f7bc69ded659c450edeccf6a5785ed94c769027cba16f23bba933a303127329fffe56c400")))
  (def %lz-r (Unlzma decode (%lz-region %lz-z) 0 (List length %lz-z)))
  (def %lz-e (%lz-want 16384 (fn (_ i) (+ 97 (+ (% i 7) (% i 3))))))
  (write (list (first (rest %lz-r))
               (first (rest (rest %lz-r)))
               ((prim-ref (lit mem) (lit cmp))
                ((prim-ref (lit str) (lit ->ptr)) (first %lz-r))
                ((prim-ref (lit str) (lit ->ptr)) %lz-e)
                16384))))
```
---
    (16384 92 0)

### a header that says how long the output is

The alone format writes every bit set when it is not told the length, and
every stream above does.  A header that names one instead stops the
decoder at that count, which is what the end marker would otherwise do:
this is the stream above with 13 in the field, and `xz -d` reads it the
same way.

```x
(do (import x/codec/unlzma) (import x/codec/hex)
  (def %lz-region (fn (_ bs) (let ((r ((prim-ref (lit str) (lit make)) (List length bs))))
    (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
      (do ((fn (self i l) (unless (null? l) (do ((prim-ref (lit ptr) (lit set!)) p i (first l) 1) (self (+ i 1) (rest l))))) 0 bs) r)))))
  (def %lz-bytes (fn (_ r n) (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
    ((fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (& ((prim-ref (lit ptr) (lit ref)) p i 1) 255) acc)))) (- n 1) ()))))
  (def %lz-z (Hex decode-bytes "5d000000040d0000000000000000341949ee8def8c80b1e6f35b7bffffb5c80000"))
  (def %lz-r (Unlzma decode (%lz-region %lz-z) 0 (List length %lz-z)))
  (write (list (equal? (%lz-bytes (first %lz-r) (first (rest %lz-r)))
                       (list 104 101 108 108 111 44 32 104 101 108 108 111 10))
               (first (rest %lz-r)))))
```
---
    (#t 13)

## a stream that is not one

### a header the format does not allow

The properties byte packs lc, lp and pb, so 225 and up name no settings.

```x
(do (import x/codec/unlzma) (import x/codec/hex)
  (def %lz-region (fn (_ bs) (let ((r ((prim-ref (lit str) (lit make)) (List length bs))))
    (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
      (do ((fn (self i l) (unless (null? l) (do ((prim-ref (lit ptr) (lit set!)) p i (first l) 1) (self (+ i 1) (rest l))))) 0 bs) r)))))
  (def %lz-z (Hex decode-bytes "ff00000004ffffffffffffffff0083fffbffffc0000000"))
  (guard (e (list (Err label e) (e msg) (e data)))
    (Unlzma decode (%lz-region %lz-z) 0 (List length %lz-z))))
```
---
    ('value "Unlzma: the header's properties byte is out of range" (('lzma . 'data)))

### a stream that stops inside a symbol

```x
(do (import x/codec/unlzma) (import x/codec/hex)
  (def %lz-region (fn (_ bs) (let ((r ((prim-ref (lit str) (lit make)) (List length bs))))
    (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
      (do ((fn (self i l) (unless (null? l) (do ((prim-ref (lit ptr) (lit set!)) p i (first l) 1) (self (+ i 1) (rest l))))) 0 bs) r)))))
  (def %lz-z (Hex decode-bytes "5d00000004ffffffffffffffff003419"))
  (guard (e (list (Err label e) (e msg) (e data)))
    (Unlzma decode (%lz-region %lz-z) 0 (List length %lz-z))))
```
---
    ('value "Unlzma: the stream ends inside a symbol" (('lzma . 'short)))

## a stream fed a piece at a time

`%lz-fed` feeds a stream step bytes at a time and then finishes it, and
answers the bytes that came out, their CRC-32 carried across the pieces,
whether the stream is done, and how many bytes it left unread.  `gzip`
gives each output's CRC-32.  Each piece here is under the 4KB that builds
the compiled decoder, so these run this file's.

### a byte at a time

```x
(do (import x/codec/unlzma) (import x/codec/hex) (import x/codec/crc32)
  (def %lz-region (fn (_ bs) (let ((r ((prim-ref (lit str) (lit make)) (List length bs))))
    (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
      (do ((fn (self i l) (unless (null? l) (do ((prim-ref (lit ptr) (lit set!)) p i (first l) 1) (self (+ i 1) (rest l))))) 0 bs) r)))))
  (def %lz-fed (fn (_ in n step)
    (let ((z (Unlzma stream))
          (sum (fn (_ acc p) (list (+ (first acc) (first (rest p))) (Crc32 update (first (rest acc)) (first p) 0 (first (rest p)))))))
      ((fn (self off acc)
         (if (< off n)
           (self (+ off step) (sum acc (Unlzma feed z in off (if (< (- n off) step) (- n off) step))))
           (let ((all (sum acc (Unlzma finish z))))
             (list (first all) (first (rest all)) (Unlzma done? z) (first (rest (Unlzma rest z)))))))
       0 (list 0 0)))))
  (def %lz-z (Hex decode-bytes "5d00000004ffffffffffffffff00341949ee8def8c80b1e6f35b7bffffb5c80000"))
  (write (%lz-fed (%lz-region %lz-z) (List length %lz-z) 1)))
```
---
    (13 522593755 #t 0)

### a window that wraps, five bytes at a time

The stream above whose 16384 bytes wrap a 4096-byte window four times.

```x
(do (import x/codec/unlzma) (import x/codec/hex) (import x/codec/crc32)
  (def %lz-region (fn (_ bs) (let ((r ((prim-ref (lit str) (lit make)) (List length bs))))
    (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
      (do ((fn (self i l) (unless (null? l) (do ((prim-ref (lit ptr) (lit set!)) p i (first l) 1) (self (+ i 1) (rest l))))) 0 bs) r)))))
  (def %lz-fed (fn (_ in n step)
    (let ((z (Unlzma stream))
          (sum (fn (_ acc p) (list (+ (first acc) (first (rest p))) (Crc32 update (first (rest acc)) (first p) 0 (first (rest p)))))))
      ((fn (self off acc)
         (if (< off n)
           (self (+ off step) (sum acc (Unlzma feed z in off (if (< (- n off) step) (- n off) step))))
           (let ((all (sum acc (Unlzma finish z))))
             (list (first all) (first (rest all)) (Unlzma done? z) (first (rest (Unlzma rest z)))))))
       0 (list 0 0)))))
  (def %lz-z (Hex decode-bytes (Str8 append
    "5d00100000ffffffffffffffff003098c8e25de1f04e8ff4b440f478025cf20601bd7bd42fc2d8d02d9a269b3609cc03b5"
    "8c1c21a1fd665f7bc69ded659c450edeccf6a5785ed94c769027cba16f23bba933a303127329fffe56c400")))
  (write (%lz-fed (%lz-region %lz-z) (List length %lz-z) 5)))
```
---
    (16384 3778333515 #t 0)

### the header waits for its bytes

Ten bytes are not a header: none come out and the stream is not done.

```x
(do (import x/codec/unlzma) (import x/codec/hex)
  (def %lz-region (fn (_ bs) (let ((r ((prim-ref (lit str) (lit make)) (List length bs))))
    (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
      (do ((fn (self i l) (unless (null? l) (do ((prim-ref (lit ptr) (lit set!)) p i (first l) 1) (self (+ i 1) (rest l))))) 0 bs) r)))))
  (def %lz-z (Hex decode-bytes "5d00000004ffffffffffffffff00341949ee8def8c80b1e6f35b7bffffb5c80000"))
  (def %lz-s (Unlzma stream))
  (write (list (first (rest (Unlzma feed %lz-s (%lz-region %lz-z) 0 10))) (Unlzma done? %lz-s))))
```
---
    (0 #f)

### a stream cut short, then finished

Fed, the bytes wait; finished, they are a stream that stops inside a
symbol.

```x
(do (import x/codec/unlzma) (import x/codec/hex)
  (def %lz-region (fn (_ bs) (let ((r ((prim-ref (lit str) (lit make)) (List length bs))))
    (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
      (do ((fn (self i l) (unless (null? l) (do ((prim-ref (lit ptr) (lit set!)) p i (first l) 1) (self (+ i 1) (rest l))))) 0 bs) r)))))
  (def %lz-z (Hex decode-bytes "5d00000004ffffffffffffffff00341949ee8def8c80b1e6"))
  (def %lz-s (Unlzma stream))
  (Unlzma feed %lz-s (%lz-region %lz-z) 0 (List length %lz-z))
  (guard (e (list (Err label e) (e msg) (e data)))
    (Unlzma finish %lz-s)))
```
---
    ('value "Unlzma: the stream ends inside a symbol" (('lzma . 'short)))

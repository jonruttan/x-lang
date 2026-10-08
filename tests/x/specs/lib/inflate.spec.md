# Inflate: DEFLATE in pure x-lang
# @weight 3

The decoder is checked against the system zlib: each case compresses with
`Zlib compress` (libz) and decompresses with `Inflate`, the levels chosen so
that every block type appears -- level 0 writes stored blocks, a short input
a fixed-code block, a longer varied one dynamic codes.  `%if-region` puts a
byte list into a byte region and `%if-bytes` reads one back.

## the checksum

### Adler-32 of a known string

```x
(do (import x/codec/inflate)
    (Inflate adler32 "Wikipedia" 9))
```
---
    300286872

## zlib streams

### a short input: one fixed-code block

```x
(do (import x/codec/inflate) (import x/codec/zlib)
  (def %if-region (fn (_ bs) (let ((r ((prim-ref (lit str) (lit make)) (List length bs))))
    (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
      (do ((fn (self i l) (unless (null? l) (do ((prim-ref (lit ptr) (lit set!)) p i (first l) 1) (self (+ i 1) (rest l))))) 0 bs) r)))))
  (def %if-bytes (fn (_ r n) (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
    ((fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (& ((prim-ref (lit ptr) (lit ref)) p i 1) 255) acc)))) (- n 1) ()))))
  (def %if-data (list 104 101 108 108 111 44 32 104 101 108 108 111 10))
  (def %if-z (Zlib compress %if-data 6))
  (def %if-r (Inflate zlib (%if-region %if-z) 0 (List length %if-z)))
  (write (list (equal? (%if-bytes (first %if-r) (first (rest %if-r))) %if-data)
               (= (first (rest (rest %if-r))) (List length %if-z)))))
```
---
    (#t #t)

### level 0: stored blocks

```x
(do (import x/codec/inflate) (import x/codec/zlib)
  (def %if-region (fn (_ bs) (let ((r ((prim-ref (lit str) (lit make)) (List length bs))))
    (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
      (do ((fn (self i l) (unless (null? l) (do ((prim-ref (lit ptr) (lit set!)) p i (first l) 1) (self (+ i 1) (rest l))))) 0 bs) r)))))
  (def %if-bytes (fn (_ r n) (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
    ((fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (& ((prim-ref (lit ptr) (lit ref)) p i 1) 255) acc)))) (- n 1) ()))))
  (def %if-data (List map (fn (_ i) (& (* i 7) 255)) (List range 0 300)))
  (def %if-z (Zlib compress %if-data 0))
  (def %if-r (Inflate zlib (%if-region %if-z) 0 (List length %if-z)))
  (write (list (equal? (%if-bytes (first %if-r) (first (rest %if-r))) %if-data)
               (first (rest %if-r)))))
```
---
    (#t 300)

### a longer varied input: dynamic codes, and back-references

```x
(do (import x/codec/inflate) (import x/codec/zlib)
  (def %if-region (fn (_ bs) (let ((r ((prim-ref (lit str) (lit make)) (List length bs))))
    (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
      (do ((fn (self i l) (unless (null? l) (do ((prim-ref (lit ptr) (lit set!)) p i (first l) 1) (self (+ i 1) (rest l))))) 0 bs) r)))))
  (def %if-bytes (fn (_ r n) (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
    ((fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (& ((prim-ref (lit ptr) (lit ref)) p i 1) 255) acc)))) (- n 1) ()))))
  (def %if-data (List map (fn (_ i) (+ 97 (% (+ (* i i) (/ i 7)) 23))) (List range 0 2000)))
  (def %if-z (Zlib compress %if-data 9))
  (def %if-r (Inflate zlib (%if-region %if-z) 0 (List length %if-z)))
  (write (list (equal? (%if-bytes (first %if-r) (first (rest %if-r))) %if-data)
               (first (rest %if-r)) (< (List length %if-z) 2000))))
```
---
    (#t 2000 #t)

### a run: overlapping copies a distance of one back

```x
(do (import x/codec/inflate) (import x/codec/zlib)
  (def %if-region (fn (_ bs) (let ((r ((prim-ref (lit str) (lit make)) (List length bs))))
    (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
      (do ((fn (self i l) (unless (null? l) (do ((prim-ref (lit ptr) (lit set!)) p i (first l) 1) (self (+ i 1) (rest l))))) 0 bs) r)))))
  (def %if-bytes (fn (_ r n) (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
    ((fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (& ((prim-ref (lit ptr) (lit ref)) p i 1) 255) acc)))) (- n 1) ()))))
  (def %if-data (List map (fn (_ i) 0) (List range 0 1000)))
  (def %if-z (Zlib compress %if-data 6))
  (def %if-r (Inflate zlib (%if-region %if-z) 0 (List length %if-z)))
  (write (list (equal? (%if-bytes (first %if-r) (first (rest %if-r))) %if-data)
               (first (rest %if-r)))))
```
---
    (#t 1000)

### an empty input

```x
(do (import x/codec/inflate) (import x/codec/zlib)
  (def %if-region (fn (_ bs) (let ((r ((prim-ref (lit str) (lit make)) (List length bs))))
    (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
      (do ((fn (self i l) (unless (null? l) (do ((prim-ref (lit ptr) (lit set!)) p i (first l) 1) (self (+ i 1) (rest l))))) 0 bs) r)))))
  (def %if-z (Zlib compress () 6))
  (write (rest (Inflate zlib (%if-region %if-z) 0 (List length %if-z)))))
```
---
    (0 8)

## where a stream ends

### USED counts the stream alone, not the bytes after it

Two streams end to end, as a git pack lays them: the first's USED is
where the second starts.

```x
(do (import x/codec/inflate) (import x/codec/zlib)
  (def %if-region (fn (_ bs) (let ((r ((prim-ref (lit str) (lit make)) (List length bs))))
    (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
      (do ((fn (self i l) (unless (null? l) (do ((prim-ref (lit ptr) (lit set!)) p i (first l) 1) (self (+ i 1) (rest l))))) 0 bs) r)))))
  (def %if-a (Zlib compress (list 1 2 3 4 5) 6))
  (def %if-b (Zlib compress (list 9 9 9) 6))
  (def %if-s (%if-region (List append %if-a %if-b)))
  (def %if-n (+ (List length %if-a) (List length %if-b)))
  (def %if-r1 (Inflate zlib %if-s 0 %if-n))
  (def %if-used (first (rest (rest %if-r1))))
  (def %if-r2 (Inflate zlib %if-s %if-used (- %if-n %if-used)))
  (write (list (= %if-used (List length %if-a)) (first (rest %if-r1)) (first (rest %if-r2)))))
```
---
    (#t 5 3)

### a raw stream is the zlib stream without its header and checksum

```x
(do (import x/codec/inflate) (import x/codec/zlib)
  (def %if-region (fn (_ bs) (let ((r ((prim-ref (lit str) (lit make)) (List length bs))))
    (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
      (do ((fn (self i l) (unless (null? l) (do ((prim-ref (lit ptr) (lit set!)) p i (first l) 1) (self (+ i 1) (rest l))))) 0 bs) r)))))
  (def %if-z (Zlib compress (List map (fn (_ i) (& i 255)) (List range 0 500)) 6))
  (def %if-n (List length %if-z))
  (def %if-r (Inflate raw (%if-region %if-z) 2 (- %if-n 6)))
  (write (list (first (rest %if-r)) (= (first (rest (rest %if-r))) (- %if-n 6)))))
```
---
    (500 #t)

## refusals

### a changed checksum

```x
(do (import x/codec/inflate) (import x/codec/zlib)
  (def %if-region (fn (_ bs) (let ((r ((prim-ref (lit str) (lit make)) (List length bs))))
    (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
      (do ((fn (self i l) (unless (null? l) (do ((prim-ref (lit ptr) (lit set!)) p i (first l) 1) (self (+ i 1) (rest l))))) 0 bs) r)))))
  (def %if-z (Zlib compress (list 1 2 3) 6))
  (def %if-n (List length %if-z))
  (def %if-bad (List append (List take (- %if-n 1) %if-z) (list (^ (List ref (- %if-n 1) %if-z) 1))))
  (guard (e (list (Err label e) (e msg))) (Inflate zlib (%if-region %if-bad) 0 %if-n)))
```
---
    ('value "Inflate: the Adler-32 does not match")

### a header that is not zlib's

```x
(do (import x/codec/inflate)
  (guard (e (e msg)) (Inflate zlib "abcdefgh")))
```
---
    "Inflate: not DEFLATE (the zlib header's method is not 8)"

### a stream cut short

```x
(do (import x/codec/inflate) (import x/codec/zlib)
  (def %if-region (fn (_ bs) (let ((r ((prim-ref (lit str) (lit make)) (List length bs))))
    (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
      (do ((fn (self i l) (unless (null? l) (do ((prim-ref (lit ptr) (lit set!)) p i (first l) 1) (self (+ i 1) (rest l))))) 0 bs) r)))))
  (def %if-z (Zlib compress (List map (fn (_ i) (& (* i 13) 255)) (List range 0 400)) 6))
  (guard (e (e msg)) (Inflate raw (%if-region %if-z) 2 10)))
```
---
    "Inflate: the input ends inside the stream"

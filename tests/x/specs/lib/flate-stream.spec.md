# Deflate and Inflate, a piece at a time
# @weight 15
# @timeout-scale 4

`Deflate stream` and `feed` write a raw DEFLATE stream from pieces, and
`Inflate stream` and `feed` read one back from pieces -- what gzip and
gunzip do with a file they must not hold whole.  Each case reads back what
it wrote, as a whole and in pieces of other sizes.  `%fs-text` makes N
bytes of varied text; `%fs-deflate` writes N bytes of a region in pieces
of K; `%fs-inflate` reads a stream back in pieces of K, answering the
bytes, whether the stream said it was done, and the input it did not use.
The weight and timeout are the 100000-byte case's: past both codecs' bars,
it builds the compiled engines.

## the helpers

### text, and the two codecs fed in pieces

```x
(do (import x/codec/deflate) (import x/codec/inflate)
  (def %fs-make (prim-ref (lit str) (lit make)))
  (def %fs-ptr (prim-ref (lit str) (lit ->ptr)))
  (def %fs-ref (prim-ref (lit ptr) (lit ref)))
  (def %fs-set (prim-ref (lit ptr) (lit set!)))
  (def %fs-copy (prim-ref (lit mem) (lit copy)))
  (def %fs-cmp (prim-ref (lit mem) (lit cmp)))
  (def %fs-at (fn (_ r off) ((prim-ref (lit int) (lit ->ptr)) (+ ((prim-ref (lit ptr) (lit ->int)) (%fs-ptr r)) off))))
  (def %fs-text
    (fn (_ n)
      (def r (%fs-make n))
      ((fn (self i s)
         (when (< i n)
           (do (%fs-set (%fs-ptr r) i (if (= (% i 97) 0) 10 (+ 97 (% (+ (* i i) (>> s 3)) 23))) 1)
               (self (+ i 1) (% (+ (* s 75) 1) 65537)))))
       0 1)
      r))
  ; regions laid end to end: (REGION . N)
  (def %fs-join
    (fn (_ parts)
      (def n (List fold (fn (_ acc p) (+ acc (rest p))) 0 parts))
      (def r (%fs-make (if (< n 1) 1 n)))
      (List fold (fn (_ at p) (do (when (> (rest p) 0) (%fs-copy (%fs-at r at) (%fs-ptr (first p)) (rest p))) (+ at (rest p)))) 0 parts)
      (pair r n)))
  (def %fs-deflate
    (fn (_ src n k)
      (def w (Deflate stream))
      ((fn (self at acc)
         (let ((m (if (< (- n at) k) (- n at) k)))
           (let ((o (Deflate feed w src at m (= (+ at m) n))))
             (if (= (+ at m) n) (%fs-join (List reverse (pair (pair (first o) (first (rest o))) acc)))
               (do (Heap collect) (self (+ at m) (pair (pair (first o) (first (rest o))) acc)))))))
       0 ())))
  (def %fs-inflate
    (fn (_ src n k)
      (def z (Inflate stream))
      ((fn (self at acc)
         (if (>= at n)
           (list (%fs-join (List reverse acc)) (Inflate done? z) (first (rest (Inflate rest z))))
           (let ((m (if (< (- n at) k) (- n at) k)))
             (let ((o (Inflate feed z src at m)))
               (do (Heap collect) (self (+ at m) (pair (pair (first o) (first (rest o))) acc)))))))
       0 ())))
  (def %fs-same? (fn (_ a b n) (= 0 (%fs-cmp (%fs-ptr a) (%fs-ptr b) n))))
  (display "made"))
```
---
    made

## the round trips

### written in three pieces, read back whole: the text again

```x
(let ((t (%fs-text 3000)))
  (let ((d (%fs-deflate t 3000 1100)))
    (let ((back (Inflate raw (first d) 0 (rest d))))
      (write (list (< (rest d) 3000) (first (rest back)) (%fs-same? t (first back) 3000) (= (first (rest (rest back))) (rest d)))))))
```
---
    (#t 3000 #t #t)

### written whole, read back 37 bytes at a time, the bytes after it kept

A stream with `trailer` after it, fed 37 bytes at a time: each block comes
out when its last byte arrives, and the trailer is the input left over.

```x
(let ((t (%fs-text 2000)))
  (let ((d (Deflate raw t 0 2000)))
    (let ((both (%fs-join (list (pair (first d) (first (rest d))) (pair "trailer" 7)))))
      (let ((back (%fs-inflate (first both) (rest both) 37)))
        (write (list (rest (first back)) (%fs-same? t (first (first back)) 2000)
                     (first (rest back)) (first (rest (rest back)))))))))
```
---
    (2000 #t #t 7)

### 100000 bytes both ways in pieces of 7000

```x
(let ((t (%fs-text 100000)))
  (let ((d (%fs-deflate t 100000 7000)))
    (let ((back (%fs-inflate (first d) (rest d) 7000)))
      (write (list (< (rest d) 100000) (rest (first back)) (%fs-same? t (first (first back)) 100000)
                   (first (rest back)) (first (rest (rest back))))))))
```
---
    (#t 100000 #t #t 0)

### an empty input: one final block, read back as none

```x
(let ((d (%fs-deflate "" 0 10)))
  (let ((back (%fs-inflate (first d) (rest d) 1)))
    (write (list (rest d) (rest (first back)) (first (rest back))))))
```
---
    (2 0 #t)

### a stream cut short waits; a malformed one is refused

Half a stream gives what its whole blocks hold and waits, not done; a
block of type 3 raises at once.

```x
(let ((t (%fs-text 40000)))
  (let ((d (%fs-deflate t 40000 40000)))
    (let ((half (%fs-inflate (first d) (>> (rest d) 1) 4096)) (bad (%fs-make 2)))
      (write (list (< (rest (first half)) 40000) (first (rest half))
                   (do (%fs-set (%fs-ptr bad) 0 255 1) (%fs-set (%fs-ptr bad) 1 255 1) (guard (e (list (Err label e) (e msg))) (Inflate feed (Inflate stream) bad 0 2))))))))
```
---
    (#t #f ('value "Inflate: a block of type 3"))

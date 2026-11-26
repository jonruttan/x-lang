# Gzip: a gzip member written a piece at a time
# @weight 8

`x/codec/gzip` answers a member's header, its compressed pieces and its CRC
and length. The members are read back by `x/codec/inflate` and by the system
libz through `Zlib gz-read-all`.

## the member's frame

### the header, and the CRC and length after the stream, low byte first

```x
(do (import x/codec/gzip)
  (def %gm (Gzip feed (Gzip stream) "abc" 0 3 #t))
  (write (list (Bytes hex (Bytes sub %gm 0 10))
               (Bytes hex (Bytes sub %gm (- (Bytes length %gm) 8) 8)))))
```
---
    ("1f8b0800000000000003" "c241243503000000")

### a member of no bytes is one final piece of none

```x
(do (import x/codec/gzip)
  (def %gm (Gzip feed (Gzip stream) "" 0 0 #t))
  (write (list (Bytes length %gm) (Bytes hex (Bytes sub %gm 12 8)))))
```
---
    (20 "0000000000000000")

### the header goes out once, with the first piece

```x
(do (import x/codec/gzip)
  (def %gs (Gzip stream))
  (def %ga (Gzip feed %gs "abc" 0 3 #f))
  (def %gb (Gzip feed %gs "def" 0 3 #f))
  (write (list (Bytes hex (Bytes sub %ga 0 2)) (< (Bytes length %gb) 10))))
```
---
    ("1f8b" #t)

## read back

### pieces fed apart inflate to the whole, and the trailer is what is left

```x
(do (import x/codec/gzip) (import x/codec/inflate) (import x/codec/crc32)
  (def %gs (Gzip stream))
  (def %gw (Bytes writer))
  (Bytes put %gw (Gzip feed %gs "hello, hello, " 0 14 #f))
  (Bytes put %gw (Gzip feed %gs "xxgzipxx" 2 4 #f))
  (Bytes put %gw (Gzip feed %gs "" 0 0 #t))
  (def %gm (Bytes written %gw))
  (def %gz (Inflate stream))
  (def %go (Inflate feed %gz (first %gm) 10 (- (Bytes length %gm) 10)))
  (def %gr (Inflate rest %gz))
  (write (list (Str8 sub 0 (first (rest %go)) (first %go))
               (Inflate done? %gz)
               (first (rest %gr))
               (Bytes hex (list (first %gr) 4 4))
               (= (Crc32 of "hello, hello, gzip")
                  (+ (Bytes ref (list (first %gr) 0 4) 0)
                     (* 256 (+ (Bytes ref (list (first %gr) 0 4) 1)
                               (* 256 (+ (Bytes ref (list (first %gr) 0 4) 2)
                                         (* 256 (Bytes ref (list (first %gr) 0 4) 3)))))))))))
```
---
    ("hello, hello, gzip" #t 8 "12000000" #t)

### 20000 bytes with NULs and high bytes, in two pieces, come back the same

```x
(do (import x/codec/gzip) (import x/codec/inflate) (import x/codec/crc32)
  (def %gd (Bytes of-list (let go ((i 0) (acc ())) (if (= i 20000) acc (go (+ i 1) (pair (& (* i 7) 255) acc))))))
  (def %gs (Gzip stream))
  (def %gw (Bytes writer))
  (Bytes put %gw (Gzip feed %gs (first %gd) 0 12000 #f))
  (Bytes put %gw (Gzip feed %gs (first %gd) 12000 8000 #t))
  (def %gm (Bytes written %gw))
  (def %gz (Inflate stream))
  (def %go (Inflate feed %gz (first %gm) 10 (- (Bytes length %gm) 10)))
  (write (list (first (rest %go))
               (= (Crc32 of (first %go) 0 (first (rest %go))) (Crc32 of (first %gd) 0 20000))
               (< (Bytes length %gm) 20000)
               (Bytes hex (list (first (Inflate rest %gz)) 4 4)))))
```
---
    (20000 #t #t "204e0000")

### libz reads a member written to a file

```x
(do (import x/codec/gzip) (import x/codec/zlib) (import x/sys/file) (import x/sys/posix)
  (def %gp (Str8 append "/tmp/x-gzip-spec." (Str8 str (Sys getpid)) ".gz"))
  (def %gs (Gzip stream))
  (def %gf (File open %gp (list (lit wronly) (lit creat) (lit trunc))))
  (def %gput (fn (_ r) (File write %gf (first r) (Bytes length r))))
  (%gput (Gzip feed %gs "one, two, " 0 10 #f))
  (%gput (Gzip feed %gs "one, two, three" 0 15 #t))
  (File close %gf)
  (def %gt (bytes->str (Zlib gz-read-all %gp)))
  (File unlink %gp)
  (write %gt))
```
---
    "one, two, one, two, three"

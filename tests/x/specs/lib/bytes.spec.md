# Bytes
# @weight 1

Binary buffers that carry their length.  A string's own length stops at
its first NUL, so every case here puts NULs where a length would lose
them: at the start, in the middle and at the end.

## regions

### of-hex, hex, length and ref keep every NUL

```x
(do
  (import x/codec/bytes)
  (def %by-r (Bytes of-hex "00ff0000ab00"))
  (write (list (Bytes length %by-r) (Bytes hex %by-r) (Bytes ref %by-r 1) (Bytes ref %by-r 4))))
```
---
    (6 "00ff0000ab00" 255 171)

### copy, sub and join

```x
(do
  (import x/codec/bytes)
  (def %bj-r (Bytes of-hex "0011002233"))
  (write (list (Bytes hex (Bytes sub %bj-r 1 3))
               (Bytes hex (Bytes copy (Bytes sub %bj-r 2 3)))
               (Bytes hex (Bytes join (Bytes sub %bj-r 0 2) "ab" (Bytes of-hex "00")))
               (Bytes length (Bytes join))
               (guard (e (e msg)) (Bytes sub %bj-r 3 3)))))
```
---
    ("110022" "002233" "0011616200" 0 "Bytes sub: past the end of the region")

### same? compares every byte, NULs included

```x
(do
  (import x/codec/bytes)
  (write (list (Bytes same? (Bytes of-hex "000102") (Bytes sub (Bytes of-hex "ff000102") 1 3))
               (Bytes same? (Bytes of-hex "000102") (Bytes of-hex "000103"))
               (Bytes same? (Bytes of-hex "00") (Bytes of-hex "0000")))))
```
---
    (#t #f #f)

### random answers the bytes asked for, and two draws differ

```x
(do
  (import x/codec/bytes)
  (def %br-a (Bytes random 32))
  (def %br-b (Bytes random 32))
  (write (list (Bytes length %br-a) (Bytes same? %br-a %br-b))))
```
---
    (32 #f)

## writers

### put integers, regions and strings; patch a length after

```x
(do
  (import x/codec/bytes)
  (def %bw (Bytes writer))
  (Bytes put-u8 %bw 22)
  (Bytes put-u16 %bw 771)
  (Bytes put-u16 %bw 0)
  (Bytes put-u24 %bw 1)
  (Bytes put-u32 %bw 16909060)
  (Bytes put %bw (Bytes of-hex "0000"))
  (Bytes put %bw "hi")
  (Bytes patch-u16 %bw 3 (- (Bytes size %bw) 5))
  (write (list (Bytes size %bw) (Bytes hex (Bytes written %bw)))))
```
---
    (16 "160303000b0000010102030400006869")

### a writer grows past its first buffer

```x
(do
  (import x/codec/bytes)
  (def %bg (Bytes writer))
  ((fn (self i) (unless (= i 1000) (do (Bytes put-u8 %bg (& i 255)) (self (+ i 1))))) 0)
  (def %bg-r (Bytes written %bg))
  (write (list (Bytes length %bg-r) (Bytes ref %bg-r 0) (Bytes ref %bg-r 256) (Bytes ref %bg-r 999))))
```
---
    (1000 0 0 231)

## readers

### get integers and regions; a field past the end is refused

```x
(do
  (import x/codec/bytes)
  (def %bd (Bytes reader (Bytes of-hex "1603030005000102030400ff")))
  (def %bd-type (Bytes get-u8 %bd))
  (def %bd-ver (Bytes get-u16 %bd))
  (def %bd-len (Bytes get-u16 %bd))
  (def %bd-body (Bytes get %bd %bd-len))
  (write (list %bd-type %bd-ver %bd-len (Bytes hex %bd-body) (Bytes left %bd)
               (Bytes get-u16 %bd)
               (guard (e (e msg)) (Bytes get-u8 %bd)))))
```
---
    (22 771 5 "0001020304" 2 255 "Bytes: a field runs past the end of its message")

### u24, u32 and rest

```x
(do
  (import x/codec/bytes)
  (def %b3 (Bytes reader (Bytes of-hex "01000000000102ffee00")))
  (write (list (Bytes get-u24 %b3) (Bytes get-u32 %b3) (Bytes hex (Bytes rest %b3)) (Bytes left %b3))))
```
---
    (65536 258 "ffee00" 0)

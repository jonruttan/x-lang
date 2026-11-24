# Tar: the blocks a ustar archive is written from
# @weight 5

`x/codec/tar` answers a member's header, the padding after its bytes and the
archive's end. The headers are held to the checksum rule and to the reader
in `x/tool/pin`, which unpacks what they describe.

## the blocks

### a header is one block, padding rounds a member up, the end is two

```x
(do (import x/codec/tar)
  (write (list (Bytes length (Tar header "lib/m.x" 12 420 0 (lit file)))
               (Bytes length (Tar padding 0)) (Bytes length (Tar padding 1))
               (Bytes length (Tar padding 512)) (Bytes length (Tar padding 700))
               (Bytes length (Tar end)))))
```
---
    (512 0 511 0 324 1024)

### the fields: name, mode, size, time, type, magic

```x
(do (import x/codec/tar)
  (def %th (Tar header "lib/m.x" 12 420 1700000000 (lit file)))
  (def %tf (fn (_ off len) (first (Bytes copy (Bytes sub %th off len)))))
  (write (list (%tf 0 100) (%tf 100 8) (%tf 124 12) (%tf 136 12) (%tf 156 1) (%tf 257 6) (%tf 263 2))))
```
---
    ("lib/m.x" "0000644" "00000000014" "14524770400" "0" "ustar" "00")

### the checksum is the sum of the block with its own field as spaces

```x
(do (import x/codec/tar) (import x/tool/pin)
  (def %th (Tar header "lib/m.x" 12 420 1700000000 (lit file)))
  (def %ts (let go ((i 0) (acc 0))
             (if (= i 512) acc
               (go (+ i 1) (+ acc (if (if (>= i 148) (< i 156) #f) 32 (Bytes ref %th i)))))))
  (write (list (= %ts (Pin %tar-octal %th 148 8)) (Bytes ref %th 154) (Bytes ref %th 155))))
```
---
    (#t 0 32)

### a directory takes its trailing slash, type 5 and no size

```x
(do (import x/codec/tar)
  (def %th (Tar header "lib" 99 493 0 (lit dir)))
  (def %tf (fn (_ off len) (first (Bytes copy (Bytes sub %th off len)))))
  (write (list (%tf 0 100) (%tf 100 8) (%tf 124 12) (%tf 156 1))))
```
---
    ("lib/" "0000755" "00000000000" "5")

## long paths

### a path past 100 bytes is split at a slash, and the reader joins it again

```x
(do (import x/codec/tar) (import x/tool/pin)
  (def %ta "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
  (def %tp (Str8 append %ta "/bbbb/m.x"))
  (def %th (Tar header %tp 0 420 0 (lit file)))
  (write (list (Str8 length %tp)
               (Str8 length (first (Bytes copy (Bytes sub %th 345 155))))
               (first (Bytes copy (Bytes sub %th 0 100)))
               (str=? (Pin %tar-path %th) %tp))))
```
---
    (109 105 "m.x" #t)

### what a header cannot hold is refused

```x
(do (import x/codec/tar)
  (def %ta "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
  (def %tr (fn (_ work) (guard (e (Err text e)) (do (work) "no raise"))))
  (write (list (%tr (fn (_) (Tar header (Str8 append %ta "b") 0 420 0 (lit file))))
               (%tr (fn (_) (Tar header "" 0 420 0 (lit file))))
               (%tr (fn (_) (Tar header "a" 8589934592 420 0 (lit file))))
               (%tr (fn (_) (Tar header "a" 0 420 0 (lit link)))))))
```
---
    ("Tar header: a path past 100 bytes with no / to split it at" "Tar header: an empty path" "Tar header: a size past 8 GB" "Tar header: a kind that is not file or dir")

## against the reader

### an archive written from these blocks unpacks to its members

```x
(do (import x/codec/tar) (import x/tool/pin) (import x/sys/file) (import x/sys/posix)
  (def %td (Str8 append "/tmp/x-tar-spec." (Str8 str (Sys getpid))))
  (File mkdir %td)
  (def %tw (Bytes writer))
  (Bytes put %tw (Tar header "d" 0 493 0 (lit dir)))
  (Bytes put %tw (Tar header "d/a.txt" 5 420 0 (lit file)))
  (Bytes put %tw "hello")
  (Bytes put %tw (Tar padding 5))
  (Bytes put %tw (Tar header "d/empty" 0 384 0 (lit file)))
  (Bytes put %tw (Tar end))
  (def %tr (Bytes written %tw))
  (def %tst (Pin %tar-feed (Pin %tar-start %td) (first %tr) 0 (Bytes length %tr)))
  (def %tout (list (Bytes length %tr) (eq? (first %tst) (lit end))
                   (File read-all (Str8 append %td "/d/a.txt"))
                   (File exists? (Str8 append %td "/d/empty"))))
  (File unlink (Str8 append %td "/d/a.txt"))
  (File unlink (Str8 append %td "/d/empty"))
  (File rmdir (Str8 append %td "/d"))
  (File rmdir %td)
  (write %tout))
```
---
    (3072 #t "hello" #t)

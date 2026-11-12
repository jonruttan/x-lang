# @lib ../tests/x/lib/asm.x
# @weight 1

x/tool/link lays objects out as one program.  An object is `(SECTIONS
SYMBOLS RELOCS)`: a section is `(NAME ALIGN SIZE BYTES)`, a symbol `(NAME
SECTION OFFSET SCOPE)`, a relocation `(SECTION OFFSET KIND NAME ADDEND)`.
`link` puts the sections of one name end to end in object order, asks the
caller where each output section will be, and calls the caller's patcher at
every relocation with the place and the value it takes; the kinds are the
caller's, since the encodings are its backend's.

The patcher in these cases stores the value as an eight-byte word, so a
relocation's effect can be read back from the bytes.

## layout

### the sections of one name go end to end, each at its alignment

Two objects with a `data` section of 3 bytes each, the second aligned to 8:
the second starts at 8, and the output is 11 bytes.

```x
(do
  (import x/tool/link link link-undefined link-write! link-read)
  (import x/core/doors ptr-set! str-byte-ref char->int)
  (def %a (list (list (list 'data 1 3 "abc")) (list (list "a" 'data 0 'global)) ()))
  (def %b (list (list (list 'data 8 3 "xyz")) (list (list "b" 'data 0 'global)) ()))
  (def %r (link (list %a %b) (fn (_ sizes) (list (pair 'data 0))) (fn (_ p o k v s) ())))
  (def %s (first (first %r)))
  (def %bytes (first (rest (rest (rest %s)))))
  (def %b (fn (_ i) (char->int (str-byte-ref %bytes i))))
  (write (list (first %s) (first (rest (rest %s))) (%b 0) (%b 2) (%b 3) (%b 7) (%b 8) (%b 10)))
  (newline))
```
---
    ('data 11 97 99 0 0 120 122)

### a global's place and address come back by name

The address the caller gives a section is the base of every symbol in it.

```x
(do
  (import x/tool/link link link-undefined link-write! link-read)
  (def %a (list (list (list 'data 1 3 "abc")) (list (list "a" 'data 0 'global)) ()))
  (def %b (list (list (list 'data 8 3 "xyz")) (list (list "b" 'data 1 'global)) ()))
  (def %r (link (list %a %b) (fn (_ sizes) (list (pair 'data 4096))) (fn (_ p o k v s) ())))
  (write (list ((first (rest %r)) get "a") ((first (rest %r)) get "b")))
  (newline))
```
---
    (('data 0 4096) ('data 9 4105))

### what no bytes cover is zero

A section with no BYTES is zero in the output, never built byte by byte.

```x
(do
  (import x/tool/link link link-undefined link-write! link-read)
  (import x/core/doors str-byte-ref char->int)
  (def %a (list (list (list 'data 1 2 "ab")) () ()))
  (def %b (list (list (list 'data 1 4 ())) () ()))
  (def %r (link (list %a %b) (fn (_ sizes) (list (pair 'data 0))) (fn (_ p o k v s) ())))
  (def %bytes (first (rest (rest (rest (first (first %r)))))))
  (write (list (char->int (str-byte-ref %bytes 1)) (char->int (str-byte-ref %bytes 2)) (char->int (str-byte-ref %bytes 5))))
  (newline))
```
---
    (98 0 0)

## relocations

### a relocation takes its name's address and the addend

Object A's data holds a place that takes B's `b` plus 2; B's data lies at 8
in the output, `b` at 1 in B, the section at 4096.

```x
(do
  (import x/tool/link link link-undefined link-write! link-read)
  (import x/core/doors ptr-set! str-byte-ref char->int)
  (def %a (list (list (list 'data 1 8 ())) () (list (list 'data 0 'word "b" 2))))
  (def %b (list (list (list 'data 8 3 "xyz")) (list (list "b" 'data 1 'global)) ()))
  (def %sites ())
  (def %r (link (list %a %b) (fn (_ sizes) (list (pair 'data 4096)))
            (fn (_ p o k v s) (do (set! %sites (pair (list o k s) %sites)) (ptr-set! p o v 8)))))
  (def %bytes (first (rest (rest (rest (first (first %r)))))))
  (write (list %sites (char->int (str-byte-ref %bytes 0)) (char->int (str-byte-ref %bytes 1))))
  (newline))
```
---
    (((0 'word 4096)) 11 16)

### an object's local shadows a global of the same name

Both objects define `n`; A's is local, so A's relocation takes its own
and B's takes the global.

```x
(do
  (import x/tool/link link link-undefined link-write! link-read)
  (import x/core/doors ptr-set! str-byte-ref char->int)
  (def %a (list (list (list 'data 1 16 ())) (list (list "n" 'data 8 'local))
            (list (list 'data 0 'word "n" 0))))
  (def %b (list (list (list 'data 1 16 ())) (list (list "n" 'data 8 'global))
            (list (list 'data 0 'word "n" 0))))
  (def %r (link (list %a %b) (fn (_ sizes) (list (pair 'data 0)))
            (fn (_ p o k v s) (ptr-set! p o v 8))))
  (def %bytes (first (rest (rest (rest (first (first %r)))))))
  (write (list (char->int (str-byte-ref %bytes 0)) (char->int (str-byte-ref %bytes 16))))
  (newline))
```
---
    (8 24)

### the names no object defines, before a link

```x
(do
  (import x/tool/link link link-undefined link-write! link-read)
  (def %a (list (list (list 'text 4 8 ())) (list (list "f" 'text 0 'global))
            (list (list 'text 0 'rel "g" 0) (list 'text 4 'rel "puts" 0))))
  (def %b (list (list (list 'text 4 8 ())) (list (list "g" 'text 0 'global))
            (list (list 'text 0 'rel "puts" 0) (list 'text 4 'rel "exit" 0))))
  (write (link-undefined (list %a %b)))
  (newline))
```
---
    ("puts" "exit")

### a name no object defines refuses the link

```x
(do
  (import x/tool/link link link-undefined link-write! link-read)
  (def %a (list (list (list 'text 4 8 ())) () (list (list 'text 0 'rel "g" 0))))
  (write (guard (e (lit refused)) (link (list %a) (fn (_ sizes) (list (pair 'text 0))) (fn (_ p o k v s) ()))))
  (newline))
```
---
    'refused

### a global defined twice refuses the link

```x
(do
  (import x/tool/link link link-undefined link-write! link-read)
  (def %a (list (list (list 'text 4 8 ())) (list (list "f" 'text 0 'global)) ()))
  (write (guard (e (lit refused)) (link (list %a %a) (fn (_ sizes) (list (pair 'text 0))) (fn (_ p o k v s) ()))))
  (newline))
```
---
    'refused

## object files

### an object written and read back is the same object, its relocations grouped by name

The records are binary unless text is asked for.  Binary records hold each
name once, with every place that takes its value, so the relocations come
back a name at a time: the object's symbols in order, then a name that is
taken and is no symbol of it.

```x
(do
  (import x/tool/link link link-undefined link-write! link-read)
  (import x/sys/file)
  (def %t (File temp))
  (File close (first %t))
  (def %o (list (list (list 'text 4 8 "ABCDEFGH") (list 'data 8 2 "xy") (list 'bss 16 64 ()))
                (list (list "f" 'text 0 'global) (list "s" 'data 0 'local) (list "g" () 0 'global))
                (list (list 'text 4 (list 'patch 4 'arm64-rel) "g" 0) (list 'data 8 'word "s" -3)
                      (list 'text 0 'word "h" 7) (list 'text 2 'word "g" 1))))
  (link-write! (rest %t) %o)
  (def %line (let ((fd (File open (rest %t) 'rdonly)) (b ((prim-ref 'str 'make) 10))) (File read fd b 10) (File close fd) b))
  (def %back (link-read (rest %t)))
  (File unlink (rest %t))
  (write (list %line %back))
  (newline))
```
---
    ("x-object 2" ((('text 4 8 "ABCDEFGH") ('data 8 2 "xy") ('bss 16 64 ())) (("f" 'text 0 'global) ("s" 'data 0 'local) ("g" () 0 'global)) (('data 8 'word "s" -3) ('text 4 ('patch 4 'arm64-rel) "g" 0) ('text 2 'word "g" 1) ('text 0 'word "h" 7))))

### written as text, an object reads back as it was written

```x
(do
  (import x/tool/link link link-undefined link-write! link-read)
  (import x/sys/file)
  (def %t (File temp))
  (File close (first %t))
  (def %o (list (list (list 'text 4 8 "ABCDEFGH") (list 'data 8 2 "xy"))
                (list (list "f" 'text 0 'global) (list "s" 'data 0 'local) (list "g" () 0 'global))
                (list (list 'text 4 (list 'patch 4 'arm64-rel) "g" 0) (list 'data 8 'word "s" 3))))
  (link-write! (rest %t) %o 'text)
  (def %line (let ((fd (File open (rest %t) 'rdonly)) (b ((prim-ref 'str 'make) 10))) (File read fd b 10) (File close fd) b))
  (def %back (link-read (rest %t)))
  (File unlink (rest %t))
  (write (list %line (equal? %back %o)))
  (newline))
```
---
    ("x-object 1" #t)

### a name with a byte past 127 is written as text

A binary record ends a name on a byte with its top bit set, so such a name
has no binary form, and the object is written as text.

```x
(do
  (import x/tool/link link link-undefined link-write! link-read)
  (import x/sys/file)
  (def %t (File temp))
  (File close (first %t))
  (def %o (list (list (list 'text 4 4 "ABCD")) (list (list "caf\xc3\xa9" 'text 0 'global)) ()))
  (link-write! (rest %t) %o)
  (def %line (let ((fd (File open (rest %t) 'rdonly)) (b ((prim-ref 'str 'make) 10))) (File read fd b 10) (File close fd) b))
  (def %back (link-read (rest %t)))
  (File unlink (rest %t))
  (write (list %line (equal? %back %o)))
  (newline))
```
---
    ("x-object 1" #t)

### an object read from binary records links as the one it was written from

```x
(do
  (import x/tool/link link link-undefined link-write! link-read)
  (import x/sys/file)
  (def %t (File temp))
  (File close (first %t))
  (def %a (list (list (list 'text 4 16 "0123456789abcdef"))
                (list (list "f" 'text 0 'global))
                (list (list 'text 0 'word "g" 1) (list 'text 4 'word "h" 2) (list 'text 8 'word "g" 3) (list 'text 12 'word "h" -4))))
  (def %b (list (list (list 'data 8 16 ())) (list (list "g" 'data 0 'global) (list "h" 'data 8 'global)) ()))
  (link-write! (rest %t) %a)
  (def %back (link-read (rest %t)))
  (File unlink (rest %t))
  (def %seen (list ()))
  (def %run (fn (_ o)
    (%set-first! %seen ())
    (link (list o %b) (fn (_ ss) (List map (fn (_ s) (pair (first s) (if (eq? (first s) 'text) 4096 8192))) ss))
      (fn (_ p offset kind value site) (%set-first! %seen (pair (list offset value site) (first %seen)))))
    (List sort (fn (_ x y) (< (first x) (first y))) (first %seen))))
  (write (list (equal? (%run %a) (%run %back)) (%run %back)))
  (newline))
```
---
    (#t ((0 8193 4096) (4 8202 4100) (8 8195 4104) (12 8196 4108)))

### a file that is no object refuses

```x
(do
  (import x/tool/link link link-undefined link-write! link-read)
  (import x/sys/file)
  (def %t (File temp))
  (File write (first %t) "hello, this is not an object file at all\n" 41)
  (File close (first %t))
  (def %r (guard (e (lit refused)) (link-read (rest %t))))
  (File unlink (rest %t))
  (write %r)
  (newline))
```
---
    'refused

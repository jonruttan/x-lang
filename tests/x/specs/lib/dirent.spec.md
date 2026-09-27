# Dirent decoding: the shared platform decoder (#228)
# @weight 1

boot/module.x and sys/file.x once carried drifted copies; both now
decode through x/platform/dirent's dirent-names, and this spec pins
its behavior over synthetic getdents buffers.  Fixtures follow
the running OS's dirent64 layout (Darwin: reclen u16@16, namlen u16@18,
name@21; Linux: reclen u16@16, type u8@18, name z@19).  Four entries:
a normal name, a "." (decoders KEEP dots -- rejecting them is consumer
policy), a deleted ino-0 slot (skipped), and -- the namlen case -- a
name field carrying bytes past namlen before its NUL, which only the
namlen bound decodes correctly on Darwin.

## the one decoder

### ino-0 skipped, namlen bounds the name, dots kept

```x
(do
  (import x/sys/file)
  (def %i->c (prim-ref 'int '->char))
  (def %bs (fn (_ ints) (bytes->str (%map (fn (_ i) (%i->c i)) ints))))
  ; one 32-byte entry; name bytes given, zero-padded to 32
  (def %ent
    (fn (_ ino namlen namebytes)
      (def %pad (fn (self lst n) (if (= n 0) lst (self (pair 0 lst) (- n 1)))))
      (def %head
        (%append
          (list ino 0 0 0 0 0 0 0)          ; ino u64 (low byte carries the id)
          (list 0 0 0 0 0 0 0 0)            ; seekoff/off u64
          (list 32 0)                        ; reclen u16 = 32
          (if os-darwin?
            (list namlen 0 0)               ; namlen u16 + type u8
            (list 0))))                      ; type u8 (Linux)
      (def %room (- 32 (+ (%length %head) (%length namebytes))))
      (%append %head (%append namebytes (%pad () %room)))))
  ; "alpha" | "." | ghost (ino 0) | "abc" with XYZ garbage past namlen
  (def %fix (%bs (%append (%ent 1 5 (list 97 108 112 104 97))
                  (%append (%ent 2 1 (list 46))
                    (%append (%ent 0 5 (list 103 104 111 115 116))
                             (%ent 3 3 (if os-darwin?
                                         (list 97 98 99 88 89 90)
                                         (list 97 98 99))))))))
  ; NOT (Str8 length): str values are C strings, so the length reads to
  ; the first NUL -- and dirent buffers are full of them.  The byte
  ; REGION is all there (byte-ref is raw); pass the constructed count,
  ; as the syscall's return value does for the real buffers.
  (def %n 128)
  (import x/platform/dirent)
  (write (dirent-names %fix %n ())))
```
---
    ("abc" "." "alpha")

## cost

### a batch decodes in fewer than 300 objects an entry

The decode runs per directory entry on every listing, so its offsets,
lengths and bytes go through the integer primitives, not the tower's
checked operators.  Sixteen 32-byte entries, decoded ten times, with the
same loop around an empty thunk subtracted.

```x
(do
  (import x/sys/gc)
  (import x/platform/dirent)
  (def %i->c (prim-ref 'int '->char))
  (def %bs (fn (_ ints) (bytes->str (%map (fn (_ i) (%i->c i)) ints))))
  ; one 32-byte entry named "abcdefgh"
  (def %ent
    (fn (_ ino)
      (%append (list ino 0 0 0 0 0 0 0  0 0 0 0 0 0 0 0  32 0)
        (%append (if os-darwin? (list 8 0 0) (list 0))
          (%append (list 97 98 99 100 101 102 103 104)
                   (if os-darwin? (list 0 0 0) (list 0 0 0 0 0)))))))
  (def %ents
    (fn (self i acc) (if (= i 0) acc (self (- i 1) (%append (%ent i) acc)))))
  (def %buf (%bs (%ents 16 ())))
  (def %cost
    (fn (_ f)
      (f)
      (def c0 (Heap count))
      ((fn (loop i) (if (= i 0) () (do (f) (loop (- i 1))))) 10)
      (- (Heap count) c0)))
  (def %over
    (- (%cost (fn (_) (dirent-names %buf 512 ())))
       (%cost (fn (_) ()))))
  (list (%length (dirent-names %buf 512 ())) (< %over (* 300 16 10))))
```
---
    (16 #t)

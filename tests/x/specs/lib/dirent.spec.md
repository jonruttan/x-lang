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

```scheme
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

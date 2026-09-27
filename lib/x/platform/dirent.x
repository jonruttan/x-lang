; dirent.x -- THE dirent64 batch decoder (#228)
;
; One decoder for the getdents64/getdirentries64 buffers, shared by the
; boot module scanner (boot/module.x) and the File class (sys/file.x) --
; the two copies this replaces had drifted (namlen ignored, deleted
; slots kept, errors folded into EOF).  The layout knowledge lives HERE
; and nowhere else:
;   Linux  dirent64: ino u64@0, off u64@8, reclen u16@16, type u8@18,
;                    name z@19 (bounded by reclen)
;   Darwin dirent64: ino u64@0, seekoff u64@8, reclen u16@16,
;                    namlen u16@18, type u8@20, name@21 (bounded by
;                    NAMLEN -- the field may carry bytes past it)
;
; Boot-loadable like platform/syscall.x: imported at CALL time by
; boot/module.x, so only boot accessors appear here -- no classes, no
; Err.  Policy stays with callers: dot entries are KEPT (rejecting "."
; and ".." is the consumer's business), and this decodes one already-
; read buffer -- it never reads fds or judges errors.

(doc (def dirent-names
  (fn (_ (param buf STRING "One getdents batch buffer (a (str make N) region a syscall filled)")
       (param n INTEGER "Byte count the syscall returned -- NOT the buffer's string length (the region is full of NULs)")
       (param acc LIST "Accumulator; entry names cons onto it"))
    ; Fetched per call, not per byte: one batch decode is one fetch.  Every
    ; value the walk computes is a byte, an offset or a length, never nil,
    ; so the integer primitives serve where the tower's operators would
    ; check and dispatch on every byte.
    (def %byte-ref (prim-ref (lit str) (lit byte-ref)))
    (def %byte-sub (prim-ref (lit str) (lit byte-sub)))
    (def %char->int (prim-ref (lit char) (lit ->int)))
    (def %int+ (prim-ref (lit int) (lit +)))
    (def %int- (prim-ref (lit int) (lit -)))
    (def %int< (prim-ref (lit int) (lit <)))
    (def %int<< (prim-ref (lit int) (lit <<)))
    (def %u16
      (fn (_ i)
        (%int+ (%char->int (%byte-ref buf i))
               (%int<< (%char->int (%byte-ref buf (%int+ i 1))) 8))))
    ; ino u64@0 all-zero = a deleted-but-not-compacted slot (byte-wise:
    ; only the zero test matters, and boot has no i64 peek).
    (def %ino-zero?
      (fn (loop i end)
        (match
          ((= i end) #t)
          ((= (%char->int (%byte-ref buf i)) 0) (loop (%int+ i 1) end))
          (#t #f))))
    ; The first NUL at or after i, or end.
    (def %nul-at
      (fn (loop i end)
        (match
          ((= i end) i)
          ((= (%char->int (%byte-ref buf i)) 0) i)
          (#t (loop (%int+ i 1) end)))))
    ; The name of the record at off: NAMLEN bytes on Darwin, NUL-terminated
    ; within the record on Linux.
    (def %name
      (match
        (os-darwin?
          (fn (_ off reclen) (%byte-sub buf (%int+ off 21) (%u16 (%int+ off 18)))))
        (#t
          (fn (_ off reclen)
            (def start (%int+ off 19))
            (%byte-sub buf start (%int- (%nul-at start (%int+ off reclen)) start))))))
    ; One record, then the rest through walk; a zero reclen would never
    ; advance (the corrupt-buffer guard).
    (def %record
      (fn (_ walk off reclen acc)
        (match
          ((= reclen 0) acc)
          ((%ino-zero? off (%int+ off 8)) (walk (%int+ off reclen) acc))
          (#t (walk (%int+ off reclen) (pair (%name off reclen) acc))))))
    (def %walk
      (fn (loop off acc)
        (match
          ((%int< off n) (%record loop off (%u16 (%int+ off 16)) acc))
          (#t acc))))
    (%walk 0 acc)))
  (returns LIST "Entry names consed onto acc, deleted (ino-0) slots skipped, dot entries KEPT")
  "Decode one dirent64 batch buffer into entry names.")

(doc (provide x/platform/dirent dirent-names)
  (note "Layout truth for dirent64 on both OSes; boot/module.x and sys/file.x both decode through this.")
  "The shared getdents batch decoder.")

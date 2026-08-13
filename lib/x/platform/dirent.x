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
       (param n INT "Byte count the syscall returned -- NOT the buffer's string length (the region is full of NULs)")
       (param acc LIST "Accumulator; entry names cons onto it"))
    ; Fetched per call, not per byte: one batch decode is one fetch.
    (def %byte-ref (prim-ref (lit str) (lit byte-ref)))
    (def %char->int (prim-ref (lit char) (lit ->int)))
    (def %u8 (fn (_ i) (%char->int (%byte-ref buf i))))
    (def %u16 (fn (_ i) (+ (%u8 i) (* 256 (%u8 (+ i 1))))))
    ; ino u64@0 all-zero = a deleted-but-not-compacted slot (byte-wise:
    ; only the zero test matters, and boot has no i64 peek).
    (def %ino-zero?
      (fn (loop off i)
        (match
          ((= i 8) #t)
          ((= (%u8 (+ off i)) 0) (loop off (+ i 1)))
          (#t #f))))
    ; NUL-terminated name between start and end (end from namlen or reclen).
    (def %name
      (fn (_ start end)
        (def %scan
          (fn (loop i)
            (match
              ((= i end) i)
              ((= (%u8 i) 0) i)
              (#t (loop (+ i 1))))))
        (%substring buf start (%scan start))))
    (def %walk
      (fn (loop off acc)
        (match
          ((< off n)
            (do
              (def %reclen (%u16 (+ off 16)))
              (match
                ; a zero reclen would never advance: corrupt-buffer guard
                ((= %reclen 0) acc)
                (#t
                  (do
                    (def %nm
                      (match
                        (os-darwin? (%name (+ off 21) (+ (+ off 21) (%u16 (+ off 18)))))
                        (#t (%name (+ off 19) (+ off %reclen)))))
                    (loop (+ off %reclen)
                          (match
                            ((%ino-zero? off 0) acc)
                            (#t (pair %nm acc)))))))))
          (#t acc))))
    (%walk 0 acc)))
  (returns LIST "Entry names consed onto acc, deleted (ino-0) slots skipped, dot entries KEPT")
  "Decode one dirent64 batch buffer into entry names.")

(doc (provide x/platform/dirent dirent-names)
  (note "Layout truth for dirent64 on both OSes; boot/module.x and sys/file.x both decode through this.")
  "The shared getdents batch decoder.")

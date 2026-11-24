; tar.x -- Tar: the blocks a ustar archive is written from.
;
; A tar archive is 512-byte blocks: one header a member, the member's bytes
; padded to a whole block, and two blocks of zeros at the end.  This class
; answers those pieces as regions (x/codec/bytes) and does no I/O: the
; caller streams a member's bytes between its header and its padding, so
; an archive is never held whole.
;
; The header is POSIX ustar (IEEE 1003.1-1988): a path past 100 bytes is
; split at a "/" into the 155-byte prefix and the 100-byte name, and one
; that cannot be split is refused, since this writes no pax or GNU long-name
; record.  Owner and group are 0 and unnamed, so the same members give the
; same bytes on any machine.
;
; The reader is in x/tool/pin, which unpacks a release's tarball.
(module x/codec/tar)

(import x/codec/bytes)
(import x/type/err)
(import x/core/doors int% int/)

; n as width - 1 octal digits, zero-padded, then a NUL: a header number's
; bytes, or nil when n does not fit.
(def %octal
  (fn (_ n width)
    (let go ((i (- width 1)) (v n) (acc (list 0)))
      (if (= i 0) (if (= v 0) acc ())
        (go (- i 1) (int/ v 8) (pair (+ 48 (int% v 8)) acc))))))

; text put to w, then NULs up to width bytes.
(def %put-field!
  (fn (_ w text width)
    (do (Bytes put w text)
        (Bytes put w (Bytes zeros (- width (Str8 length text)))))))

; Where path splits into a prefix and a name: the index of the last "/" that
; leaves at most 155 bytes before it and 1 to 100 after, or nil.
(def %split-at
  (fn (_ path)
    (let ((n (Str8 length path)))
      (let go ((i (if (< 155 (- n 2)) 155 (- n 2))))
        (match
          ((< i 1) ())
          ((< 100 (- n (+ i 1))) ())
          ((str=? (Str8 sub i 1 path) "/") i)
          (#t (go (- i 1))))))))

; The sum of a region's bytes.
(def %sum
  (fn (_ r)
    (let go ((i 0) (acc 0))
      (if (= i (Bytes length r)) acc
        (go (+ i 1) (+ acc (Bytes ref r i)))))))

(def-class Tar ()
  (doc "The blocks a ustar archive is written from, as regions: a member's header, the padding after its bytes, and the archive's end. No I/O is done."
    (example "(Bytes length (Tar header \"lib/m.x\" 12 420 0 (lit file)))" "512")
    (see header) (see padding) (see end))
  (static
    (method header (self (param path STRING "The member's path, with no leading /")
                         (param size INTEGER "How many bytes the member holds; a directory's is 0")
                         (param mode INTEGER "Its permission bits, such as 420 for rw-r--r--")
                         (param mtime INTEGER "When it was modified, in seconds since the epoch")
                         (param kind SYMBOL "file or dir"))
      (doc "The 512-byte ustar header of one member. A directory's path is given its trailing /. Raises a label 'value for a path past 100 bytes with no / to split it at, a size or time that is below 0 or past what its field holds (8 GB for a size), and a kind that is neither."
        (returns LIST "A region (BUF 0 512)")
        (example "(Bytes length (Tar header \"a\" 0 493 0 (lit dir)))" "512")
        (example "(first (Bytes copy (Bytes sub (Tar header \"a\" 0 493 0 (lit dir)) 0 2)))" "\"a/\"")
        (example "(first (Bytes copy (Bytes sub (Tar header \"a\" 5 420 0 (lit file)) 257 5)))" "\"ustar\""))
      (def %bad (fn (_ what) (Err raise (lit value) (Str8 append "Tar header: " what) path)))
      (def dir? (eq? kind (lit dir)))
      (unless (if dir? #t (eq? kind (lit file))) (%bad "a kind that is not file or dir"))
      (def full (if (if dir? (not (Str8 ends? "/" path)) #f) (Str8 append path "/") path))
      (when (str=? full "") (%bad "an empty path"))
      (def at (if (< 100 (Str8 length full)) (%split-at full) ()))
      (when (if (< 100 (Str8 length full)) (null? at) #f)
        (%bad "a path past 100 bytes with no / to split it at"))
      (when (< size 0) (%bad "a size below 0"))
      (when (< mtime 0) (%bad "a time below 0"))
      (def size-field (%octal (if dir? 0 size) 12))
      (def mtime-field (%octal mtime 12))
      (when (null? size-field) (%bad "a size past 8 GB"))
      (when (null? mtime-field) (%bad "a time its field cannot hold"))
      (def w (Bytes writer))
      (%put-field! w (if (null? at) full (Str8 sub (+ at 1) (- (Str8 length full) (+ at 1)) full)) 100)
      (Bytes put w (Bytes of-list (%octal (int% mode 4096) 8)))
      (Bytes put w (Bytes of-list (%octal 0 8)))
      (Bytes put w (Bytes of-list (%octal 0 8)))
      (Bytes put w (Bytes of-list size-field))
      (Bytes put w (Bytes of-list mtime-field))
      ; The checksum is taken with its own field as eight spaces.
      (Bytes put w "        ")
      (Bytes put w (if dir? "5" "0"))
      (%put-field! w "" 100)
      (%put-field! w "ustar" 6)
      (Bytes put w "00")
      (%put-field! w "" 32)
      (%put-field! w "" 32)
      (Bytes put w (Bytes of-list (%octal 0 8)))
      (Bytes put w (Bytes of-list (%octal 0 8)))
      (%put-field! w (if (null? at) "" (Str8 sub 0 at full)) 155)
      (%put-field! w "" 12)
      ; Six octal digits, a NUL and a space, two bytes a patch.
      (def sum (%octal (%sum (Bytes written w)) 7))
      (Bytes patch-u16 w 148 (+ (* 256 (sum 0)) (sum 1)))
      (Bytes patch-u16 w 150 (+ (* 256 (sum 2)) (sum 3)))
      (Bytes patch-u16 w 152 (+ (* 256 (sum 4)) (sum 5)))
      (Bytes patch-u16 w 154 32)
      (Bytes written w))

    (method padding (self (param size INTEGER "How many bytes the member held"))
      (doc "The zeros that follow a member of size bytes, to the end of its last 512-byte block: none when size is a whole number of blocks."
        (returns LIST "A region of 0 to 511 zeros")
        (example "(Bytes length (Tar padding 513))" "511")
        (example "(Bytes length (Tar padding 1024))" "0"))
      (Bytes zeros (int% (- 512 (int% size 512)) 512)))

    (method end (self)
      (doc "The two blocks of zeros that end an archive."
        (returns LIST "A region of 1024 zeros")
        (example "(Bytes length (Tar end))" "1024"))
      (Bytes zeros 1024))))

(doc (provide x/codec/tar Tar)
  (example "(Bytes length (Tar end))" "1024")
  "The blocks a ustar archive is written from: a member's header, the padding after its bytes, and the archive's end, as regions. The reader is in x/tool/pin.")

; crc32.x -- Crc32: the CRC-32 of ISO 3309 in pure x-lang.
;
; The checksum gzip, zip and git's pack indexes carry: the reflected
; polynomial 0xEDB88320, the register started at all ones and inverted at
; the end, a byte at a time through a table of 256 entries built when the
; module loads.  Zlib (x/codec/zlib) binds the system's libz for the same
; sum; this is the one for a system that has no libz, and the reference
; the two are checked against each other by.
;
; Pure INT on the C bit ops through the int doors; the exclusive or, which
; has no door, is (a | b) - (a & b) on the non-negative words here.  The
; byte loop is one top-level function calling itself in tail position.
(module x/codec/crc32)

(import x/type/vector)

(def %add (prim-ref (lit int) (lit +)))
(def %sub (prim-ref (lit int) (lit -)))
(def %lt (prim-ref (lit int) (lit <)))
(def %eq (prim-ref (lit int) (lit =)))
(def %and (prim-ref (lit int) (lit &)))
(def %or (prim-ref (lit int) (lit |)))
(def %shr (prim-ref (lit int) (lit >>)))
(def %oref (prim-ref (lit obj) (lit ref)))
(def %oset! (prim-ref (lit obj) (lit set!)))
(def %pref (prim-ref (lit ptr) (lit ref)))
(def %str->ptr (prim-ref (lit str) (lit ->ptr)))
(def %str-byte-len (prim-ref (lit str) (lit byte-len)))

(def %xor (fn (_ a b) (%sub (%or a b) (%and a b))))

; Slot i+1 holds byte i's CRC: eight shifts, the polynomial folded in
; when the low bit is set.
(def %table (Vector make 256 0))
((fn (self i)
   (if (%lt i 256)
     (do (%oset! %table (%add i 1)
           ((fn (fold k c)
              (if (%eq k 0) c
                (fold (%sub k 1) (if (%eq (%and c 1) 0) (%shr c 1) (%xor (%shr c 1) 3988292384)))))
            8 i))
         (self (%add i 1)))
     ()))
 0)

; The register after the bytes from i below n at p.
(def %fold
  (fn (self p i n c)
    (if (%lt i n)
      (self p (%add i 1) n
        (%xor (%oref %table (%add (%and (%xor c (%and (%pref p i 1) 255)) 255) 1)) (%shr c 8)))
      c)))

; START and LENGTH from an optional span, defaulting to the whole string.
(def %span
  (fn (_ s span)
    (match
      ((null? span) (list 0 (%str-byte-len s)))
      ((null? (rest span)) (list (first span) (%sub (%str-byte-len s) (first span))))
      (#t (list (first span) (first (rest span)))))))

(def %ptr-at (prim-ref (lit ptr) (lit ->int)))
(def %int->ptr (prim-ref (lit int) (lit ->ptr)))
(def %at (fn (_ p off) (%int->ptr (%add (%ptr-at p) off))))

(def-class Crc32 ()
  (doc "The CRC-32 of ISO 3309 (gzip, zip, git's pack indexes) in pure x-lang.")
  (static
    (method of (self (param s STRING "Bytes")
                     . (param span LIST "START, then LENGTH: which bytes of s; default all of s"))
      (doc "The CRC-32 of the bytes. Give LENGTH for binary input: s's own length is measured to its first NUL."
        (returns INTEGER "The CRC, 0 to 4294967295")
        (example "(Crc32 of \"123456789\")" "3421780262")
        (example "(Crc32 of \"\")" "0"))
      (def sp (%span s span))
      (%xor (%fold (%at (%str->ptr s) (first sp)) 0 (first (rest sp)) 4294967295) 4294967295))
    (method update (self (param crc INTEGER "The CRC so far; 0 to start")
                         (param s STRING "Bytes")
                         . (param span LIST "START, then LENGTH, as for of"))
      (doc "The CRC-32 of the data crc sums followed by the bytes: a sum carried on across pieces, as Zlib crc32 carries it."
        (returns INTEGER "The CRC, 0 to 4294967295")
        (example "(Crc32 update (Crc32 update 0 \"1234\") \"56789\")" "3421780262"))
      (def sp (%span s span))
      (%xor (%fold (%at (%str->ptr s) (first sp)) 0 (first (rest sp)) (%xor crc 4294967295)) 4294967295))))

(doc (provide x/codec/crc32 Crc32)
  "The CRC-32 of ISO 3309 in pure x-lang: (Crc32 of s) and (Crc32 update crc s), the sum libz's crc32 answers.")

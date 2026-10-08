; deflate.x -- Deflate: DEFLATE streams written in pure x-lang.
;
; The writing half of x/codec/inflate, begun with what git needs first: a
; stream any DEFLATE reader takes, written where no C library is present
; (x-os).  Stored blocks (RFC 1951 3.2.4) carry the bytes as they are, up to
; 65535 a block, so the stream is a little larger than its input; a
; compressing writer -- LZ77 over the fixed and dynamic codes -- is the next
; step and will share this file.
;
; Input is a byte region and a count, so a NUL is a byte like any other;
; the output is a region and its count, as Inflate answers.
(module x/codec/deflate)

(import x/codec/inflate)

(def %add (prim-ref 'int '+))
(def %sub (prim-ref 'int '-))
(def %pset! (prim-ref (lit ptr) (lit set!)))
(def %make-str (prim-ref (lit str) (lit make)))
(def %str->ptr (prim-ref (lit str) (lit ->ptr)))
(def %ptr->int (prim-ref (lit ptr) (lit ->int)))
(def %int->ptr (prim-ref (lit int) (lit ->ptr)))
(def %mem-copy (prim-ref (lit mem) (lit copy)))
(def %str-byte-len (prim-ref (lit str) (lit byte-len)))

(def %at (fn (_ p off) (%int->ptr (%add (%ptr->int p) off))))

; The stored blocks of n bytes at src, written from byte `at` of dst:
; each block a header byte (BFINAL in bit 0, type 00), LEN and its
; complement little-endian, then the bytes.  Answers where the writing
; ended.  An empty input is one empty final block.
(def %stored!
  (fn (self src dst at i n)
    (def len (if (> (%sub n i) 65535) 65535 (%sub n i)))
    (def final? (= (%add i len) n))
    (%pset! dst at (if final? 1 0) 1)
    (%pset! dst (%add at 1) (& len 255) 1)
    (%pset! dst (%add at 2) (>> len 8) 1)
    (%pset! dst (%add at 3) (& (~ len) 255) 1)
    (%pset! dst (%add at 4) (& (>> (~ len) 8) 255) 1)
    (when (> len 0) (%mem-copy (%at dst (%add at 5)) (%at src i) len))
    (if final? (%add (%add at 5) len)
      (self src dst (%add (%add at 5) len) (%add i len) n))))

; Room for the stored blocks of n bytes: five a block, and one block at
; least.
(def %stored-room
  (fn (_ n) (%add n (* 5 (%add 1 (>> n 16))))))

(def %span
  (fn (_ s span)
    (match
      ((null? span) (list 0 (%str-byte-len s)))
      ((null? (rest span)) (list (first span) (%sub (%str-byte-len s) (first span))))
      (#t (list (first span) (first (rest span)))))))

(def-class Deflate ()
  (doc "DEFLATE streams written in pure x-lang. Each writer answers (OUT N): a byte region and how many of its bytes the stream is.")
  (static
    (method stored (self (param s STRING "The bytes to carry")
                         . (param span LIST "START, then LENGTH: which bytes of s; default all of s"))
      (doc "A raw DEFLATE stream (RFC 1951) of stored blocks: the bytes as they are, five bytes of framing a block of up to 65535. Give LENGTH for binary input: s's own length is measured to its first NUL."
        (returns LIST "(OUT N): the stream's region and its byte count")
        (example "(first (rest (Deflate stored \"abc\")))" "8"))
      (def sp (%span s span))
      (def n (first (rest sp)))
      (def out (%make-str (%stored-room n)))
      (list out (%stored! (%at (%str->ptr s) (first sp)) (%str->ptr out) 0 0 n)))
    (method zlib-stored (self (param s STRING "The bytes to carry")
                              . (param span LIST "START, then LENGTH, as for stored"))
      (doc "A zlib stream (RFC 1950) of stored blocks: the two-byte header (method 8, a 32K window, no dictionary, FCHECK making the pair a multiple of 31), the raw stream, then the Adler-32 of the bytes big-endian. What git writes a loose object as, when the writer does not compress."
        (returns LIST "(OUT N): the stream's region and its byte count")
        (example "(first (rest (Deflate zlib-stored \"abc\")))" "14"))
      (def sp (%span s span))
      (def start (first sp))
      (def n (first (rest sp)))
      (def out (%make-str (%add (%stored-room n) 6)))
      (def p (%str->ptr out))
      ; 0x78 0x01: CM 8, CINFO 7, FLEVEL 0, and 0x7801 = 31 * 991
      (%pset! p 0 120 1)
      (%pset! p 1 1 1)
      (def end (%stored! (%at (%str->ptr s) start) p 2 0 n))
      ; adler32 sums from a string's start: a span not at 0 is copied first
      (def sum
        (if (= start 0) (Inflate adler32 s n)
          (let ((c (%make-str n)))
            (do (%mem-copy (%str->ptr c) (%at (%str->ptr s) start) n)
                (Inflate adler32 c n)))))
      (%pset! p end (& (>> sum 24) 255) 1)
      (%pset! p (%add end 1) (& (>> sum 16) 255) 1)
      (%pset! p (%add end 2) (& (>> sum 8) 255) 1)
      (%pset! p (%add end 3) (& sum 255) 1)
      (list out (%add end 4)))))

(doc (provide x/codec/deflate Deflate)
  "DEFLATE streams written in pure x-lang: (Deflate stored s) a raw stream of stored blocks, (Deflate zlib-stored s) the same in zlib's wrapper; each answers (OUT N).")

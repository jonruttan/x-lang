; inflate.x -- Inflate: DEFLATE decompression (RFC 1951) in pure x-lang.
;
; git keeps every object and every pack entry DEFLATE-compressed, and a git
; written in x needs to read them where no C library is present; Zlib (x/codec/
; zlib) binds the system's libz, which such a system does not have.  This is the
; decoder as Mark Adler's puff.c, zlib's own reference, lays it out: stored,
; fixed and dynamic blocks, and canonical Huffman codes decoded a bit at a time
; against a count of codes per length.  It is the reference a compiled engine
; will be checked against, as sha.x's digests are.
;
; Input is a byte region, a start and a length, so a NUL is a byte like any
; other; output is a (str make) region that doubles as it fills, the window the
; back-references copy from.  Each call answers how many input bytes the stream
; used: git's packs hold one stream after another, and the reader goes on from
; where the last ended.
;
; Pure INT on the C bit ops, every addition through the cached int prims, as
; sha256.x's arithmetic is, so the decoder is tower-proof.  A malformed stream
; raises a label 'value naming what was wrong.
(module x/codec/inflate)

(import x/type/vector)

(def %add (prim-ref 'int '+))
(def %sub (prim-ref 'int '-))
(def %oref (prim-ref (lit obj) (lit ref)))
(def %oset! (prim-ref (lit obj) (lit set!)))
(def %pref (prim-ref (lit ptr) (lit ref)))
(def %pset! (prim-ref (lit ptr) (lit set!)))
(def %make-str (prim-ref (lit str) (lit make)))
(def %str->ptr (prim-ref (lit str) (lit ->ptr)))
(def %ptr->int (prim-ref (lit ptr) (lit ->int)))
(def %int->ptr (prim-ref (lit int) (lit ->ptr)))
(def %mem-copy (prim-ref (lit mem) (lit copy)))
(def %str-byte-len (prim-ref (lit str) (lit byte-len)))

; A stream's state, in the slots of one vector (slot k holds field k): the
; input's address, its length and how much of it is read; the bits read
; ahead and how many; the output region, its address, its size and how much
; of it is written.
(def %IN 1)
(def %INLEN 2)
(def %INCNT 3)
(def %BITBUF 4)
(def %BITCNT 5)
(def %OUT 6)
(def %OUTP 7)
(def %OUTCAP 8)
(def %OUTCNT 9)

(def %fail (fn (_ what) (Err raise (lit value) (Str8 append "Inflate: " what) ())))

(def %at (fn (_ p off) (%int->ptr (%add (%ptr->int p) off))))

; The next `need` bits, least significant first (3.1.1).
(def %bits
  (fn (_ s need)
    (let go ((val (%oref s %BITBUF)) (cnt (%oref s %BITCNT)))
      (if (< cnt need)
        (let ((i (%oref s %INCNT)))
          (do (when (= i (%oref s %INLEN)) (%fail "the input ends inside the stream"))
              (%oset! s %INCNT (%add i 1))
              (go (| val (<< (& (%pref (%oref s %IN) i 1) 255) cnt)) (%add cnt 8))))
        (do (%oset! s %BITBUF (>> val need))
            (%oset! s %BITCNT (%sub cnt need))
            (& val (%sub (<< 1 need) 1)))))))

; Room for n more output bytes: the region doubles until they fit.
(def %room!
  (fn (_ s n)
    (let ((cnt (%oref s %OUTCNT)) (cap (%oref s %OUTCAP)))
      (when (> (%add cnt n) cap)
        (let ((ncap (let grow ((c (<< cap 1))) (if (< c (%add cnt n)) (grow (<< c 1)) c))))
          (let ((r (%make-str ncap)))
            (do (when (> cnt 0) (%mem-copy (%str->ptr r) (%oref s %OUTP) cnt))
                (%oset! s %OUT r)
                (%oset! s %OUTP (%str->ptr r))
                (%oset! s %OUTCAP ncap))))))))

(def %put-byte!
  (fn (_ s b)
    (do (%room! s 1)
        (let ((cnt (%oref s %OUTCNT)))
          (do (%pset! (%oref s %OUTP) cnt b 1)
              (%oset! s %OUTCNT (%add cnt 1)))))))

; A stored block (3.2.4): to the byte boundary, LEN and its complement, then
; LEN bytes as they are.
(def %stored
  (fn (_ s)
    (do (%oset! s %BITBUF 0)
        (%oset! s %BITCNT 0)
        (let ((i (%oref s %INCNT)) (in (%oref s %IN)))
          (do (when (> (%add i 4) (%oref s %INLEN)) (%fail "the input ends inside a stored block"))
              (let ((len (| (& (%pref in i 1) 255) (<< (& (%pref in (%add i 1) 1) 255) 8)))
                    (nlen (| (& (%pref in (%add i 2) 1) 255) (<< (& (%pref in (%add i 3) 1) 255) 8))))
                (do (unless (= len (& (~ nlen) 65535)) (%fail "a stored block's length and its complement disagree"))
                    (when (> (%add (%add i 4) len) (%oref s %INLEN)) (%fail "the input ends inside a stored block"))
                    (%room! s len)
                    (%mem-copy (%at (%oref s %OUTP) (%oref s %OUTCNT)) (%at in (%add i 4)) len)
                    (%oset! s %OUTCNT (%add (%oref s %OUTCNT) len))
                    (%oset! s %INCNT (%add (%add i 4) len)))))))))

; A canonical Huffman code (3.2.2) from the code lengths of n symbols, read
; from slot off+1 of lengths on: (COUNTS SYMBOLS LEFT), COUNTS the number of
; codes of each length, SYMBOLS the symbols in code order, LEFT the codes
; left unused -- negative when the lengths ask for more codes than exist.
(def %construct
  (fn (_ lengths off n)
    (def counts (Vector make 16 0))
    (def symbols (Vector make n 0))
    (def len-of (fn (_ sym) (%oref lengths (%add (%add off sym) 1))))
    ((fn (self sym)
       (when (< sym n)
         (do (let ((k (%add (len-of sym) 1))) (%oset! counts k (%add (%oref counts k) 1)))
             (self (%add sym 1)))))
     0)
    (def left
      ((fn (self len left)
         (if (or (> len 15) (< left 0)) left
           (self (%add len 1) (%sub (<< left 1) (%oref counts (%add len 1))))))
       1 1))
    ; Over-subscribed: no table to build, and the offsets below would run
    ; past SYMBOLS.
    (if (< left 0) (list counts symbols left) (%fill-symbols lengths off n counts symbols left))))

; SYMBOLS in code order: each length's codes from offs[len] on.
(def %fill-symbols
  (fn (_ lengths off n counts symbols left)
    (def len-of (fn (_ sym) (%oref lengths (%add (%add off sym) 1))))
    ; offs[len], the index in SYMBOLS of the first code of that length
    (def offs (Vector make 16 0))
    ((fn (self len)
       (when (< len 15)
         (do (%oset! offs (%add len 2) (%add (%oref offs (%add len 1)) (%oref counts (%add len 1))))
             (self (%add len 1)))))
     1)
    ((fn (self sym)
       (when (< sym n)
         (do (let ((len (len-of sym)))
               (unless (= len 0)
                 (let ((at (%oref offs (%add len 1))))
                   (do (%oset! symbols (%add at 1) sym)
                       (%oset! offs (%add len 1) (%add at 1))))))
             (self (%add sym 1)))))
     0)
    (list counts symbols (if (= (%oref counts 1) n) 0 left))))

; The next symbol in code h, a bit at a time: a code of length len is one
; of the counts[len] codes from fst on.
(def %decode
  (fn (_ s h)
    (def counts (first h))
    (def symbols (first (rest h)))
    ((fn (self len code fst index)
       (if (> len 15) (%fail "a code no table holds")
         (let ((c (| code (%bits s 1))) (count (%oref counts (%add len 1))))
           (if (< (%sub c count) fst)
             (%oref symbols (%add (%add index (%sub c fst)) 1))
             (self (%add len 1) (<< c 1) (<< (%add fst count) 1) (%add index count))))))
     1 0 0 0)))

; Base lengths and distances, and their extra bits (3.2.5).
(def %lbase (Vector from-list (list 3 4 5 6 7 8 9 10 11 13 15 17 19 23 27 31 35 43 51 59 67 83 99 115 131 163 195 227 258)))
(def %lext (Vector from-list (list 0 0 0 0 0 0 0 0 1 1 1 1 2 2 2 2 3 3 3 3 4 4 4 4 5 5 5 5 0)))
(def %dbase (Vector from-list (list 1 2 3 4 5 7 9 13 17 25 33 49 65 97 129 193 257 385 513 769 1025 1537 2049 3073 4097 6145 8193 12289 16385 24577)))
(def %dext (Vector from-list (list 0 0 0 0 1 1 2 2 3 3 4 4 5 5 6 6 7 7 8 8 9 9 10 10 11 11 12 12 13 13)))

; Copy len bytes from dist back, a byte at a time: the two may overlap,
; and a run repeats what it has just written.
(def %copy!
  (fn (_ s dist len)
    (do (%room! s len)
        (let ((p (%oref s %OUTP)) (cnt (%oref s %OUTCNT)))
          (do ((fn (self k)
                 (when (< k len)
                   (do (%pset! p (%add cnt k) (& (%pref p (%sub (%add cnt k) dist) 1) 255) 1)
                       (self (%add k 1)))))
               0)
              (%oset! s %OUTCNT (%add cnt len)))))))

; A block's literals, lengths and distances, to its end code (256).
(def %codes
  (fn (_ s lencode distcode)
    ((fn (self)
       (let ((sym (%decode s lencode)))
         (match
           ((< sym 256) (do (%put-byte! s sym) (self)))
           ((= sym 256) ())
           ((> sym 285) (%fail "a length code out of range"))
           (#t
             (let ((k (%add (%sub sym 257) 1)))
               (let ((len (%add (%oref %lbase k) (%bits s (%oref %lext k))))
                     (dsym (%decode s distcode)))
                 (do (when (> dsym 29) (%fail "a distance code out of range"))
                     (let ((dist (%add (%oref %dbase (%add dsym 1)) (%bits s (%oref %dext (%add dsym 1))))))
                       (do (when (> dist (%oref s %OUTCNT)) (%fail "a distance too far back"))
                           (%copy! s dist len)
                           (self)))))))))))))

; The fixed codes (3.2.6), made once, when first wanted.
(def %fixed-codes ())
(def %fixed
  (fn (_ s)
    (do (when (null? %fixed-codes)
          (let ((lengths (Vector make 288 0)) (dists (Vector make 30 5)))
            (do ((fn (self sym)
                   (when (< sym 288)
                     (do (%oset! lengths (%add sym 1)
                           (match ((< sym 144) 8) ((< sym 256) 9) ((< sym 280) 7) (#t 8)))
                         (self (%add sym 1)))))
                 0)
                (set! %fixed-codes (pair (%construct lengths 0 288) (%construct dists 0 30))))))
        (%codes s (first %fixed-codes) (rest %fixed-codes)))))

; The order the code-length code's lengths come in (3.2.7).
(def %order (list 16 17 18 0 8 7 9 6 10 5 11 4 12 3 13 2 14 1 15))

; A code is fit to decode with when it is complete, or is the one code of
; a single symbol (a distance code of one length, say).
(def %usable?
  (fn (_ h n) (or (= (first (rest (rest h))) 0) (= (%sub n (%oref (first h) 1)) 1))))

; A dynamic block (3.2.7): its codes first, coded themselves.
(def %dynamic
  (fn (_ s)
    (def nlen (%add (%bits s 5) 257))
    (def ndist (%add (%bits s 5) 1))
    (def ncode (%add (%bits s 4) 4))
    (when (or (> nlen 286) (> ndist 30)) (%fail "more codes than a block can have"))
    (def lengths (Vector make 320 0))
    ((fn (self i order)
       (when (< i ncode)
         (do (%oset! lengths (%add (first order) 1) (%bits s 3))
             (self (%add i 1) (rest order)))))
     0 %order)
    (def lencode (%construct lengths 0 19))
    (unless (= (first (rest (rest lencode))) 0) (%fail "an incomplete code-length code"))
    (def total (%add nlen ndist))
    ((fn (self index)
       (when (< index total)
         (let ((sym (%decode s lencode)))
           (if (< sym 16)
             (do (%oset! lengths (%add index 1) sym) (self (%add index 1)))
             (let ((len (if (= sym 16)
                          (if (= index 0) (%fail "a repeat with nothing before it")
                            (%oref lengths index))
                          0))
                   (times (match ((= sym 16) (%add 3 (%bits s 2)))
                                 ((= sym 17) (%add 3 (%bits s 3)))
                                 (#t (%add 11 (%bits s 7))))))
               (do (when (> (%add index times) total) (%fail "lengths past the code's end"))
                   ((fn (fill k)
                      (when (< k times)
                        (do (%oset! lengths (%add (%add index k) 1) len) (fill (%add k 1)))))
                    0)
                   (self (%add index times))))))))
     0)
    (when (= (%oref lengths 257) 0) (%fail "no end-of-block code"))
    (def lcode (%construct lengths 0 nlen))
    (unless (and (>= (first (rest (rest lcode))) 0) (%usable? lcode nlen))
      (%fail "an incomplete literal/length code"))
    (def dcode (%construct lengths nlen ndist))
    (unless (and (>= (first (rest (rest dcode))) 0) (%usable? dcode ndist))
      (%fail "an incomplete distance code"))
    (%codes s lcode dcode)))

; The whole of a raw stream from byte `start` of in: (OUT N USED).
(def %raw
  (fn (_ in start inlen)
    (def s (Vector make 9 0))
    (%oset! s %IN (%at (%str->ptr in) start))
    (%oset! s %INLEN inlen)
    (def cap (if (< inlen 256) 1024 (<< inlen 2)))
    (def out (%make-str cap))
    (%oset! s %OUT out)
    (%oset! s %OUTP (%str->ptr out))
    (%oset! s %OUTCAP cap)
    ((fn (self)
       (let ((last (%bits s 1)) (type (%bits s 2)))
         (do (match
               ((= type 0) (%stored s))
               ((= type 1) (%fixed s))
               ((= type 2) (%dynamic s))
               (#t (%fail "a block of type 3")))
             (when (= last 0) (self))))))
    (list (%oref s %OUT) (%oref s %OUTCNT) (%oref s %INCNT))))

; Adler-32 (RFC 1950 8) of n bytes at p: each sum stays under 65521 by one
; subtraction a byte, since neither can pass twice that.
(def %adler32
  (fn (_ p n)
    ((fn (self i a b)
       (if (= i n) (| (<< b 16) a)
         (let ((a1 (%add a (& (%pref p i 1) 255))))
           (let ((a2 (if (>= a1 65521) (%sub a1 65521) a1)))
             (let ((b1 (%add b a2)))
               (self (%add i 1) a2 (if (>= b1 65521) (%sub b1 65521) b1)))))))
     0 1 0)))

(def %int-mod (prim-ref (lit int) (lit %)))

; A zlib stream (RFC 1950): the two-byte header, a raw stream, then the
; Adler-32 of what it holds, big-endian.
(def %zlib
  (fn (_ in start inlen)
    (def p (%at (%str->ptr in) start))
    (when (< inlen 6) (%fail "too short for a zlib stream"))
    (def cmf (& (%pref p 0 1) 255))
    (def flg (& (%pref p 1 1) 255))
    (unless (= (& cmf 15) 8) (%fail "not DEFLATE (the zlib header's method is not 8)"))
    (when (> (>> cmf 4) 7) (%fail "a window larger than 32K"))
    (unless (= (%int-mod (| (<< cmf 8) flg) 31) 0) (%fail "the zlib header's check fails"))
    (unless (= (& flg 32) 0) (%fail "a preset dictionary, which this does not take"))
    (def r (%raw in (%add start 2) (%sub inlen 2)))
    (def at (%add 2 (first (rest (rest r)))))
    (when (> (%add at 4) inlen) (%fail "the input ends before the Adler-32"))
    (def want (| (<< (& (%pref p at 1) 255) 24)
                 (| (<< (& (%pref p (%add at 1) 1) 255) 16)
                    (| (<< (& (%pref p (%add at 2) 1) 255) 8)
                       (& (%pref p (%add at 3) 1) 255)))))
    (unless (= want (%adler32 (%str->ptr (first r)) (first (rest r))))
      (%fail "the Adler-32 does not match"))
    (list (first r) (first (rest r)) (%add at 4))))

; START and LENGTH from an optional span, defaulting to the whole string.
(def %span
  (fn (_ s span)
    (match
      ((null? span) (list 0 (%str-byte-len s)))
      ((null? (rest span)) (list (first span) (%sub (%str-byte-len s) (first span))))
      (#t (list (first span) (first (rest span)))))))

(def-class Inflate ()
  (doc "DEFLATE decompression in pure x-lang: raw streams (RFC 1951) and zlib streams (RFC 1950). Each answers (OUT N USED): OUT a byte region holding the N bytes decompressed, USED how many input bytes the stream took, so a reader of streams laid end to end goes on from there.")
  (static
    (method raw (self (param s STRING "Bytes holding a raw DEFLATE stream")
                      . (param span LIST "START, then LENGTH: where the stream starts in s and how many bytes of s it may use; default all of s"))
      (doc "Decompress a raw DEFLATE stream (RFC 1951). Raises a label 'value naming what is wrong with a malformed one. Give LENGTH for binary input: s's own length is measured to its first NUL."
        (returns LIST "(OUT N USED): the output region, its byte count, and the input bytes the stream used"))
      (def sp (%span s span))
      (%raw s (first sp) (first (rest sp))))
    (method zlib (self (param s STRING "Bytes holding a zlib stream")
                       . (param span LIST "START, then LENGTH, as for raw"))
      (doc "Decompress a zlib stream (RFC 1950): its header checked, then a raw stream, then its Adler-32 checked against what came out. Raises a label 'value on any of them failing."
        (returns LIST "(OUT N USED), as for raw; USED includes the header and the Adler-32"))
      (def sp (%span s span))
      (%zlib s (first sp) (first (rest sp))))
    (method adler32 (self (param s STRING "Bytes") (param n INTEGER "How many of them"))
      (doc "The Adler-32 checksum (RFC 1950) of the first n bytes of s."
        (returns INTEGER "The checksum")
        (example "(Inflate adler32 \"Wikipedia\" 9)" "300286872"))
      (%adler32 (%str->ptr s) n))))

(doc (provide x/codec/inflate Inflate)
  "DEFLATE decompression (RFC 1951) and the zlib wrapper (RFC 1950) in pure x-lang: (Inflate zlib s) answers (OUT N USED).")

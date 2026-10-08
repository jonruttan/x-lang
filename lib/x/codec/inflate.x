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
; The compiled engine is on Compiled's list.
(import x/tool/compiled)

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

; The comparisons and bit operations of the hot paths go through the int
; doors: the generic ones dispatch through the tower and cost a hundred
; objects or more a call, these none.  Every operand on those paths is an
; int.  There is no int > or >=: a > b is written (%lt b a).
(def %lt (prim-ref (lit int) (lit <)))
(def %eq (prim-ref (lit int) (lit =)))
(def %and (prim-ref (lit int) (lit &)))
(def %or (prim-ref (lit int) (lit |)))
(def %shl (prim-ref (lit int) (lit <<)))
(def %shr (prim-ref (lit int) (lit >>)))

; A stream's state, in the slots of one vector (slot k holds field k): the
; input's address, its length and how much of it is read; the bits read
; ahead and how many; the output region, its address, its size and how much
; of it is written; and the function that decodes a block's codes, this
; file's or the compiled engine's.
(def %IN 1)
(def %INLEN 2)
(def %INCNT 3)
(def %BITBUF 4)
(def %BITCNT 5)
(def %OUT 6)
(def %OUTP 7)
(def %OUTCAP 8)
(def %OUTCNT 9)
(def %CODES 10)

(def %fail (fn (_ what) (Err raise (lit value) (Str8 append "Inflate: " what) ())))

(def %at (fn (_ p off) (%int->ptr (%add (%ptr->int p) off))))

; The paths below run once a bit, a symbol or a byte, so they are written
; in primitives alone: def in a body, if, do and self-calls of top-level
; functions.  A let, a named let, a when or an inner closure costs a frame
; or a pair each time through, and the decoder spent most of its objects
; on them (2026-10-08: a 136-byte loose git commit cost 2.1M objects).

; Bytes read ahead into the bit buffer until it holds `need` bits.
(def %fill!
  (fn (self s need)
    (def cnt (%oref s %BITCNT))
    (if (%lt cnt need)
      (do (def i (%oref s %INCNT))
          (if (%eq i (%oref s %INLEN)) (%fail "the input ends inside the stream") ())
          (%oset! s %INCNT (%add i 1))
          (%oset! s %BITBUF (%or (%oref s %BITBUF) (%shl (%and (%pref (%oref s %IN) i 1) 255) cnt)))
          (%oset! s %BITCNT (%add cnt 8))
          (self s need))
      ())))

; The next `need` bits, least significant first (3.1.1).
(def %bits
  (fn (_ s need)
    (%fill! s need)
    (def val (%oref s %BITBUF))
    (%oset! s %BITBUF (%shr val need))
    (%oset! s %BITCNT (%sub (%oref s %BITCNT) need))
    (%and val (%sub (%shl 1 need) 1))))

; Bytes read ahead until the buffer holds `need` bits, or the input is
; used up: a look at the bits to come, which the end of the input does
; not refuse.  What is short reads as zeros; see %decode.
(def %fill-upto!
  (fn (self s need)
    (def cnt (%oref s %BITCNT))
    (if (%lt cnt need)
      (do (def i (%oref s %INCNT))
          (if (%eq i (%oref s %INLEN)) ()
            (do (%oset! s %INCNT (%add i 1))
                (%oset! s %BITBUF (%or (%oref s %BITBUF) (%shl (%and (%pref (%oref s %IN) i 1) 255) cnt)))
                (%oset! s %BITCNT (%add cnt 8))
                (self s need))))
      ())))

; The whole bytes a look read ahead given back to the input: the count of
; input used steps back over them.  What stays in the buffer is the rest
; of the byte in hand, and that is what the end of a block discards.
(def %unread-bytes!
  (fn (_ s)
    (def back (%shr (%oref s %BITCNT) 3))
    (if (%lt 0 back)
      (do (%oset! s %INCNT (%sub (%oref s %INCNT) back))
          (%oset! s %BITCNT (%sub (%oref s %BITCNT) (%shl back 3)))
          (%oset! s %BITBUF (%and (%oref s %BITBUF) (%sub (%shl 1 (%oref s %BITCNT)) 1))))
      ())))

; The output region doubled from ncap until `need` bytes fit.
(def %grow!
  (fn (self s need ncap)
    (if (%lt ncap need) (self s need (%shl ncap 1))
      (do (def r (%make-str ncap))
          (def cnt (%oref s %OUTCNT))
          (if (%lt 0 cnt) (%mem-copy (%str->ptr r) (%oref s %OUTP) cnt) ())
          (%oset! s %OUT r)
          (%oset! s %OUTP (%str->ptr r))
          (%oset! s %OUTCAP ncap)))))

; Room for n more output bytes.
(def %room!
  (fn (_ s n)
    (def need (%add (%oref s %OUTCNT) n))
    (def cap (%oref s %OUTCAP))
    (if (%lt cap need) (%grow! s need (%shl cap 1)) ())))

(def %put-byte!
  (fn (_ s b)
    (%room! s 1)
    (def cnt (%oref s %OUTCNT))
    (%pset! (%oref s %OUTP) cnt b 1)
    (%oset! s %OUTCNT (%add cnt 1))))

; A stored block (3.2.4): to the byte boundary, LEN and its complement, then
; LEN bytes as they are.
(def %stored
  (fn (_ s)
    (do (%unread-bytes! s)
        (%oset! s %BITBUF 0)
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
; from slot off+1 of lengths on: (COUNTS SYMBOLS LEFT TABLE), COUNTS the
; number of codes of each length, SYMBOLS the symbols in code order, LEFT
; the codes left unused -- negative when the lengths ask for more codes
; than exist, and then no TABLE (below) follows.
; COUNTS tallied: counts[len] the number of symbols from sym on of length len.
(def %count-lengths!
  (fn (self lengths off n sym counts)
    (if (%lt sym n)
      (do (def k (%add (%oref lengths (%add (%add off sym) 1)) 1))
          (%oset! counts k (%add (%oref counts k) 1))
          (self lengths off n (%add sym 1) counts))
      ())))

; The codes left unused after lengths 1..15 take theirs, from `left` at
; length len: negative as soon as the lengths over-subscribe.
(def %codes-left
  (fn (self counts len left)
    (if (%lt 15 len) left
      (if (%lt left 0) left
        (self counts (%add len 1) (%sub (%shl left 1) (%oref counts (%add len 1))))))))

(def %construct
  (fn (_ lengths off n)
    (def counts (Vector make 16 0))
    (def symbols (Vector make n 0))
    (%count-lengths! lengths off n 0 counts)
    (def left (%codes-left counts 1 1))
    ; Over-subscribed: no table to build, and the offsets below would run
    ; past SYMBOLS.
    (if (< left 0) (list counts symbols left) (%fill-symbols lengths off n counts symbols left))))

; offs[len] from length len on: the index in SYMBOLS of the first code of
; each length.
(def %offsets!
  (fn (self counts offs len)
    (if (%lt len 15)
      (do (%oset! offs (%add len 2) (%add (%oref offs (%add len 1)) (%oref counts (%add len 1))))
          (self counts offs (%add len 1)))
      ())))

; Each symbol from sym on of a nonzero length placed at its length's offset.
(def %place-symbols!
  (fn (self lengths off n sym offs symbols)
    (if (%lt sym n)
      (do (def len (%oref lengths (%add (%add off sym) 1)))
          (if (%eq len 0) ()
            (do (def at (%oref offs (%add len 1)))
                (%oset! symbols (%add at 1) sym)
                (%oset! offs (%add len 1) (%add at 1))))
          (self lengths off n (%add sym 1) offs symbols))
      ())))

; --- The lookup table ---
;
; A code's TABLE answers the next symbol from the next BITS bits of input
; at once, where puff.c walks the code a bit at a time against the counts.
; BITS is the code's longest length up to %TBITS.  Slot b+1 holds, for the
; BITS bits b as they sit in the buffer (the code's first bit lowest), the
; symbol and its code length as SYM<<4|LEN: 0 where no code begins so,
; %WALK where a code longer than BITS does, which the walk then reads from
; its first bit.  A code of LEN bits fills every slot whose low LEN bits
; are its own, reversed.

(def %TBITS 9)
(def %WALK 15)

; The 9-bit reversal, once: slot i+1 holds the bits of i in the other
; order, each entry from the one below it.
(def %rev9 (Vector make 512 0))
((fn (self i)
   (if (%lt i 512)
     (do (%oset! %rev9 (%add i 1) (%or (%shr (%oref %rev9 (%add (%shr i 1) 1)) 1) (%shl (%and i 1) 8)))
         (self (%add i 1)))
     ()))
 1)

; The low len bits of code (len up to 9), reversed.
(def %reverse-bits
  (fn (_ code len) (%shr (%oref %rev9 (%add code 1)) (%sub %TBITS len))))

; Slots at, at+step, ... of table, up to size, set to entry.
(def %fill-entries!
  (fn (self table size at step entry)
    (if (%lt at size)
      (do (%oset! table (%add at 1) entry)
          (self table size (%add at step) step entry))
      ())))

; The `count` codes of length len from `code` on, their symbols from slot
; index+1 of symbols on, entered in a table of bits bits.
(def %fill-codes!
  (fn (self table bits symbols len code index count)
    (if (%lt 0 count)
      (do (if (%lt bits len)
            (%fill-entries! table (%shl 1 bits) (%reverse-bits (%shr code (%sub len bits)) bits) (%shl 1 bits) %WALK)
            (%fill-entries! table (%shl 1 bits) (%reverse-bits code len) (%shl 1 len)
              (%or (%shl (%oref symbols (%add index 1)) 4) len)))
          (self table bits symbols len (%add code 1) (%add index 1) (%sub count 1)))
      ())))

; Every length's codes entered, from length len, whose first code is
; `code` and whose first symbol sits at index: the canonical code (3.2.2),
; each length's first code the one past the length before's last, doubled.
(def %fill-table!
  (fn (self table bits counts symbols len code index)
    (if (%lt 15 len) ()
      (do (def count (%oref counts (%add len 1)))
          (%fill-codes! table bits symbols len code index count)
          (self table bits counts symbols (%add len 1) (%shl (%add code count) 1) (%add index count))))))

; The longest length up to %TBITS that counts has a code of, from len down.
(def %table-bits
  (fn (self counts len)
    (if (%eq len 0) 0
      (if (%lt 0 (%oref counts (%add len 1))) len (self counts (%sub len 1))))))

; SYMBOLS in code order: each length's codes from offs[len] on; then the
; table over both.
(def %fill-symbols
  (fn (_ lengths off n counts symbols left)
    (def offs (Vector make 16 0))
    (%offsets! counts offs 1)
    (%place-symbols! lengths off n 0 offs symbols)
    (def bits (%table-bits counts %TBITS))
    (def table (Vector make (%shl 1 bits) 0))
    (%fill-table! table bits counts symbols 1 0 0)
    (list counts symbols (if (= (%oref counts 1) n) 0 left) table (%sub (%shl 1 bits) 1))))

; The TABLE of a code h, (COUNTS SYMBOLS LEFT TABLE MASK), and the MASK
; that picks its slot from the bits in hand.
(def %table (fn (_ h) (first (rest (rest (rest h))))))
(def %table-mask (fn (_ h) (first (rest (rest (rest (rest h)))))))

; The symbol whose code begins with `code`, read on from length len: a code
; of length len is one of the counts[len] codes from fst on.
(def %decode-from
  (fn (self s counts symbols len code fst index)
    (if (%lt 15 len) (%fail "a code no table holds")
      (do (def c (%or code (%bits s 1)))
          (def count (%oref counts (%add len 1)))
          (if (%lt (%sub c count) fst)
            (%oref symbols (%add (%add index (%sub c fst)) 1))
            (self s counts symbols (%add len 1) (%shl c 1) (%shl (%add fst count) 1) (%add index count)))))))

; The next symbol in code h through its table: the next %TBITS bits looked
; at, not yet read, name the entry; the symbol's own bits are then read.
; A code longer than the table is walked from its first bit, which is
; still unread.  Short of the stream's end the look pads with zeros, and
; the entry those pick is right or refused: a code of LEN bits that the
; bits in hand begin is the one code they begin, whatever follows; one
; longer than the bits in hand ends inside the stream.
(def %decode-with
  (fn (_ s h table mask)
    (%fill-upto! s %TBITS)
    (def e (%oref table (%add (%and (%oref s %BITBUF) mask) 1)))
    (def len (%and e 15))
    (match
      ((%eq len 0) (%fail "a code no table holds"))
      ((%eq len %WALK) (%decode-from s (first h) (first (rest h)) 1 0 0 0))
      ((%lt (%oref s %BITCNT) len) (%fail "the input ends inside the stream"))
      (#t (do (%oset! s %BITBUF (%shr (%oref s %BITBUF) len))
              (%oset! s %BITCNT (%sub (%oref s %BITCNT) len))
              (%shr e 4))))))

; The next symbol in code h.
(def %decode
  (fn (_ s h) (%decode-with s h (%table h) (%table-mask h))))

; Base lengths and distances, and their extra bits (3.2.5).
(def %lbase (Vector from-list (list 3 4 5 6 7 8 9 10 11 13 15 17 19 23 27 31 35 43 51 59 67 83 99 115 131 163 195 227 258)))
(def %lext (Vector from-list (list 0 0 0 0 0 0 0 0 1 1 1 1 2 2 2 2 3 3 3 3 4 4 4 4 5 5 5 5 0)))
(def %dbase (Vector from-list (list 1 2 3 4 5 7 9 13 17 25 33 49 65 97 129 193 257 385 513 769 1025 1537 2049 3073 4097 6145 8193 12289 16385 24577)))
(def %dext (Vector from-list (list 0 0 0 0 1 1 2 2 3 3 4 4 5 5 6 6 7 7 8 8 9 9 10 10 11 11 12 12 13 13)))

; Copy len bytes from dist back, a byte at a time: the two may overlap,
; and a run repeats what it has just written.
(def %copy-bytes!
  (fn (self p at dist k len)
    (if (%lt k len)
      (do (%pset! p (%add at k) (%and (%pref p (%sub (%add at k) dist) 1) 255) 1)
          (self p at dist (%add k 1) len))
      ())))

(def %copy!
  (fn (_ s dist len)
    (%room! s len)
    (def cnt (%oref s %OUTCNT))
    (%copy-bytes! (%oref s %OUTP) cnt dist 0 len)
    (%oset! s %OUTCNT (%add cnt len))))

; A length/distance pair from length symbol sym (257..285): the copy done.
(def %copy-coded!
  (fn (_ s sym distcode)
    (def k (%add (%sub sym 257) 1))
    (def len (%add (%oref %lbase k) (%bits s (%oref %lext k))))
    (def dsym (%decode s distcode))
    (if (%lt 29 dsym) (%fail "a distance code out of range") ())
    (def dist (%add (%oref %dbase (%add dsym 1)) (%bits s (%oref %dext (%add dsym 1)))))
    (if (%lt (%oref s %OUTCNT) dist) (%fail "a distance too far back") ())
    (%copy! s dist len)))

; The codes loop proper, the literal/length table in hand.
(def %codes-loop
  (fn (self s lencode distcode ltable lmask)
    (def sym (%decode-with s lencode ltable lmask))
    (match
      ((%lt sym 256) (do (%put-byte! s sym) (self s lencode distcode ltable lmask)))
      ((%eq sym 256) ())
      ((%lt 285 sym) (%fail "a length code out of range"))
      (#t (do (%copy-coded! s sym distcode) (self s lencode distcode ltable lmask))))))

; A block's literals, lengths and distances, to its end code (256).
(def %codes-x
  (fn (_ s lencode distcode)
    (%codes-loop s lencode distcode (%table lencode) (%table-mask lencode))))

; The fixed codes (3.2.6), made once, when first wanted.
(def %fixed-codes ())

; The literal/length code lengths from sym on: 8 to 143, 9 to 255, 7 to
; 279, 8 to 287.
(def %fixed-lengths!
  (fn (self lengths sym)
    (if (%lt sym 288)
      (do (%oset! lengths (%add sym 1)
            (if (%lt sym 144) 8 (if (%lt sym 256) 9 (if (%lt sym 280) 7 8))))
          (self lengths (%add sym 1)))
      ())))

(def %fixed
  (fn (_ s)
    (if (null? %fixed-codes)
      (do (def lengths (Vector make 288 0))
          (%fixed-lengths! lengths 0)
          (set! %fixed-codes (pair (%construct lengths 0 288) (%construct (Vector make 30 5) 0 30))))
      ())
    ((%oref s %CODES) s (first %fixed-codes) (rest %fixed-codes))))

; The order the code-length code's lengths come in (3.2.7).
(def %order (list 16 17 18 0 8 7 9 6 10 5 11 4 12 3 13 2 14 1 15))

; A code is fit to decode with when it is complete, or is the one code of
; a single symbol (a distance code of one length, say).
(def %usable?
  (fn (_ h n) (or (= (first (rest (rest h))) 0) (= (%sub n (%oref (first h) 1)) 1))))

; Slots index+1 .. index+times of lengths set to len.
(def %repeat!
  (fn (self lengths index len k times)
    (if (%lt k times)
      (do (%oset! lengths (%add (%add index k) 1) len)
          (self lengths index len (%add k 1) times))
      ())))

; The code lengths of a dynamic block's two codes, read from `index` to
; `total` through the code-length code: a length as itself (0..15), or a
; repeat of the one before (16), or a run of zeros (17, 18).
(def %read-lengths!
  (fn (self s lencode lengths index total)
    (if (%lt index total)
      (do (def sym (%decode s lencode))
          (if (%lt sym 16)
            (do (%oset! lengths (%add index 1) sym)
                (self s lencode lengths (%add index 1) total))
            (do (def len (if (%eq sym 16)
                           (if (%eq index 0) (%fail "a repeat with nothing before it")
                             (%oref lengths index))
                           0))
                (def times (match ((%eq sym 16) (%add 3 (%bits s 2)))
                                  ((%eq sym 17) (%add 3 (%bits s 3)))
                                  (#t (%add 11 (%bits s 7)))))
                (if (%lt total (%add index times)) (%fail "lengths past the code's end") ())
                (%repeat! lengths index len 0 times)
                (self s lencode lengths (%add index times) total))))
      ())))

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
    (%read-lengths! s lencode lengths 0 (%add nlen ndist))
    (when (= (%oref lengths 257) 0) (%fail "no end-of-block code"))
    (def lcode (%construct lengths 0 nlen))
    (unless (and (>= (first (rest (rest lcode))) 0) (%usable? lcode nlen))
      (%fail "an incomplete literal/length code"))
    (def dcode (%construct lengths nlen ndist))
    (unless (and (>= (first (rest (rest dcode))) 0) (%usable? dcode ndist))
      (%fail "an incomplete distance code"))
    ((%oref s %CODES) s lcode dcode)))

; The whole of a raw stream from byte `start` of in: (OUT N USED), each
; block's codes decoded by codes.
(def %raw
  (fn (_ in start inlen codes)
    (def s (Vector make 10 0))
    (%oset! s %CODES codes)
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
    (%unread-bytes! s)
    (list (%oref s %OUT) (%oref s %OUTCNT) (%oref s %INCNT))))

; Adler-32 (RFC 1950 8) of n bytes at p: each sum stays under 65521 by one
; subtraction a byte, since neither can pass twice that.
(def %adler-sum
  (fn (self p n i a b)
    (if (%eq i n) (%or (%shl b 16) a)
      (do (def a1 (%add a (%and (%pref p i 1) 255)))
          (def a2 (if (%lt a1 65521) a1 (%sub a1 65521)))
          (def b1 (%add b a2))
          (self p n (%add i 1) a2 (if (%lt b1 65521) b1 (%sub b1 65521)))))))

(def %adler32-x
  (fn (_ p n) (%adler-sum p n 0 1 0)))

; --- The compiled engine (JIT), adopted only when it proves out ------
;
; x/codec/inflate-jit compiles the codes loop and the Adler-32; the rest
; stays here.  As the digests' engines are, it is an entry of Compiled's
; made on demand, built for an input of %jit-threshold bytes or more or on
; (Inflate jit!), and adopted only after decoding and summing the streams
; below exactly as %codes-x and %adler32-x do.  The entry's value is a pair,
; (CODES . ADLER): this file's two, or the engine's.

; Raw streams written by gzip -9: a fixed-code block of 26 bytes, and a
; dynamic-code block of 3000 (every length and distance class the codes
; loop branches on).
(def %check-streams
  (list "cb48cdc9c9d751c840a214caf38b7252b800"
        (Str8 append
          "edce8b0100110800d05943447e4567fd5ba437c183804de2c43b1b515b96379e"
          "4e9890c62d4a4f06f7a9500fbdcd5488059a71bcb29658eaafc733b9f575d380"
          "59e0aa5ea01d57fe64cda5af6cd4969e19209fac359a8a5ae44b364a0c21d1fc"
          "ea3732d8b550e663d85c100b4b1c61d704e0410f7ad0831ef4a0073de8410f7a"
          "f007")))

(def %region
  (fn (_ bytes)
    (let ((r (%make-str (List length bytes))))
      (do ((fn (self i l) (unless (null? l) (do (%pset! (%str->ptr r) i (first l) 1) (self (%add i 1) (rest l)))))
           0 bytes)
          r))))

; Does an engine (CODES . ADLER) decode every check stream as %codes-x
; does, byte for byte, and sum each output as %adler32-x does?
(def %agrees?
  (fn (_ engine)
    (import x/codec/hex)
    (List all?
      (fn (_ hex)
        (let ((bytes (Hex decode-bytes hex)))
          (let ((in (%region bytes)) (n (List length bytes)))
            (let ((want (%raw in 0 n %codes-x)) (got (%raw in 0 n (first engine))))
              (and (= (first (rest want)) (first (rest got)))
                   (= (first (rest (rest want))) (first (rest (rest got))))
                   (= 0 (%mem-cmp (%str->ptr (first want)) (%str->ptr (first got)) (first (rest want))))
                   (= (%adler32-x (%str->ptr (first want)) (first (rest want)))
                      ((rest engine) (%str->ptr (first got)) (first (rest got)))))))))
      %check-streams)))

(def %mem-cmp (prim-ref (lit mem) (lit cmp)))

; THE BAR, measured 2026-10-08, arm64: the zlib path decodes and sums 7.4KB
; of output a second in pure x (16KB in 2.22s) and ~485KB/s through the
; engine (64KB in 135ms); the build is ~2.8s with the asm cache warm, 7.2s
; cold, so it repays itself past ~20KB of output.  The bar is on the input,
; which is all a caller knows beforehand: at text's ~3:1, 4KB of input.
(def %entry ())
(def %jit-threshold 4096)

(def %jit-try!
  (fn (_)
    (when (null? %entry)
      (set! %entry
        (Compiled make-on-demand (lit inflate) (pair %codes-x %adler32-x)
          (fn (_)
            (import x/codec/inflate-jit)
            ((prim-ref (lit inflate) (lit jit-make))
             (list (pair (lit in) %IN) (pair (lit inlen) %INLEN) (pair (lit incnt) %INCNT)
                   (pair (lit bitbuf) %BITBUF) (pair (lit bitcnt) %BITCNT)
                   (pair (lit outp) %OUTP) (pair (lit outcap) %OUTCAP) (pair (lit outcnt) %OUTCNT))
             %room! %agrees?))
          (fn (_ v) ()))))
    ((fn (_ entry)
       (when (eq? (entry state) (lit interpreted)) (entry compile!))
       (eq? (entry state) (lit compiled)))
     %entry)))

; (CODES . ADLER) for n bytes of input: the engine's when it is built, or
; when n is past the bar and a build succeeds; else this file's.
(def %engine-for
  (fn (_ n)
    (do (when (and (>= n %jit-threshold)
                   ((fn (_ entry) (if (null? entry) #t (eq? (entry state) (lit interpreted)))) %entry))
          (%jit-try!))
        ((fn (_ entry)
           (if (if (null? entry) #f (eq? (entry state) (lit compiled)))
             (entry compiled)
             (pair %codes-x %adler32-x)))
         %entry))))

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
    (def engine (%engine-for inlen))
    (def r (%raw in (%add start 2) (%sub inlen 2) (first engine)))
    (def at (%add 2 (first (rest (rest r)))))
    (when (> (%add at 4) inlen) (%fail "the input ends before the Adler-32"))
    (def want (| (<< (& (%pref p at 1) 255) 24)
                 (| (<< (& (%pref p (%add at 1) 1) 255) 16)
                    (| (<< (& (%pref p (%add at 2) 1) 255) 8)
                       (& (%pref p (%add at 3) 1) 255)))))
    (unless (= want ((rest engine) (%str->ptr (first r)) (first (rest r))))
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
      (%raw s (first sp) (first (rest sp)) (first (%engine-for (first (rest sp))))))
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
      ((rest (%engine-for n)) (%str->ptr s) n))
    (method jit! (self)
      (doc "Build and adopt the compiled codes loop and Adler-32 (JIT; ARM64 and x86-64 backends) now, if they decode and sum the check streams exactly as the pure-x ones do. Idempotent. Answers #t when the engine is active, #f when unavailable -- the pure-x decoder carries on, with the same output. raw and zlib build it on their own for an input of 4KB or more."
        (returns BOOL "#t when the compiled engine is active"))
      (%jit-try!))))

(doc (provide x/codec/inflate Inflate)
  "DEFLATE decompression (RFC 1951) and the zlib wrapper (RFC 1950) in pure x-lang, with a differentially-verified compiled engine for the codes loop: (Inflate zlib s) answers (OUT N USED).")

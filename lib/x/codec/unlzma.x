; unlzma.x -- Unlzma: lzma decompression in pure x-lang.
;
; Reads the .lzma "alone" format, as busybox's unlzma, lzcat and `lzma -d`
; do (archival/libarchive/decompress_unlzma.c, Aurelien Jacobs's small
; decoder after Igor Pavlov's LZMA SDK 4.22).  A stream is a 13-byte
; header -- one byte packing lc, lp and pb, the dictionary size as LE32,
; the output size as LE64 -- and then the range coder's bytes.
;
; LZMA codes every decision as a bit through an adaptive binary range
; coder: a probability per context, 11 bits wide, moved a fifth of the way
; to its bound by each bit it codes.  A decision is a literal byte or a
; match -- a length and a distance, the distance either coded outright or
; one of the last four used again.  Twelve states remember what the recent
; decisions were, and the state is what picks the context.
;
; The decoded bytes are the dictionary: a match reads the window behind the
; write position.  The window is the header's dictionary size, grown to it
; as the output grows rather than taken whole at the start, and it wraps --
; a distance reaching past the start of the window reads its end, which
; holds data once the window has wrapped.  Where busybox reads
; uninitialized memory for a distance that names bytes it never wrote, this
; raises on it.
;
; The range coder and the symbol decoders know nothing of the alone format:
; they read a probability index and the state vector, so the .xz
; container's LZMA2 can drive them a chunk at a time without a second copy
; of the coder.
;
; This file's decoder is the reference.  x/codec/unlzma-jit compiles the
; decisions, and it is adopted only once it agrees with this one (below).
(module x/codec/unlzma)

(import x/type/vector)
(import x/tool/compiled)
(import x/num/u32 u32-srl)

(import x/core/doors int% int& int* int+ int- int->ptr int/ int< int<< int= int>> int| mem-cmp mem-copy obj-ref obj-set! ptr->int ptr-ref ptr-set! str->ptr str-byte-len str-make)

; The one coordinate the doors module does not carry.  There is no int >
; or >= either: a > b is (int< b a).
(def %mem-set (prim-ref (lit mem) (lit set)))

; Every bit of a 32-bit pattern, spelled in hex because hex reads the bits:
; -1 where the word is 32 bits, 4294967295 where it is 64.  The decimal
; would be a number, and on a 32-bit word a number that large is a Bigint
; once Bigint is loaded, which no integer door can mask with.
(def %M32 0xFFFFFFFF)

; --- the range coder's shape ------------------------------------------------

(def %MODEL-BITS 11)
(def %MODEL-TOTAL (int<< 1 %MODEL-BITS))
(def %MOVE-BITS 5)
(def %TOP (int<< 1 24))

; --- the probability layout, derived as the decoder's own enum derives it ---

(def %NSTATES 12)
(def %NLITSTATES 7)
(def %POSBITSMAX 4)
(def %MATCHMINLEN 2)
(def %LITSIZE 768)

(def %LEN-LOW-BITS 3)
(def %LEN-MID-BITS 3)
(def %LEN-HIGH-BITS 8)

; A length coder's own entries, from its base.
(def %LEN-CHOICE 0)
(def %LEN-CHOICE-2 (int+ %LEN-CHOICE 1))
(def %LEN-LOW (int+ %LEN-CHOICE-2 1))
(def %LEN-MID (int+ %LEN-LOW (int<< 1 (int+ %POSBITSMAX %LEN-LOW-BITS))))
(def %LEN-HIGH (int+ %LEN-MID (int<< 1 (int+ %POSBITSMAX %LEN-MID-BITS))))
(def %NUM-LEN-PROBS (int+ %LEN-HIGH (int<< 1 %LEN-HIGH-BITS)))

(def %START-POS-MODEL 4)
(def %END-POS-MODEL 14)
(def %FULL-DISTANCES (int<< 1 (int>> %END-POS-MODEL 1)))
(def %POS-SLOT-BITS 6)
(def %LEN-TO-POS-STATES 4)
(def %ALIGN-BITS 4)

(def %IS-MATCH 0)
(def %IS-REP (int+ %IS-MATCH (int<< %NSTATES %POSBITSMAX)))
(def %IS-REP-G0 (int+ %IS-REP %NSTATES))
(def %IS-REP-G1 (int+ %IS-REP-G0 %NSTATES))
(def %IS-REP-G2 (int+ %IS-REP-G1 %NSTATES))
(def %IS-REP-0-LONG (int+ %IS-REP-G2 %NSTATES))
(def %POS-SLOT (int+ %IS-REP-0-LONG (int<< %NSTATES %POSBITSMAX)))
(def %SPEC-POS (int+ %POS-SLOT (int<< %LEN-TO-POS-STATES %POS-SLOT-BITS)))
(def %ALIGN (int+ %SPEC-POS (int- %FULL-DISTANCES %END-POS-MODEL)))
(def %LEN-CODER (int+ %ALIGN (int<< 1 %ALIGN-BITS)))
(def %REP-LEN-CODER (int+ %LEN-CODER %NUM-LEN-PROBS))
(def %LITERAL (int+ %REP-LEN-CODER %NUM-LEN-PROBS))

; What the state becomes after a literal, by state.
(def %next-state
  (let ((v (Vector make %NSTATES 0)))
    (do ((fn (self i l) (unless (null? l) (do (Vector set! i (first l) v) (self (int+ i 1) (rest l)))))
         0 (list 0 0 0 0 1 2 3 4 5 6 4 5))
        v)))

; --- the decoder's state, in the slots of one vector ------------------------
;
; The input's address, its length and how much is read; the range coder's
; code and range; the probabilities, their region and address and how many;
; the window's region, address, size, how much of it is allocated, the
; write position, how far it has ever been written, and how many whole
; windows are behind it; the output's region, address, size and count; the
; header's lc and the masks pb and lp make; the state machine's state, the
; last four distances and the byte before the write position; the output
; size the header declares, or -1 for the "not told" the alone format
; writes when the size is unknown.
(def %IN 1)
(def %INLEN 2)
(def %INCNT 3)
(def %CODE 4)
(def %RANGE 5)
(def %PROBSR 6)
(def %PROBS 7)
(def %NPROBS 8)
(def %DICTR 9)
(def %DICT 10)
(def %DICTSIZE 11)
(def %DICTCAP 12)
(def %DICTPOS 13)
(def %DICTHIGH 14)
(def %GLOBALPOS 15)
(def %OUT 16)
(def %OUTP 17)
(def %OUTCAP 18)
(def %OUTCNT 19)
(def %LC 20)
(def %POSMASK 21)
(def %LITMASK 22)
(def %STATE 23)
(def %REP0 24)
(def %REP1 25)
(def %REP2 26)
(def %REP3 27)
(def %PREV 28)
(def %DSTSIZE 29)
(def %NSLOTS 29)

(def %fail
  (fn (_ kind what)
    (Err raise (lit value) (Str8 append "Unlzma: " what) (list (pair (lit lzma) kind)))))

; --- memory -----------------------------------------------------------------

(def %at (fn (_ p off) (int->ptr (int+ (ptr->int p) off))))
(def %wref (fn (_ p i) (ptr-ref p (int<< i 3) 8)))
(def %wset! (fn (_ p i v) (ptr-set! p (int<< i 3) v 8)))
(def %bref (fn (_ p i) (int& (ptr-ref p i 1) 255)))
(def %bset! (fn (_ p i v) (ptr-set! p i v 1)))

; A region of n bytes, zeroed; never of none, since a (str make) of 0 is no
; buffer.
(def %zeroed
  (fn (_ n)
    (def k (if (int< n 1) 1 n))
    (def r (str-make k))
    (do (%mem-set (str->ptr r) 0 k) r)))

; A region of n words, every one 1024: each probability starts even.
(def %probs
  (fn (_ n)
    (def r (str-make (int<< n 3)))
    (def p (str->ptr r))
    (do ((fn (self i) (if (int< i n) (do (%wset! p i (int>> %MODEL-TOTAL 1)) (self (int+ i 1))) ())) 0)
        r)))

; --- the input --------------------------------------------------------------

(def %byte!
  (fn (_ s)
    (def i (obj-ref s %INCNT))
    (if (int< i (obj-ref s %INLEN))
      (do (obj-set! s %INCNT (int+ i 1)) (%bref (obj-ref s %IN) i))
      (%fail (lit short) "the stream ends inside a symbol"))))

; --- the range coder --------------------------------------------------------
;
; A byte at a time into code, once range has shrunk past 2^24.  Both are 32
; bits wide, so every step masks.

; The coder's code and range are 32-bit patterns, and the word they sit in
; is the platform's: 64 bits holds them as the numbers they are, 32 bits
; holds the same bits as a signed int.  Wrapping, masking and subtraction
; carry the bits either way.  Only two operations differ: a right shift
; sign-extends, and a comparison reads the top bit as a sign.
;
; The shift is x/num/u32's u32-srl, the logical one on either word.  The
; comparison is %ult: on an 8-byte word the patterns are the numbers and it
; is the door itself; on a 4-byte word it compares the halves first -- a
; pattern shifted right by one is never negative -- and the low bits only
; to break a tie.
(def %ult
  (if (int< 4 %word-size) int<
    (fn (_ a b)
      (def ah (u32-srl a 1))
      (def bh (u32-srl b 1))
      (if (int< ah bh) #t
        (if (int< bh ah) #f (int< (int& a 1) (int& b 1)))))))

(def %shift-in!
  (fn (_ s)
    (obj-set! s %RANGE (int& (int<< (obj-ref s %RANGE) 8) %M32))
    (obj-set! s %CODE (int& (int| (int<< (obj-ref s %CODE) 8) (%byte! s)) %M32))))

(def %normalize!
  (fn (_ s) (if (%ult (obj-ref s %RANGE) %TOP) (%shift-in! s) ())))

; Five shifts prime the coder.  The first of those five bytes leaves the low
; 32 bits again and is never read, which is why the sixth byte of a stream
; is the first one that says anything.
(def %rc-init!
  (fn (_ s)
    (obj-set! s %CODE 0)
    (obj-set! s %RANGE 0)
    ((fn (self i) (if (int< i 5) (do (%shift-in! s) (self (int+ i 1))) ())) 0)
    (obj-set! s %RANGE %M32)))

; One bit against the probability at index pi, which the bit then moves.
(def %bit!
  (fn (_ s pi)
    (%normalize! s)
    (def p (obj-ref s %PROBS))
    (def v (%wref p pi))
    (def bound (int* v (u32-srl (obj-ref s %RANGE) %MODEL-BITS)))
    (if (%ult (obj-ref s %CODE) bound)
      (do (obj-set! s %RANGE bound)
          (%wset! p pi (int+ v (int>> (int- %MODEL-TOTAL v) %MOVE-BITS)))
          0)
      (do (obj-set! s %RANGE (int- (obj-ref s %RANGE) bound))
          (obj-set! s %CODE (int- (obj-ref s %CODE) bound))
          (%wset! p pi (int- v (int>> v %MOVE-BITS)))
          1))))

; A bit with no probability behind it: the range halves and the code says
; which half.
(def %direct-bit!
  (fn (_ s)
    (%normalize! s)
    (obj-set! s %RANGE (u32-srl (obj-ref s %RANGE) 1))
    (if (%ult (obj-ref s %CODE) (obj-ref s %RANGE)) 0
      (do (obj-set! s %CODE (int- (obj-ref s %CODE) (obj-ref s %RANGE))) 1))))

; levels bits, each against the context the bits so far name: a walk down a
; binary tree of probabilities from base.
(def %tree!
  (fn (_ s base levels)
    (int- ((fn (self i m) (if (int< i 1) m (self (int- i 1) (int+ (int* m 2) (%bit! s (int+ base m))))))
           levels 1)
          (int<< 1 levels))))

; --- the window -------------------------------------------------------------
;
; Grown by doubling towards the header's dictionary size, so a stream whose
; output is small does not take 64MB to decode.  DICTHIGH is how far the
; window has ever been written: a distance reaching past it before the
; window has wrapped names bytes no stream ever wrote.

(def %dict-double
  (fn (self c n) (if (int< c n) (self (int<< c 1) n) c)))

(def %dict-room!
  (fn (_ s n)
    (def cap (obj-ref s %DICTCAP))
    (if (int< cap n)
      (do (def want (%dict-double (if (int< cap 1) 1 cap) n))
          (def size (obj-ref s %DICTSIZE))
          (def ncap (if (int< size want) size want))
          (def r (%zeroed ncap))
          (def high (obj-ref s %DICTHIGH))
          (if (int< 0 high) (mem-copy (str->ptr r) (obj-ref s %DICT) high) ())
          (obj-set! s %DICTR r)
          (obj-set! s %DICT (str->ptr r))
          (obj-set! s %DICTCAP ncap))
      ())))

(def %out-room!
  (fn (_ s n)
    (def need (int+ (obj-ref s %OUTCNT) n))
    (if (int< (obj-ref s %OUTCAP) need) (%out-grow! s need (int<< (obj-ref s %OUTCAP) 1)) ())))

(def %out-grow!
  (fn (self s need ncap)
    (if (int< ncap need) (self s need (int<< ncap 1))
      (do (def r (str-make ncap))
          (def cnt (obj-ref s %OUTCNT))
          (if (int< 0 cnt) (mem-copy (str->ptr r) (obj-ref s %OUTP) cnt) ())
          (obj-set! s %OUT r)
          (obj-set! s %OUTP (str->ptr r))
          (obj-set! s %OUTCAP ncap)))))

; The window's first n bytes onto the output.
(def %flush!
  (fn (_ s n)
    (if (int< 0 n)
      (do (%out-room! s n)
          (mem-copy (%at (obj-ref s %OUTP) (obj-ref s %OUTCNT)) (obj-ref s %DICT) n)
          (obj-set! s %OUTCNT (int+ (obj-ref s %OUTCNT) n)))
      ())))

; One byte into the window, and the window out when the byte fills it.
(def %put!
  (fn (_ s b)
    (def i (obj-ref s %DICTPOS))
    (%dict-room! s (int+ i 1))
    (%bset! (obj-ref s %DICT) i b)
    (obj-set! s %PREV b)
    (def n (int+ i 1))
    (if (int< (obj-ref s %DICTHIGH) n) (obj-set! s %DICTHIGH n) ())
    (if (int= n (obj-ref s %DICTSIZE))
      (do (%flush! s n)
          (obj-set! s %DICTPOS 0)
          (obj-set! s %GLOBALPOS (int+ (obj-ref s %GLOBALPOS) (obj-ref s %DICTSIZE))))
      (obj-set! s %DICTPOS n))))

; Where a distance of rep0 reads, wrapping to the window's end.
(def %back
  (fn (_ s)
    (def pos (int- (obj-ref s %DICTPOS) (obj-ref s %REP0)))
    (if (int< pos 0)
      (do (def w (int+ pos (obj-ref s %DICTSIZE)))
          (if (int< w 0) (%fail (lit data) "a distance reaches past the window")
            (if (int< (obj-ref s %DICTHIGH) (int+ w 1))
              (%fail (lit data) "a distance names bytes the stream never wrote")
              w)))
      pos)))

; --- literals ---------------------------------------------------------------
;
; A literal's context is the bits of the byte so far, under the low bits of
; the position and the high bits of the byte before it.  Past the literal
; states the byte one distance back is coded against as well, bit by bit,
; until the two differ.

(def %lit-base
  (fn (_ s)
    (int+ %LITERAL
          (int* %LITSIZE
                (int+ (int<< (int& (int+ (obj-ref s %DICTPOS) (obj-ref s %GLOBALPOS)) (obj-ref s %LITMASK))
                             (obj-ref s %LC))
                      (int>> (obj-ref s %PREV) (int- 8 (obj-ref s %LC))))))))

(def %matched-loop!
  (fn (self s base mb m)
    (if (int< m 256)
      (do (def mb2 (int& (int<< mb 1) 511))
          (def bit (int& mb2 256))
          (def got (%bit! s (int+ base (int+ 256 (int+ bit m)))))
          (def m2 (int+ (int* m 2) got))
          (if (int= bit (int<< got 8)) (self s base mb2 m2) m2))
      m)))

(def %plain-loop!
  (fn (self s base m)
    (if (int< m 256) (self s base (int+ (int* m 2) (%bit! s (int+ base m)))) m)))

(def %literal!
  (fn (_ s)
    (def base (%lit-base s))
    (def st (obj-ref s %STATE))
    (def m (if (int< st %NLITSTATES) 1
             (%matched-loop! s base (%bref (obj-ref s %DICT) (%back s)) 1)))
    (def mi (%plain-loop! s base m))
    (obj-set! s %STATE (Vector ref st %next-state))
    (%put! s (int& mi 255))))

; --- lengths ----------------------------------------------------------------
;
; Three tiers: eight lengths under the position's state, eight more, then
; 256.  The tier says which tree to walk and what to add to its symbol.

(def %length!
  (fn (_ s base pos-state)
    (if (int= 0 (%bit! s (int+ base %LEN-CHOICE)))
      (%tree! s (int+ base (int+ %LEN-LOW (int<< pos-state %LEN-LOW-BITS))) %LEN-LOW-BITS)
      (if (int= 0 (%bit! s (int+ base %LEN-CHOICE-2)))
        (int+ (%tree! s (int+ base (int+ %LEN-MID (int<< pos-state %LEN-MID-BITS))) %LEN-MID-BITS)
              (int<< 1 %LEN-LOW-BITS))
        (int+ (%tree! s (int+ base %LEN-HIGH) %LEN-HIGH-BITS)
              (int+ (int<< 1 %LEN-LOW-BITS) (int<< 1 %LEN-MID-BITS)))))))

; --- distances --------------------------------------------------------------
;
; A slot names how many bits the distance has.  Under four, the slot is the
; distance; to fourteen, the low bits come from a tree of their own; past
; that, the middle bits are coded outright and the low four come from the
; align tree.  Answers the distance as the bits say it, one less than the
; distance itself.

(def %dist-low!
  (fn (self s base i m acc bits)
    (if (int< bits 1) acc
      (do (def bit (%bit! s (int+ base m)))
          (self s base (int<< i 1) (int+ (int* m 2) bit)
                (if (int= 1 bit) (int| acc i) acc) (int- bits 1))))))

(def %direct-loop!
  (fn (self s acc bits)
    (if (int< bits 1) acc
      (self s (int& (int| (int<< acc 1) (%direct-bit! s)) %M32) (int- bits 1)))))

(def %distance!
  (fn (_ s len)
    (def slot (%tree! s (int+ %POS-SLOT
                              (int<< (if (int< len %LEN-TO-POS-STATES) len (int- %LEN-TO-POS-STATES 1))
                                     %POS-SLOT-BITS))
                      %POS-SLOT-BITS))
    (if (int< slot %START-POS-MODEL) slot
      (do (def bits (int- (int>> slot 1) 1))
          (def head (int| 2 (int& slot 1)))
          (if (int< slot %END-POS-MODEL)
            (do (def d (int<< head bits))
                (%dist-low! s (int- (int+ %SPEC-POS d) (int+ slot 1)) 1 1 d bits))
            (do (def mid (%direct-loop! s head (int- bits %ALIGN-BITS)))
                (def d (int& (int<< mid %ALIGN-BITS) %M32))
                (%dist-low! s %ALIGN 1 1 d %ALIGN-BITS)))))))

; --- matches ----------------------------------------------------------------

(def %copy-loop!
  (fn (self s len)
    (if (int< len 1) ()
      (do (%put! s (%bref (obj-ref s %DICT) (%back s)))
          (self s (int- len 1))))))

; A fresh distance: the last three shift down, and the state says whether a
; literal or a match came before.  Answers 'end for the end marker, which
; is the distance that cannot be one.
(def %new-match!
  (fn (_ s pos-state)
    (obj-set! s %REP3 (obj-ref s %REP2))
    (obj-set! s %REP2 (obj-ref s %REP1))
    (obj-set! s %REP1 (obj-ref s %REP0))
    (def st (obj-ref s %STATE))
    (obj-set! s %STATE (if (int< st %NLITSTATES) 0 3))
    (def len (%length! s %LEN-CODER pos-state))
    (def d (%distance! s len))
    (obj-set! s %STATE (int+ (obj-ref s %STATE) %NLITSTATES))
    (obj-set! s %REP0 (int& (int+ d 1) %M32))
    (if (int= 0 (obj-ref s %REP0)) (lit end)
      (if (int= 1 (u32-srl (obj-ref s %REP0) 31))
        (%fail (lit data) "a distance is not a number of bytes")
        (int+ len %MATCHMINLEN)))))

; One of the last four distances again.  The first, under a short code, is a
; single byte; otherwise a length follows, and the distance chosen moves to
; the front.
(def %rep-len!
  (fn (_ s pos-state)
    (def st (obj-ref s %STATE))
    (obj-set! s %STATE (if (int< st %NLITSTATES) 8 11))
    (int+ (%length! s %REP-LEN-CODER pos-state) %MATCHMINLEN)))

(def %rep-match!
  (fn (_ s pos-state)
    (def st (obj-ref s %STATE))
    (if (int= 0 (%bit! s (int+ %IS-REP-G0 st)))
      (if (int= 0 (%bit! s (int+ %IS-REP-0-LONG (int+ (int<< st %POSBITSMAX) pos-state))))
        (do (obj-set! s %STATE (if (int< st %NLITSTATES) 9 11))
            (%put! s (%bref (obj-ref s %DICT) (%back s)))
            0)
        (%rep-len! s pos-state))
      (do (def d (if (int= 0 (%bit! s (int+ %IS-REP-G1 st))) (obj-ref s %REP1)
                   (if (int= 0 (%bit! s (int+ %IS-REP-G2 st)))
                     (do (def d2 (obj-ref s %REP2)) (obj-set! s %REP2 (obj-ref s %REP1)) d2)
                     (do (def d3 (obj-ref s %REP3))
                         (obj-set! s %REP3 (obj-ref s %REP2))
                         (obj-set! s %REP2 (obj-ref s %REP1))
                         d3))))
          (obj-set! s %REP1 (obj-ref s %REP0))
          (obj-set! s %REP0 d)
          (%rep-len! s pos-state)))))

; --- the stream -------------------------------------------------------------

(def %done?
  (fn (_ s)
    (def want (obj-ref s %DSTSIZE))
    (if (int< want 0) #f
      (int< want (int+ 1 (int+ (obj-ref s %GLOBALPOS) (obj-ref s %DICTPOS)))))))

(def %step!
  (fn (_ s)
    (def pos-state (int& (int+ (obj-ref s %DICTPOS) (obj-ref s %GLOBALPOS)) (obj-ref s %POSMASK)))
    (if (int= 0 (%bit! s (int+ %IS-MATCH (int+ (int<< (obj-ref s %STATE) %POSBITSMAX) pos-state))))
      (do (%literal! s) #t)
      (do (def len (if (int= 0 (%bit! s (int+ %IS-REP (obj-ref s %STATE))))
                     (%new-match! s pos-state)
                     (%rep-match! s pos-state)))
          (if (eq? len (lit end)) #f
            (do (%copy-loop! s len) #t))))))

(def %run!
  (fn (self s)
    (if (%done? s) ()
      (if (%step! s) (self s) ()))))

; --- the header -------------------------------------------------------------

(def %le
  (fn (self p i n acc sh)
    (if (int< n 1) acc
      (self p (int+ i 1) (int- n 1) (int| acc (int<< (%bref p i) sh)) (int+ sh 8)))))

; Every bit set is the alone format's "I was not told": decode to the end
; marker.  Anything else is the length of the output.
(def %dst-size
  (fn (_ p start)
    (if ((fn (self i) (if (int< i 8) (if (int= 255 (%bref p (int+ start i))) (self (int+ i 1)) #f) #t)) 0)
      -1
      (%le p start 8 0 0))))

(def %header!
  (fn (_ s)
    (if (int< (obj-ref s %INLEN) 13) (%fail (lit short) "the stream is shorter than a header") ())
    (def p (obj-ref s %IN))
    (def pos (%bref p 0))
    (if (int< pos 225) () (%fail (lit data) "the header's properties byte is out of range"))
    (def lc (int% pos 9))
    (def i (int/ pos 9))
    (def pb (int/ i 5))
    (def lp (int% i 5))
    (def dict (%le p 1 4 0 0))
    (obj-set! s %LC lc)
    (obj-set! s %POSMASK (int- (int<< 1 pb) 1))
    (obj-set! s %LITMASK (int- (int<< 1 lp) 1))
    (obj-set! s %DICTSIZE (if (int< dict 1) 1 dict))
    (obj-set! s %DSTSIZE (%dst-size p 5))
    (def want (obj-ref s %DSTSIZE))
    (if (int< 0 want) (if (int< want (obj-ref s %DICTSIZE)) (obj-set! s %DICTSIZE want) ()) ())
    (obj-set! s %NPROBS (int+ %LITERAL (int<< %LITSIZE (int+ lc lp))))
    (obj-set! s %INCNT 13)))

(def %decoder
  (fn (_ s start n)
    (def d (Vector make %NSLOTS 0))
    (def o (str-make 256))
    (obj-set! d %IN (%at (str->ptr s) start))
    (obj-set! d %INLEN n)
    (obj-set! d %REP0 1)
    (obj-set! d %REP1 1)
    (obj-set! d %REP2 1)
    (obj-set! d %REP3 1)
    (obj-set! d %OUT o)
    (obj-set! d %OUTP (str->ptr o))
    (obj-set! d %OUTCAP 256)
    (obj-set! d %DICTR ())
    (obj-set! d %DICT ())
    d))

; The decisions, from the first to the end, by this file's loops: the
; probabilities and the window made, the stream run, the window's last bytes
; out.  Answers (OUT N USED).
(def %pure-run
  (fn (_ d)
    (def pr (%probs (obj-ref d %NPROBS)))
    (obj-set! d %PROBSR pr)
    (obj-set! d %PROBS (str->ptr pr))
    (%dict-room! d 1)
    (%run! d)
    (%flush! d (obj-ref d %DICTPOS))
    (list (obj-ref d %OUT) (obj-ref d %OUTCNT) (obj-ref d %INCNT))))

; One stream: the header and the coder's first bytes here, the decisions by
; run, this file's %pure-run or the compiled engine's.
(def %decode-all
  (fn (_ s start n run)
    (def d (%decoder s start n))
    (%header! d)
    (%rc-init! d)
    (run d)))

; --- The compiled engine (JIT), adopted only when it proves out --------------
;
; x/codec/unlzma-jit compiles the decisions: everything %pure-run does after
; the header and the coder's first bytes.  As Bunzip2's engine is, it is an
; entry of Compiled's made on demand, built for an input of %jit-threshold
; bytes or more or on (Unlzma jit!), and adopted only after it decodes the
; streams below exactly as %pure-run does.  The entry's value is the run:
; %pure-run, or the engine's.

; Streams written by xz 5.8.4.  The first is --lzma1=preset=9,dict=4KiB over
; 4652 bytes built to reach every decision the format has -- literals plain
; and matched, distances from each tier, all four repeated ones, lengths from
; each tier -- and the window wraps once.  The second declares its length.
(def %check-streams
  (list (Str8 append
          "5d00100000ffffffffffffffff00399948caebd3b5bc6180c1fad3fafc7972156fc13767639185bd015f88c195a2f4c4"
          "7140f803827086e65f855789c9412488723be50124b0ca6fb9b4d26be6cdfd8319d24179ba9c46c23fbb1e3cb7172b51"
          "8485a73ed2a40c39bb9abf714d3ae98273d60480cde321bbaa33a281b2379fd2a3e92a26eb2d1d0f68560014e515d3a0"
          "9f4cb995d7f1b1c79304d8067ea4e23b34dee7c1db0d2715e75138ced1310e2cc81ae77f8bb2d98226c9bcbdccc9f48f"
          "427e61e55508e4149932d8ca6ba54da2fba83a8649459ba1ecad3de60f0762e6d24904e3f240870cbf4761dac9db2fed"
          "a05fad8a5637565e7a10cd122aea43f424b4f83e463740d612fd6796e553ccb064eed37577ea3f7e379ccf579ad6e378"
          "46f4f8643e37866b6a0936d79e83a5ddd0d95bc6e207e5d5225c7eb54fee2a6ae542d0d6b6b75ccfc6d54a6c3a2b5a43"
          "b5ff1b9ae63615b7deca95a4882c8ccda80d72ec5d7db6559d9b58ead38452f80e094c101344c571a7bc4c5345c093f0"
          "d1340bbb36349f25567f2f523b268db64a9f585e95e0f87a60dd93b90dbf5503bffc157839b2742fb81378cb45e8ac6f"
          "f9c4da32d7b5ffb5a44d789b4d23a2cf78f59b790c641acc802d180fdcf7e2b2e00fbefddba98d4bc41736440615ac12"
          "a2157c4e1c58b7813c1934997ca3917ed538e97ee321609c5299597bd8cf267bed6c26c62d06d02d6fd5c01eb752aea1"
          "8c5e60d355c5a0d550499bb5a7336b9ec7117075399ada8c8382c2e5d3eab26bab66fd2538d915bccd2e51192b69643b"
          "bf5ffb4197245d5ed08b795bf7b89e9e4560f236feecf2fb2a99cb5c50a6160245c199aaa8ed0d7801c5e8433bc6fe14"
          "97e354a41008c573999c0df3d86cb2cc7aa60651eb42a6c025c4a53d5cc74fb7cfe05ec220fdf5ad4d709e40949f60b3"
          "0e976b193bf459f5e213b20b7f326919aa40359a19c30131dd924cd739b155a4f7e4f913dedeefd0a7459a820bc00075"
          "6f21b790600211554ee75de7cf66b92bcef0b812c2805e45fded04861771c1f004665e1487a48e38e255fd44542fa3de"
          "2042f108674ca552407ef7020574d870f649a27c89546d0aa161564ac799cbabd677e6a04e5e723ccc84849520ec0a9d"
          "b2fb9b0edb63cba450b7470691a1d2d93e13a69a8c8c6724d35c312ccb4582d3ec05d6e7e3b45994d1eb1d111c5e209a"
          "4b8569b945729c3f99eecfb8ad58009f95de46a54414407cb22cb744e8d5423cbe2120af994d8d3fac712e4a38107398"
          "d668d295681cb720330ee3f781fd4b56eb42411791fffd9eae8c")        "5d000000040d0000000000000000341949ee8def8c80b1e6f35b7bffffb5c80000"))

(def %region
  (fn (_ bytes)
    (let ((r (str-make (List length bytes))))
      (do ((fn (self i l) (unless (null? l) (do (ptr-set! (str->ptr r) i (first l) 1) (self (int+ i 1) (rest l)))))
           0 bytes)
          r))))

; Does a run decode every check stream as %pure-run does, byte for byte,
; using as much input?
(def %agrees?
  (fn (_ run)
    (import x/codec/hex)
    (List all?
      (fn (_ hex)
        (let ((bytes (Hex decode-bytes hex)))
          (let ((in (%region bytes)) (n (List length bytes)))
            (let ((want (%decode-all in 0 n %pure-run)) (got (%decode-all in 0 n run)))
              (and (= (first (rest want)) (first (rest got)))
                   (= (first (rest (rest want))) (first (rest (rest got))))
                   (= 0 (mem-cmp (str->ptr (first want)) (str->ptr (first got)) (first (rest want)))))))))
      %check-streams)))

(def %entry ())
(def %jit-threshold 4096)

(def %jit-try!
  (fn (_)
    (when (null? %entry)
      (set! %entry
        (Compiled make-on-demand (lit unlzma) %pure-run
          (fn (_)
            (import x/codec/unlzma-jit)
            ((prim-ref (lit unlzma) (lit jit-make))
             (list (pair (lit in) %IN) (pair (lit inlen) %INLEN) (pair (lit incnt) %INCNT)
                   (pair (lit code) %CODE) (pair (lit range) %RANGE) (pair (lit nprobs) %NPROBS)
                   (pair (lit dictsize) %DICTSIZE) (pair (lit lc) %LC) (pair (lit posmask) %POSMASK)
                   (pair (lit litmask) %LITMASK) (pair (lit state) %STATE) (pair (lit rep0) %REP0)
                   (pair (lit rep1) %REP1) (pair (lit rep2) %REP2) (pair (lit rep3) %REP3)
                   (pair (lit prev) %PREV) (pair (lit dstsize) %DSTSIZE))
             (list (pair (lit is-match) %IS-MATCH) (pair (lit is-rep) %IS-REP) (pair (lit is-rep-g0) %IS-REP-G0)
                   (pair (lit is-rep-g1) %IS-REP-G1) (pair (lit is-rep-g2) %IS-REP-G2)
                   (pair (lit is-rep-0-long) %IS-REP-0-LONG) (pair (lit pos-slot) %POS-SLOT)
                   (pair (lit spec-pos) %SPEC-POS) (pair (lit align) %ALIGN) (pair (lit len-coder) %LEN-CODER)
                   (pair (lit rep-len-coder) %REP-LEN-CODER) (pair (lit literal) %LITERAL)
                   (pair (lit len-choice) %LEN-CHOICE) (pair (lit len-choice-2) %LEN-CHOICE-2)
                   (pair (lit len-low) %LEN-LOW) (pair (lit len-mid) %LEN-MID) (pair (lit len-high) %LEN-HIGH))
             %next-state %agrees?))
          (fn (_ _) ()))))
    ((fn (_ entry)
       (when (eq? (entry state) (lit interpreted)) (entry compile!))
       (eq? (entry state) (lit compiled)))
     %entry)))

; The run for n bytes of input: the engine's when it is built, or when n is
; past the bar and a build succeeds; else %pure-run.
(def %engine-for
  (fn (_ n)
    (do (when (and (>= n %jit-threshold)
                   ((fn (_ entry) (if (null? entry) #t (eq? (entry state) (lit interpreted)))) %entry))
          (%jit-try!))
        ((fn (_ entry)
           (if (if (null? entry) #f (eq? (entry state) (lit compiled)))
             (entry compiled)
             %pure-run))
         %entry))))

(def %span
  (fn (_ s span)
    (match
      ((null? span) (list 0 (str-byte-len s)))
      ((null? (rest span)) (list (first span) (int- (str-byte-len s) (first span))))
      (#t (list (first span) (first (rest span)))))))

(def-class Unlzma ()
  (doc "lzma decompression in pure x-lang, the .lzma \"alone\" format busybox's unlzma and lzcat read. (Unlzma decode s start n) answers (OUT N USED)."
    (example "(do (import x/codec/bytes) (def z (Bytes of-hex \"5d00000004ffffffffffffffff00341949ee8def8c80b1e6f35b7bffffb5c80000\")) (first (rest (Unlzma decode (first z) 0 (Bytes length z)))))" "13"))
  (static
    (method decode (self (param s STRING "Bytes holding a .lzma stream")
                         . (param span LIST "START, then LENGTH: where the stream starts in s and how many bytes of s it may use; default all of s"))
      (doc "Decompress one .lzma stream: the 13-byte header, then the range coder's bytes, to the end marker or to the length the header declares. Give LENGTH for binary input: s's own length is measured to its first NUL, and a header holds three."
        (returns LIST "(OUT N USED): the output region, its byte count, and the input bytes the stream used")
        (example "(do (import x/codec/bytes) (def z (Bytes of-hex \"5d00000004ffffffffffffffff0083fffbffffc0000000\")) (first (rest (Unlzma decode (first z) 0 (Bytes length z)))))" "0"))
      (def sp (%span s span))
      (%decode-all s (first sp) (first (rest sp)) (%engine-for (first (rest sp)))))
    (method jit! (self)
      (doc "Build and adopt the compiled decoder (JIT; ARM64, x86-64 and 32-bit ARM backends) now, if it decodes the check streams exactly as the pure-x one does. Idempotent. Answers #t when the engine is active, #f when unavailable -- the pure-x decoder carries on, with the same output. decode builds it on its own for an input of 4KB or more."
        (returns BOOL "#t when the compiled engine is active"))
      (%jit-try!))))

(doc (provide x/codec/unlzma Unlzma)
  (example "(do (import x/codec/bytes) (def z (Bytes of-hex \"5d00000004ffffffffffffffff00341949ee8def8c80b1e6f35b7bffffb5c80000\")) (first (rest (rest (Unlzma decode (first z) 0 (Bytes length z))))))" "33")
  "lzma decompression in pure x-lang, the .lzma \"alone\" format: (Unlzma decode s start n) answers (OUT N USED).")

; deflate.x -- Deflate: DEFLATE streams written in pure x-lang.
;
; The writing half of x/codec/inflate: a stream any DEFLATE reader takes,
; written where no C library is present (x-os).  Two writers: stored blocks
; (RFC 1951 3.2.4) carry the bytes as they are, five bytes of framing a
; block; the compressor finds repeats with LZ77 over a 32K window and codes
; what it finds with Huffman codes, a block's own (3.2.7) or the fixed ones
; (3.2.6), whichever is shorter -- or stores the block when neither is.  The
; shape is zlib's deflate at its default level, without the lazy match: a
; hash of three bytes heads a chain of earlier positions, the chain is
; walked a bounded number of steps, and the longest match wins.
;
; Input is a byte region and a count, so a NUL is a byte like any other;
; the output is a region and its count, as Inflate answers.  A raw stream
; can also be written a piece at a time: see the stream below.
;
; The paths run once a byte, a match or a symbol are written in primitives
; alone -- def in a body, if, do, self-calls of top-level functions, the
; int doors -- for the reason inflate.x gives: a let, a when or a generic
; comparison costs a frame, a pair or a tower dispatch each time through.
(module x/codec/deflate)

(import x/type/vector)
(import x/type/list)
; The compiled engine is on Compiled's list.
(import x/tool/compiled)
; The length and distance code tables, shared with the decoder.
(import x/codec/flate-codes lbase lext dbase dext)

(import x/core/doors int% int& int* int+ int- int->ptr int/ int< int<< int= int>> int| mem-cmp mem-copy obj-ref obj-set! ptr->int ptr-ref ptr-set! str->ptr str-byte-len str-make)
(def %mem-set (prim-ref (lit mem) (lit set)))

(def %at (fn (_ p off) (int->ptr (int+ (ptr->int p) off))))

; --- The output: bytes, and bits into them ---
;
; A writer's state in the slots of one vector: the output region, its
; address, its size and how much is written; the bits not yet a whole byte
; and how many.

(def %OUT 1)
(def %OUTP 2)
(def %OUTCAP 3)
(def %OUTCNT 4)
(def %BITBUF 5)
(def %BITCNT 6)

(def %writer
  (fn (_ cap)
    (def w (Vector make 6 0))
    (def out (str-make cap))
    (obj-set! w %OUT out)
    (obj-set! w %OUTP (str->ptr out))
    (obj-set! w %OUTCAP cap)
    w))

; The output region doubled from ncap until `need` bytes fit.
(def %grow!
  (fn (self w need ncap)
    (if (int< ncap need) (self w need (int<< ncap 1))
      (do (def r (str-make ncap))
          (def cnt (obj-ref w %OUTCNT))
          (if (int< 0 cnt) (mem-copy (str->ptr r) (obj-ref w %OUTP) cnt) ())
          (obj-set! w %OUT r)
          (obj-set! w %OUTP (str->ptr r))
          (obj-set! w %OUTCAP ncap)))))

(def %room!
  (fn (_ w n)
    (def need (int+ (obj-ref w %OUTCNT) n))
    (def cap (obj-ref w %OUTCAP))
    (if (int< cap need) (%grow! w need (int<< cap 1)) ())))

(def %emit!
  (fn (_ w b)
    (%room! w 1)
    (def at (obj-ref w %OUTCNT))
    (ptr-set! (obj-ref w %OUTP) at b 1)
    (obj-set! w %OUTCNT (int+ at 1))))

; Whole bytes of the bit buffer out, low byte first (3.1.1).
(def %emit-whole!
  (fn (self w)
    (def cnt (obj-ref w %BITCNT))
    (if (int< cnt 8) ()
      (do (%emit! w (int& (obj-ref w %BITBUF) 255))
          (obj-set! w %BITBUF (int>> (obj-ref w %BITBUF) 8))
          (obj-set! w %BITCNT (int- cnt 8))
          (self w)))))

; The low n bits of value, least significant first.
(def %put-bits!
  (fn (_ w value n)
    (obj-set! w %BITBUF (int| (obj-ref w %BITBUF) (int<< value (obj-ref w %BITCNT))))
    (obj-set! w %BITCNT (int+ (obj-ref w %BITCNT) n))
    (%emit-whole! w)))

; The bits in hand padded to a byte boundary.
(def %align!
  (fn (_ w)
    (if (int< 0 (obj-ref w %BITCNT))
      (do (%emit! w (int& (obj-ref w %BITBUF) 255))
          (obj-set! w %BITBUF 0)
          (obj-set! w %BITCNT 0))
      ())))

; --- Stored blocks ---

; The stored blocks of n bytes at src: each a header byte (BFINAL in bit 0,
; type 00), LEN and its complement little-endian, then the bytes.  An empty
; input is one empty final block.
(def %stored!
  (fn (self w src i n final?)
    (def len (if (int< 65535 (int- n i)) 65535 (int- n i)))
    (def last? (int= (int+ i len) n))
    (%put-bits! w (if (if last? final? #f) 1 0) 1)
    (%put-bits! w 0 2)
    (%align! w)
    (%emit! w (int& len 255))
    (%emit! w (int>> len 8))
    (%emit! w (int& (~ len) 255))
    (%emit! w (int& (int>> (~ len) 8) 255))
    (%room! w len)
    (if (int< 0 len) (mem-copy (%at (obj-ref w %OUTP) (obj-ref w %OUTCNT)) (%at src i) len) ())
    (obj-set! w %OUTCNT (int+ (obj-ref w %OUTCNT) len))
    (if last? () (self w src (int+ i len) n final?))))

; --- The tables (3.2.5) ---


; Slot len+1 of %length-code holds the length code (0..28) of a match of
; len bytes, 3..258.
(def %length-code (Vector make 259 0))
((fn (self code)
   (if (int< code 29)
     (do ((fn (fill k n) (if (int< k n) (do (obj-set! %length-code (int+ (int+ (obj-ref lbase (int+ code 1)) k) 1) code) (fill (int+ k 1) n)) ()))
          0 (if (int= code 28) 1 (int<< 1 (obj-ref lext (int+ code 1)))))
         (self (int+ code 1)))
     ()))
 0)

; The distance code of d: slot d of %distance-code for d up to 256, slot
; 256 + (d-1 >> 7) + 1 past it -- zlib's two-part table.
(def %distance-code (Vector make 512 0))
((fn (self code)
   (if (int< code 30)
     (do (def base (obj-ref dbase (int+ code 1)))
         (def span (int<< 1 (obj-ref dext (int+ code 1))))
         (if (int< code 16)
           ((fn (fill d) (if (int< d (int+ base span)) (do (obj-set! %distance-code d code) (fill (int+ d 1))) ()))
            base)
           ((fn (fill d) (if (int< d (int+ base span)) (do (obj-set! %distance-code (int+ 257 (int>> (int- d 1) 7)) code) (fill (int+ d 128))) ()))
            base))
         (self (int+ code 1)))
     ()))
 0)

(def %dcode
  (fn (_ d) (if (int< d 257) (obj-ref %distance-code d) (obj-ref %distance-code (int+ 257 (int>> (int- d 1) 7))))))

; The 9-bit reversal, once: slot i+1 holds the bits of i the other way.
(def %rev9 (Vector make 512 0))
((fn (self i)
   (if (int< i 512)
     (do (obj-set! %rev9 (int+ i 1) (int| (int>> (obj-ref %rev9 (int+ (int>> i 1) 1)) 1) (int<< (int& i 1) 8)))
         (self (int+ i 1)))
     ()))
 1)

; The low len bits of code (len up to 15) reversed: a Huffman code is
; written most significant bit first into a stream read least first.
(def %reverse
  (fn (_ code len)
    (if (int< len 10) (int>> (obj-ref %rev9 (int+ code 1)) (int- 9 len))
      (int| (int<< (obj-ref %rev9 (int+ (int& code 511) 1)) (int- len 9))
           (int>> (obj-ref %rev9 (int+ (int>> code 9) 1)) (int- 18 len))))))

; --- LZ77 (zlib's deflate_fast, greedy) ---

(def %WBITS 15)
(def %WSIZE 32768)
(def %WMASK 32767)
(def %HSIZE 32768)
(def %HMASK 32767)
(def %MINMATCH 3)
(def %MAXMATCH 258)
(def %MAXCHAIN 32)
(def %NICE 128)
(def %MAXINSERT 16)

; A hash of the three bytes at i.
(def %hash
  (fn (_ p i)
    (int& (int+ (int* (int& (ptr-ref p i 1) 255) 1089)
                (int+ (int* (int& (ptr-ref p (int+ i 1) 1) 255) 33)
                      (int& (ptr-ref p (int+ i 2) 1) 255)))
          %HMASK)))

; The tables are byte regions, not vectors: a Vector of 32768 slots costs
; 12.7M objects to make (its fill is a loop), a region one allocation and
; a memset.  The hash and chain tables hold 4-byte slots, a position kept
; plus one so a zeroed slot reads as none; the token tables hold 8-byte
; words, which the compiled writer reads as words.
(def %tref (fn (_ t i) (ptr-ref t (int<< i 3) 8)))
(def %tset! (fn (_ t i v) (ptr-set! t (int<< i 3) v 8)))

(def %table
  (fn (_ slots)
    (def r (str-make (int<< slots 2)))
    (%mem-set (str->ptr r) 0 (int<< slots 2))
    (pair r (str->ptr r))))

; Position i entered: its chain link is what the hash headed before.
(def %insert!
  (fn (_ p i head prev)
    (def h (int<< (%hash p i) 2))
    (ptr-set! prev (int<< (int& i %WMASK) 2) (ptr-ref head h 4) 4)
    (ptr-set! head h (int+ i 1) 4)))

; How many bytes from a and b agree, up to limit: eight at a time while
; eight are left, then one.
(def %agree
  (fn (self p a b k limit)
    (if (int< (int- limit k) 8)
      (%agree-bytes p a b k limit)
      (if (int= (ptr-ref p (int+ a k) 8) (ptr-ref p (int+ b k) 8))
        (self p a b (int+ k 8) limit)
        (%agree-bytes p a b k limit)))))

(def %agree-bytes
  (fn (self p a b k limit)
    (if (int< k limit)
      (if (int= (ptr-ref p (int+ a k) 1) (ptr-ref p (int+ b k) 1))
        (self p a b (int+ k 1) limit)
        k)
      k)))

; The longest match for position i among the chain from cand, as
; (LENGTH . DISTANCE); best so far is (blen . bdist), limit the most a
; match here can be.  A candidate is tried only when its byte at blen
; agrees, where a longer match must; the walk stops at the chain's end,
; the window's edge, the step budget, a match past %NICE, or one as long
; as the input allows.
(def %longest
  (fn (self p i limit cand prev steps blen bdist)
    (if (if (int< cand 0) #t
          (if (int< %WSIZE (int- i cand)) #t
            (if (int= steps 0) #t
              (if (int< %NICE blen) #t (int< (int- limit 1) blen)))))
      (pair blen bdist)
      (do (def len (if (int= (ptr-ref p (int+ cand blen) 1) (ptr-ref p (int+ i blen) 1))
                     (%agree p cand i 0 limit)
                     0))
          (def next (int- (ptr-ref prev (int<< (int& cand %WMASK) 2) 4) 1))
          (if (int< blen len)
            (self p i limit next prev (int- steps 1) len (int- i cand))
            (self p i limit next prev (int- steps 1) blen bdist))))))

; The tokens of n bytes at p: slot t+1 of lens holds a match's length, 0
; for a literal; of vals its distance, or the literal byte.  Answers the
; token count.  The positions inside a match of up to %MAXINSERT bytes are
; entered in the hash so later matches can start there; a longer match is
; skipped over, as zlib's deflate_fast does, since what it covers is
; already a repeat.
(def %tokenize!
  (fn (self p i n head prev lens vals t)
    (if (int< i n)
      (do (def m (if (int< (int- n i) %MINMATCH) (pair 0 0)
                   (do (def h (int<< (%hash p i) 2))
                       (def cand (int- (ptr-ref head h 4) 1))
                       (ptr-set! prev (int<< (int& i %WMASK) 2) (int+ cand 1) 4)
                       (ptr-set! head h (int+ i 1) 4)
                       (%longest p i (if (int< (int- n i) %MAXMATCH) (int- n i) %MAXMATCH)
                         cand prev %MAXCHAIN (int- %MINMATCH 1) 0))))
          (if (int< (first m) %MINMATCH)
            (do (%tset! lens t 0)
                (%tset! vals t (int& (ptr-ref p i 1) 255))
                (self p (int+ i 1) n head prev lens vals (int+ t 1)))
            (do (%tset! lens t (first m))
                (%tset! vals t (rest m))
                (if (int< %MAXINSERT (first m)) () (%insert-run! p (int+ i 1) (int+ i (first m)) n head prev))
                (self p (int+ i (first m)) n head prev lens vals (int+ t 1)))))
      t)))

; Positions from i below end entered, while three bytes remain at each.
(def %insert-run!
  (fn (self p i end n head prev)
    (if (int< i end)
      (do (if (int< (int- n i) %MINMATCH) () (%insert! p i head prev))
          (self p (int+ i 1) end n head prev))
      ())))

; --- Huffman codes from frequencies (3.2.2) ---

; A tree from the symbols with a frequency, (FREQ SYM) leaves merged two
; smallest at a time: the leaves sorted ascending in one queue, the merges
; in another in the order made, which is ascending too.  The merge queue
; is a front list and a back list newest first, the back turned over when
; the front runs out.  A take answers (LEAST LEAVES FRONT BACK).
(def %take-least
  (fn (self leaves front back)
    (match
      ((if (null? front) (not (null? back)) #f) (self leaves (List reverse back) ()))
      ((null? leaves) (list (first front) leaves (rest front) back))
      ((null? front) (list (first leaves) (rest leaves) front back))
      ((int< (first (first front)) (first (first leaves))) (list (first front) leaves (rest front) back))
      (#t (list (first leaves) (rest leaves) front back)))))

(def %merge-tree
  (fn (self leaves front back)
    (if (if (null? front) (not (null? back)) #f) (self leaves (List reverse back) ())
     (if (if (null? leaves) (if (null? back) (null? (rest front)) #f) #f) (first front)
      (do (def a (%take-least leaves front back))
          (def b (%take-least (first (rest a)) (first (rest (rest a))) (first (rest (rest (rest a))))))
          (def node (list (int+ (first (first a)) (first (first b))) (first a) (first b)))
          (self (first (rest b)) (first (rest (rest b))) (pair node (first (rest (rest (rest b)))))))))))

; Each leaf's depth into lengths (slot sym+1), from a node at depth d.
(def %depths!
  (fn (self node d lengths)
    (if (null? (rest (rest node)))
      (obj-set! lengths (int+ (first (rest node)) 1) d)
      (do (self (first (rest node)) (int+ d 1) lengths)
          (self (first (rest (rest node))) (int+ d 1) lengths)))))

(def %max-length
  (fn (self lengths i n best)
    (if (int< i n)
      (self lengths (int+ i 1) n (if (int< best (obj-ref lengths (int+ i 1))) (obj-ref lengths (int+ i 1)) best))
      best)))

; The code lengths for n symbols whose frequencies are in freqs (slot
; sym+1), none longer than limit: the Huffman tree's depths, and when one
; is too deep, the frequencies halved (never to zero) and the tree made
; again -- flatter each time, and never past the limit once they are all
; alike.  Fewer than two symbols are made two, as zlib does: a code must
; have a bit to send, and a reader takes an incomplete code only as the
; one code of one symbol.
;
; freqs is read, never written: the block's costs are reckoned from it
; after.  A halving is made on a copy.
(def %code-lengths
  (fn (self freqs n limit)
    (def used (%symbols-used freqs 0 n 0))
    (def pads
      (match
        ((int= used 0) (list (list 1 0) (list 1 1)))
        ((int= used 1) (list (list 1 (if (int= (obj-ref freqs 1) 0) 0 1))))
        (#t ())))
    (def leaves
      (List sort (fn (_ a b) (int< (first a) (first b)))
        ((fn (collect i acc)
           (if (int< i n)
             (collect (int+ i 1) (if (int< 0 (obj-ref freqs (int+ i 1))) (pair (list (obj-ref freqs (int+ i 1)) i) acc) acc))
             acc))
         0 pads)))
    (def lengths (Vector make n 0))
    (%depths! (%merge-tree leaves () ()) 0 lengths)
    (if (int< limit (%max-length lengths 0 n 0))
      (do (def halved (Vector make n 0))
          ((fn (halve i)
             (if (int< i n)
               (do (def f (obj-ref freqs (int+ i 1)))
                   (obj-set! halved (int+ i 1) (if (int< 1 f) (int>> f 1) f))
                   (halve (int+ i 1)))
               ()))
           0)
          (self halved n limit))
      lengths)))

; How many of n symbols have a frequency.
(def %symbols-used
  (fn (self freqs i n k)
    (if (int< i n) (self freqs (int+ i 1) n (if (int< 0 (obj-ref freqs (int+ i 1))) (int+ k 1) k)) k)))

; The canonical codes for lengths (slot sym+1), reversed for writing, into
; codes: each length's first code is the one past the length before's
; last, doubled (3.2.2).
(def %canonical!
  (fn (_ lengths n codes)
    (def counts (Vector make 16 0))
    ((fn (count i) (if (int< i n) (do (def l (obj-ref lengths (int+ i 1))) (if (int= l 0) () (obj-set! counts (int+ l 1) (int+ (obj-ref counts (int+ l 1)) 1))) (count (int+ i 1))) ()))
     0)
    (def next (Vector make 16 0))
    ((fn (first-codes len code)
       (if (int< len 16)
         (do (obj-set! next (int+ len 1) code)
             (first-codes (int+ len 1) (int<< (int+ code (obj-ref counts (int+ len 1))) 1)))
         ()))
     1 0)
    ((fn (assign i)
       (if (int< i n)
         (do (def l (obj-ref lengths (int+ i 1)))
             (if (int= l 0) ()
               (do (obj-set! codes (int+ i 1) (%reverse (obj-ref next (int+ l 1)) l))
                   (obj-set! next (int+ l 1) (int+ (obj-ref next (int+ l 1)) 1))))
             (assign (int+ i 1)))
         ()))
     0)))

; The fixed codes (3.2.6): literal/length lengths 8 to 143, 9 to 255, 7 to
; 279, 8 to 287; every distance 5.
(def %fixed-lit-lengths (Vector make 288 0))
((fn (self i) (if (int< i 288) (do (obj-set! %fixed-lit-lengths (int+ i 1) (if (int< i 144) 8 (if (int< i 256) 9 (if (int< i 280) 7 8)))) (self (int+ i 1))) ())) 0)
(def %fixed-lit-codes (Vector make 288 0))
(%canonical! %fixed-lit-lengths 288 %fixed-lit-codes)
(def %fixed-dist-lengths (Vector make 30 5))
(def %fixed-dist-codes (Vector make 30 0))
(%canonical! %fixed-dist-lengths 30 %fixed-dist-codes)

; --- A block ---

; The frequencies of a block's tokens t0 below t1: literal/length symbols
; into lfreq, distance codes into dfreq.  Answers the bytes they cover,
; counted on from b.  The one pass a block makes over its tokens in x: what
; the block costs is reckoned from the frequencies.
(def %count!
  (fn (self lens vals t t1 lfreq dfreq b)
    (if (int< t t1)
      (do (def len (%tref lens t))
          (if (int= len 0)
            (do (def s (int+ (%tref vals t) 1)) (obj-set! lfreq s (int+ (obj-ref lfreq s) 1)))
            (do (def s (int+ (int+ 257 (obj-ref %length-code (int+ len 1))) 1))
                (obj-set! lfreq s (int+ (obj-ref lfreq s) 1))
                (def d (int+ (%dcode (%tref vals t)) 1))
                (obj-set! dfreq d (int+ (obj-ref dfreq d) 1))))
          (self lens vals (int+ t 1) t1 lfreq dfreq (int+ b (if (int= len 0) 1 len))))
      b)))

; The bits n symbols take: each one's count times its code's length.
(def %freq-cost
  (fn (self freqs lengths i n bits)
    (if (int< i n)
      (self freqs lengths (int+ i 1) n (int+ bits (int* (obj-ref freqs (int+ i 1)) (obj-ref lengths (int+ i 1)))))
      bits)))

; The extra bits of the block's lengths and distances, whatever the codes.
(def %extra-bits
  (fn (self freqs ext base i n bits)
    (if (int< i n)
      (self freqs ext base (int+ i 1) n (int+ bits (int* (obj-ref freqs (int+ (int+ base i) 1)) (obj-ref ext (int+ i 1)))))
      bits)))

; A code's symbol written: its reversed code, its length bits.
(def %put-code!
  (fn (_ w codes lengths sym)
    (%put-bits! w (obj-ref codes (int+ sym 1)) (obj-ref lengths (int+ sym 1)))))

; The tokens t0 below t1 written under the codes, then the end code.
(def %put-tokens!
  (fn (self w lens vals t t1 lcodes llen dcodes dlen)
    (if (int< t t1)
      (do (def len (%tref lens t))
          (if (int= len 0)
            (%put-code! w lcodes llen (%tref vals t))
            (do (def lc (obj-ref %length-code (int+ len 1)))
                (%put-code! w lcodes llen (int+ 257 lc))
                (if (int= (obj-ref lext (int+ lc 1)) 0) ()
                  (%put-bits! w (int- len (obj-ref lbase (int+ lc 1))) (obj-ref lext (int+ lc 1))))
                (def d (%tref vals t))
                (def dc (%dcode d))
                (%put-code! w dcodes dlen dc)
                (if (int= (obj-ref dext (int+ dc 1)) 0) ()
                  (%put-bits! w (int- d (obj-ref dbase (int+ dc 1))) (obj-ref dext (int+ dc 1))))))
          (self w lens vals (int+ t 1) t1 lcodes llen dcodes dlen))
      (%put-code! w lcodes llen 256))))

; --- The dynamic header (3.2.7) ---

; The order the code-length code's lengths are sent in.
(def %order (Vector from-list (list 16 17 18 0 8 7 9 6 10 5 11 4 12 3 13 2 14 1 15)))

; The last slot of lengths (n of them) that is not zero, plus one; at least
; floor.
(def %used
  (fn (self lengths i floor)
    (if (int< i floor) floor
      (if (int= (obj-ref lengths (int+ i 1)) 0) (self lengths (int- i 1) floor) (int+ i 1)))))

; The lit/len lengths then the dist lengths as one sequence, run-length
; coded as the code-length alphabet has it: a length as itself; 16, the
; last one again 3..6 times; 17, zero 3..10 times; 18, zero 11..138 times.
; Each item into items as (SYM . EXTRA), their count answered; freqs of
; the 19 symbols tallied.
(def %length-at
  (fn (_ llen hlit dlen i) (if (int< i hlit) (obj-ref llen (int+ i 1)) (obj-ref dlen (int+ (int- i hlit) 1)))))

(def %run-length
  (fn (self llen hlit dlen total i items k freqs)
    (if (int< i total)
      (do (def cur (%length-at llen hlit dlen i))
          (def run ((fn (count j) (if (if (int< j total) (int= (%length-at llen hlit dlen j) cur) #f) (count (int+ j 1)) (int- j i))) (int+ i 1)))
          (if (int= cur 0)
            (if (int< run 3)
              (self llen hlit dlen total (int+ i 1) items (%item! items k freqs 0 0) freqs)
              (if (int< run 11)
                (self llen hlit dlen total (int+ i run) items (%item! items k freqs 17 (int- run 3)) freqs)
                (do (def take (if (int< 138 run) 138 run))
                    (self llen hlit dlen total (int+ i take) items (%item! items k freqs 18 (int- take 11)) freqs))))
            (do (def k1 (%item! items k freqs cur 0))
                (def rep (int- run 1))
                (if (int< rep 3)
                  (self llen hlit dlen total (int+ i 1) items k1 freqs)
                  (do (def take (if (int< 6 rep) 6 rep))
                      (self llen hlit dlen total (int+ (int+ i 1) take) items (%item! items k1 freqs 16 (int- take 3)) freqs))))))
      k)))

(def %item!
  (fn (_ items k freqs sym extra)
    (obj-set! items (int+ k 1) (pair sym extra))
    (obj-set! freqs (int+ sym 1) (int+ (obj-ref freqs (int+ sym 1)) 1))
    (int+ k 1)))

(def %clext (Vector from-list (list 2 3 7)))

; The header written: HLIT, HDIST, HCLEN, the code-length code's lengths in
; %order, then the two codes' lengths through it.  Answers nothing; the
; cost of the same, in bits, is %header-cost.
(def %put-header!
  (fn (_ w hlit hdist cllen clcodes hclen items nitems)
    (%put-bits! w (int- hlit 257) 5)
    (%put-bits! w (int- hdist 1) 5)
    (%put-bits! w (int- hclen 4) 4)
    ((fn (self i) (if (int< i hclen) (do (%put-bits! w (obj-ref cllen (int+ (obj-ref %order (int+ i 1)) 1)) 3) (self (int+ i 1))) ())) 0)
    ((fn (self k)
       (if (int< k nitems)
         (do (def it (obj-ref items (int+ k 1)))
             (%put-code! w clcodes cllen (first it))
             (if (int< (first it) 16) () (%put-bits! w (rest it) (obj-ref %clext (int+ (int- (first it) 16) 1))))
             (self (int+ k 1)))
         ()))
     0)))

(def %header-cost
  (fn (self cllen hclen items k nitems bits)
    (if (int< k nitems)
      (do (def it (obj-ref items (int+ k 1)))
          (self cllen hclen items (int+ k 1) nitems
            (int+ bits (int+ (obj-ref cllen (int+ (first it) 1)) (if (int< (first it) 16) 0 (obj-ref %clext (int+ (int- (first it) 16) 1)))))))
      (int+ bits (int+ 14 (int* 3 hclen))))))

; The order's position of the last code-length code used, plus one; at
; least 4.
(def %hclen
  (fn (self cllen i)
    (if (int< i 4) 4
      (if (int= (obj-ref cllen (int+ (obj-ref %order (int+ i 1)) 1)) 0) (self cllen (int- i 1)) (int+ i 1)))))

; --- Blocks ---

(def %BLOCK-TOKENS 16384)

; The tokens t0 below t1, which cover bytes b0 below b1 of src, written
; as one block: stored, fixed or dynamic, whichever is fewest bits.  put
; writes the tokens and the end code: %put-tokens!, or the engine's.
(def %block!
  (fn (_ w src lens vals t0 t1 b0 b1 final? put lfreq dfreq)
    (def llen (%code-lengths lfreq 286 15))
    (def dlen (%code-lengths dfreq 30 15))
    (def hlit (%used llen 285 257))
    (def hdist (%used dlen 29 1))
    (def items (Vector make (int+ hlit hdist) ()))
    (def clfreq (Vector make 19 0))
    (def nitems (%run-length llen hlit dlen (int+ hlit hdist) 0 items 0 clfreq))
    (def cllen (%code-lengths clfreq 19 7))
    (def hclen (%hclen cllen 18))
    (def extra (int+ (%extra-bits lfreq lext 257 0 29 0) (%extra-bits dfreq dext 0 0 30 0)))
    (def dynamic (int+ (int+ (%header-cost cllen hclen items 0 nitems 0) extra)
                       (int+ (%freq-cost lfreq llen 0 286 0) (%freq-cost dfreq dlen 0 30 0))))
    (def fixed (int+ extra (int+ (%freq-cost lfreq %fixed-lit-lengths 0 286 0) (%freq-cost dfreq %fixed-dist-lengths 0 30 0))))
    (def stored (int+ (int* 8 (int+ (int- b1 b0) 5)) (int* 40 (int>> (int- b1 b0) 16))))
    (match
      ((if (int< stored dynamic) (int< stored fixed) #f)
        (%stored! w src b0 b1 final?))
      ((int< fixed dynamic)
        (do (%put-bits! w (if final? 1 0) 1)
            (%put-bits! w 1 2)
            (put w lens vals t0 t1 %fixed-lit-codes %fixed-lit-lengths %fixed-dist-codes %fixed-dist-lengths)))
      (#t
        (do (def lcodes (Vector make 286 0))
            (def dcodes (Vector make 30 0))
            (def clcodes (Vector make 19 0))
            (%canonical! llen 286 lcodes)
            (%canonical! dlen 30 dcodes)
            (%canonical! cllen 19 clcodes)
            (%put-bits! w (if final? 1 0) 1)
            (%put-bits! w 2 2)
            (%put-header! w hlit hdist cllen clcodes hclen items nitems)
            (put w lens vals t0 t1 lcodes llen dcodes dlen))))))

; All the tokens in blocks of %BLOCK-TOKENS at most, the last one final
; when final? is.
(def %blocks!
  (fn (self w src lens vals t ntok b eng final?)
    (def t1 (if (int< %BLOCK-TOKENS (int- ntok t)) (int+ t %BLOCK-TOKENS) ntok))
    (def lfreq (Vector make 286 0))
    (def dfreq (Vector make 30 0))
    (obj-set! lfreq 257 1)
    (def b1 ((first (rest (rest eng))) lens vals t t1 lfreq dfreq b))
    (%block! w src lens vals t t1 b b1 (if (int= t1 ntok) final? #f) (first (rest eng)) lfreq dfreq)
    (if (int= t1 ntok) () (self w src lens vals t1 ntok b1 eng final?))))

; The tokens of n bytes at src into the token tables at lens and vals;
; answers their count.  The pure-x matcher, with its hash and chain tables.
(def %match-x
  (fn (_ src n lens vals)
    ; The regions are held here so the pointers into them stay good.
    (def head (%table %HSIZE))
    (def prev (%table %WSIZE))
    (%tokenize! src 0 n (rest head) (rest prev) lens vals 0)))

; A raw stream of n bytes at src, compressed by eng, a list (MATCH PUT COUNT
; ADLER): the matcher, the writer of a block's tokens, its counter and the
; Adler-32.  An empty input is one empty final block of fixed codes: the
; end code alone.
(def %compress-with!
  (fn (_ w src n eng)
    (%piece! w src n eng #t)
    (%align! w)))

; n bytes at src as blocks; the last final when final? is, and when there
; are no bytes and it is, the one empty final block.  A piece's matches
; reach back only inside the piece: each is tokenized with tables of its
; own.
(def %piece!
  (fn (_ w src n eng final?)
    (def lens (str-make (int<< (int+ n 1) 3)))
    (def vals (str-make (int<< (int+ n 1) 3)))
    (def ntok (if (int= n 0) 0 ((first eng) src n (str->ptr lens) (str->ptr vals))))
    (if (int= ntok 0)
      (if final? (do (%put-bits! w 1 1) (%put-bits! w 1 2) (%put-code! w %fixed-lit-codes %fixed-lit-lengths 256)) ())
      (%blocks! w src (str->ptr lens) (str->ptr vals) 0 ntok 0 eng final?))))

; --- A stream written a piece at a time ---
;
; gzip and its kin read a file in pieces and must not hold it whole.  A
; stream is a writer kept from piece to piece: each piece is written as
; blocks, none final until the last, and what they make in whole bytes is
; handed back as it is made; the bits short of a byte wait in the writer
; for the next piece.

; n bytes of buf from start written to stream w, the last of them when
; final? is: (OUT N), the whole bytes the stream gained.
(def %stream-feed
  (fn (_ w buf start n final?)
    (obj-set! w %OUTCNT 0)
    (%piece! w (%at (str->ptr buf) start) n (%engine-for n) final?)
    (if final? (%align! w) ())
    (def cnt (obj-ref w %OUTCNT))
    (def r (str-make (if (int< cnt 1) 1 cnt)))
    (if (int< 0 cnt) (mem-copy (str->ptr r) (obj-ref w %OUTP) cnt) ())
    (list r cnt)))

(def %compress!
  (fn (_ w src n) (%compress-with! w src n (%engine-for n))))

; --- The compiled engine (JIT), adopted only when it proves out ------
;
; x/codec/deflate-jit compiles the encoder's hot parts: the matcher,
; one compiled loop over the input, the token writer, the counter and the Adler-32.  As inflate's
; engine is, it is an entry of Compiled's made on demand, built for an
; input of %jit-threshold bytes or more or on (Deflate jit!), and adopted
; only after the streams it writes for the check inputs below are byte for
; byte the ones this file's four write.  The entry's value is a
; list, (MATCH PUT COUNT ADLER): this file's four, or the engine's.

; The check inputs: a short repeat and a long one (fixed codes, matches
; past 16 bytes and up to 258), varied text with repeats at many
; distances (dynamic codes, every length and distance class), and six-bit
; symbols from a generator (literals under dynamic codes).
(def %check-input
  (fn (_ which n)
    (def r (str-make n))
    (def p (str->ptr r))
    ((fn (self i s)
       (if (int< i n)
         (do (ptr-set! p i
               (match
                 ((int= which 0) (int+ 97 (int% i 3)))
                 ((int= which 1) (int+ 97 (int% (int+ (int* i i) (int/ i 7)) 23)))
                 (#t (int+ 32 (int& s 63))))
               1)
             (self (int+ i 1) (int% (int* s 75) 65537)))
         ()))
     0 1)
    r))


; The Adler-32 of n bytes at p, the fourth part.
(def %adler-x (fn (_ p n) (%adler32 p n 0 1 0)))

(def %engine-x (list %match-x %put-tokens! %count! %adler-x))

; Does an engine (MATCH PUT COUNT ADLER) write what this file's four write,
; and sum what they sum, on every check input?
(def %agrees?
  (fn (_ eng)
    (List all?
      (fn (_ c)
        (def r (%check-input (first c) (rest c)))
        (def want (%writer 64))
        (%compress-with! want (str->ptr r) (rest c) %engine-x)
        (def got (%writer 64))
        (%compress-with! got (str->ptr r) (rest c) eng)
        (and (int= (obj-ref want %OUTCNT) (obj-ref got %OUTCNT))
             (int= 0 (mem-cmp (obj-ref want %OUTP) (obj-ref got %OUTP) (obj-ref want %OUTCNT)))
             (int= (%adler-x (str->ptr r) (rest c)) ((first (rest (rest (rest eng)))) (str->ptr r) (rest c)))))
      (list (pair 0 30) (pair 0 1200) (pair 1 3000) (pair 2 2000)))))

; THE BAR, measured 2026-10-15 on arm64: the pure-x writer costs about 770
; objects a byte (3.1M for 4KB of text), the engine's build about 9.8M once,
; so the build repays itself past some 13KB; below the bar the pure-x writer
; serves.
(def %jit-threshold 16384)
(def %entry ())

(def %jit-try!
  (fn (_)
    (if (null? %entry)
      (set! %entry
        (Compiled make-on-demand (lit deflate) %engine-x
          (fn (_)
            (import x/codec/deflate-jit)
            ((prim-ref (lit deflate) (lit jit-make))
             (list (pair (lit outp) %OUTP) (pair (lit outcap) %OUTCAP) (pair (lit outcnt) %OUTCNT)
                   (pair (lit bitbuf) %BITBUF) (pair (lit bitcnt) %BITCNT))
             (list %length-code lbase lext %distance-code dbase dext)
             %room! %put-code! %agrees?))
          (fn (_ v) ())))
      ())
    ((fn (_ entry)
       (if (eq? (entry state) (lit interpreted)) (entry compile!) ())
       (eq? (entry state) (lit compiled)))
     %entry)))

; (MATCH PUT COUNT ADLER) for an input of n bytes: the engine's when it is
; built, or when n is past the bar and a build succeeds; else this file's.
(def %engine-for
  (fn (_ n)
    (if (if (int< n %jit-threshold) #f
          ((fn (_ entry) (if (null? entry) #t (eq? (entry state) (lit interpreted)))) %entry))
      (%jit-try!)
      ())
    ((fn (_ entry)
       (if (if (null? entry) #f (eq? (entry state) (lit compiled)))
         (entry compiled)
         %engine-x))
     %entry)))

; Adler-32 (RFC 1950 8) of n bytes at p, as inflate.x sums it.
(def %adler32
  (fn (self p n i a b)
    (if (int= i n) (int| (int<< b 16) a)
      (do (def a1 (int+ a (int& (ptr-ref p i 1) 255)))
          (def a2 (if (int< a1 65521) a1 (int- a1 65521)))
          (def b1 (int+ b a2))
          (self p n (int+ i 1) a2 (if (int< b1 65521) b1 (int- b1 65521)))))))

; The zlib wrapper (RFC 1950) around a raw stream written by body: the
; two-byte header, then the Adler-32 of the n bytes at src, big-endian.
(def %zlib!
  (fn (_ w src n body header)
    (%emit! w 120)
    (%emit! w header)
    (body w src n)
    (def sum ((first (rest (rest (rest (%engine-for n))))) src n))
    (%emit! w (int& (int>> sum 24) 255))
    (%emit! w (int& (int>> sum 16) 255))
    (%emit! w (int& (int>> sum 8) 255))
    (%emit! w (int& sum 255))))

(def %span
  (fn (_ s span)
    (match
      ((null? span) (list 0 (str-byte-len s)))
      ((null? (rest span)) (list (first span) (int- (str-byte-len s) (first span))))
      (#t (list (first span) (first (rest span)))))))

; Room for the stored blocks of n bytes: five a block, and one block at
; least; what any writer starts from, as no stream grows past it by more
; than the bits round up.
(def %stored-room
  (fn (_ n) (int+ (int+ n (int* 5 (int+ 1 (int>> n 16)))) 16)))

(def %answer (fn (_ w) (list (obj-ref w %OUT) (obj-ref w %OUTCNT))))

(def %stored-body (fn (_ w src n) (%stored! w src 0 n #t)))

(def %run
  (fn (_ s span body header)
    (def sp (%span s span))
    (def n (first (rest sp)))
    (def w (%writer (%stored-room n)))
    (def src (%at (str->ptr s) (first sp)))
    (if (null? header) (body w src n) (%zlib! w src n body header))
    (%answer w)))

(def-class Deflate ()
  (doc "DEFLATE streams written in pure x-lang: stored, or compressed with LZ77 and Huffman codes as zlib's deflate does at its default level. Each writer answers (OUT N): a byte region and how many of its bytes the stream is. A raw stream can also be written a piece at a time: stream, feed.")
  (static
    (method raw (self (param s STRING "The bytes to compress")
                      . (param span LIST "START, then LENGTH: which bytes of s; default all of s"))
      (doc "A raw DEFLATE stream (RFC 1951), compressed: repeats of three bytes or more within 32K found through a hash chain and coded as length/distance pairs, each block of up to 16384 tokens under its own Huffman codes, the fixed ones or stored, whichever is fewest bits. Give LENGTH for binary input: s's own length is measured to its first NUL."
        (returns LIST "(OUT N): the stream's region and its byte count")
        (example "(< (first (rest (Deflate raw \"abcabcabcabcabcabc\"))) 18)" "#t"))
      (%run s span %compress! ()))
    (method zlib (self (param s STRING "The bytes to compress")
                       . (param span LIST "START, then LENGTH, as for raw"))
      (doc "A zlib stream (RFC 1950) around a compressed raw stream: the two-byte header (method 8, a 32K window, the default level's FLEVEL, FCHECK making the pair a multiple of 31), then the Adler-32 of the bytes big-endian. What git writes a loose object as."
        (returns LIST "(OUT N): the stream's region and its byte count")
        (example "(first (rest (Deflate zlib \"abc\")))" "11"))
      (%run s span %compress! 156))
    (method stored (self (param s STRING "The bytes to carry")
                         . (param span LIST "START, then LENGTH, as for raw"))
      (doc "A raw DEFLATE stream (RFC 1951) of stored blocks: the bytes as they are, five bytes of framing a block of up to 65535."
        (returns LIST "(OUT N): the stream's region and its byte count")
        (example "(first (rest (Deflate stored \"abc\")))" "8"))
      (%run s span %stored-body ()))
    (method zlib-stored (self (param s STRING "The bytes to carry")
                              . (param span LIST "START, then LENGTH, as for raw"))
      (doc "A zlib stream (RFC 1950) of stored blocks: the header with FLEVEL 0 (0x78 0x01), the stored blocks, the Adler-32."
        (returns LIST "(OUT N): the stream's region and its byte count")
        (example "(first (rest (Deflate zlib-stored \"abc\")))" "14"))
      (%run s span %stored-body 1))
    (method stream (self)
      (doc "A raw DEFLATE stream (RFC 1951) written a piece at a time with (Deflate feed): what gzip wants of a file it must not read whole. Each piece is compressed as raw's input is, matches reaching back only inside it."
        (returns OBJECT "The stream")
        (example "(first (rest (Deflate feed (Deflate stream) \"\" 0 0 #t)))" "2"))
      (%writer 64))
    (method feed (self (param w OBJECT "A (Deflate stream)")
                       (param s STRING "Bytes holding the next piece")
                       (param start INTEGER "Where the piece starts in s")
                       (param n INTEGER "How many bytes it is")
                       (param final BOOL "Is this the last piece? Its last block is then final and the stream padded to a byte"))
      (doc "Compress n more bytes into the stream. Answers the whole bytes of stream they made; the bits short of a byte wait for the next piece, and the last piece (final) writes them out."
        (returns LIST "(OUT N): a region and how many of its bytes the stream gained")
        (example "(< (first (rest (Deflate feed (Deflate stream) \"abcabcabcabcabcabc\" 0 18 #t))) 18)" "#t"))
      (%stream-feed w s start n final))
    (method jit! (self)
      (doc "Build and adopt the compiled matcher and token writer (JIT; ARM64 and x86-64 backends) now, if the streams they write for the check inputs are byte for byte the pure-x encoder's. Idempotent. Answers #t when the engine is active, #f when unavailable -- the pure-x encoder carries on, with the same output. raw, zlib and feed build it on their own for an input of 16KB or more."
        (returns BOOL "#t when the compiled engine is active"))
      (%jit-try!))))

(doc (provide x/codec/deflate Deflate)
  "DEFLATE streams written in pure x-lang: (Deflate raw s) and (Deflate zlib s) compressed, (Deflate stored s) and (Deflate zlib-stored s) the bytes as they are; each answers (OUT N).")

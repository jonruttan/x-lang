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
; the output is a region and its count, as Inflate answers.
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

(def %add (prim-ref (lit int) (lit +)))
(def %sub (prim-ref (lit int) (lit -)))
(def %mul (prim-ref (lit int) (lit *)))
(def %lt (prim-ref (lit int) (lit <)))
(def %eq (prim-ref (lit int) (lit =)))
(def %and (prim-ref (lit int) (lit &)))
(def %or (prim-ref (lit int) (lit |)))
(def %shl (prim-ref (lit int) (lit <<)))
(def %shr (prim-ref (lit int) (lit >>)))
(def %oref (prim-ref (lit obj) (lit ref)))
(def %oset! (prim-ref (lit obj) (lit set!)))
(def %pref (prim-ref (lit ptr) (lit ref)))
(def %pset! (prim-ref (lit ptr) (lit set!)))
(def %make-str (prim-ref (lit str) (lit make)))
(def %str->ptr (prim-ref (lit str) (lit ->ptr)))
(def %ptr->int (prim-ref (lit ptr) (lit ->int)))
(def %int->ptr (prim-ref (lit int) (lit ->ptr)))
(def %mem-copy (prim-ref (lit mem) (lit copy)))
(def %mem-set (prim-ref (lit mem) (lit set)))
(def %str-byte-len (prim-ref (lit str) (lit byte-len)))

(def %at (fn (_ p off) (%int->ptr (%add (%ptr->int p) off))))

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
    (def out (%make-str cap))
    (%oset! w %OUT out)
    (%oset! w %OUTP (%str->ptr out))
    (%oset! w %OUTCAP cap)
    w))

; The output region doubled from ncap until `need` bytes fit.
(def %grow!
  (fn (self w need ncap)
    (if (%lt ncap need) (self w need (%shl ncap 1))
      (do (def r (%make-str ncap))
          (def cnt (%oref w %OUTCNT))
          (if (%lt 0 cnt) (%mem-copy (%str->ptr r) (%oref w %OUTP) cnt) ())
          (%oset! w %OUT r)
          (%oset! w %OUTP (%str->ptr r))
          (%oset! w %OUTCAP ncap)))))

(def %room!
  (fn (_ w n)
    (def need (%add (%oref w %OUTCNT) n))
    (def cap (%oref w %OUTCAP))
    (if (%lt cap need) (%grow! w need (%shl cap 1)) ())))

(def %emit!
  (fn (_ w b)
    (%room! w 1)
    (def at (%oref w %OUTCNT))
    (%pset! (%oref w %OUTP) at b 1)
    (%oset! w %OUTCNT (%add at 1))))

; Whole bytes of the bit buffer out, low byte first (3.1.1).
(def %emit-whole!
  (fn (self w)
    (def cnt (%oref w %BITCNT))
    (if (%lt cnt 8) ()
      (do (%emit! w (%and (%oref w %BITBUF) 255))
          (%oset! w %BITBUF (%shr (%oref w %BITBUF) 8))
          (%oset! w %BITCNT (%sub cnt 8))
          (self w)))))

; The low n bits of value, least significant first.
(def %put-bits!
  (fn (_ w value n)
    (%oset! w %BITBUF (%or (%oref w %BITBUF) (%shl value (%oref w %BITCNT))))
    (%oset! w %BITCNT (%add (%oref w %BITCNT) n))
    (%emit-whole! w)))

; The bits in hand padded to a byte boundary.
(def %align!
  (fn (_ w)
    (if (%lt 0 (%oref w %BITCNT))
      (do (%emit! w (%and (%oref w %BITBUF) 255))
          (%oset! w %BITBUF 0)
          (%oset! w %BITCNT 0))
      ())))

; --- Stored blocks ---

; The stored blocks of n bytes at src: each a header byte (BFINAL in bit 0,
; type 00), LEN and its complement little-endian, then the bytes.  An empty
; input is one empty final block.
(def %stored!
  (fn (self w src i n final?)
    (def len (if (%lt 65535 (%sub n i)) 65535 (%sub n i)))
    (def last? (%eq (%add i len) n))
    (%put-bits! w (if (if last? final? #f) 1 0) 1)
    (%put-bits! w 0 2)
    (%align! w)
    (%emit! w (%and len 255))
    (%emit! w (%shr len 8))
    (%emit! w (%and (~ len) 255))
    (%emit! w (%and (%shr (~ len) 8) 255))
    (%room! w len)
    (if (%lt 0 len) (%mem-copy (%at (%oref w %OUTP) (%oref w %OUTCNT)) (%at src i) len) ())
    (%oset! w %OUTCNT (%add (%oref w %OUTCNT) len))
    (if last? () (self w src (%add i len) n final?))))

; --- The tables (3.2.5) ---

(def %lbase (Vector from-list (list 3 4 5 6 7 8 9 10 11 13 15 17 19 23 27 31 35 43 51 59 67 83 99 115 131 163 195 227 258)))
(def %lext (Vector from-list (list 0 0 0 0 0 0 0 0 1 1 1 1 2 2 2 2 3 3 3 3 4 4 4 4 5 5 5 5 0)))
(def %dbase (Vector from-list (list 1 2 3 4 5 7 9 13 17 25 33 49 65 97 129 193 257 385 513 769 1025 1537 2049 3073 4097 6145 8193 12289 16385 24577)))
(def %dext (Vector from-list (list 0 0 0 0 1 1 2 2 3 3 4 4 5 5 6 6 7 7 8 8 9 9 10 10 11 11 12 12 13 13)))

; Slot len+1 of %length-code holds the length code (0..28) of a match of
; len bytes, 3..258.
(def %length-code (Vector make 259 0))
((fn (self code)
   (if (%lt code 29)
     (do ((fn (fill k n) (if (%lt k n) (do (%oset! %length-code (%add (%add (%oref %lbase (%add code 1)) k) 1) code) (fill (%add k 1) n)) ()))
          0 (if (%eq code 28) 1 (%shl 1 (%oref %lext (%add code 1)))))
         (self (%add code 1)))
     ()))
 0)

; The distance code of d: slot d of %distance-code for d up to 256, slot
; 256 + (d-1 >> 7) + 1 past it -- zlib's two-part table.
(def %distance-code (Vector make 512 0))
((fn (self code)
   (if (%lt code 30)
     (do (def base (%oref %dbase (%add code 1)))
         (def span (%shl 1 (%oref %dext (%add code 1))))
         (if (%lt code 16)
           ((fn (fill d) (if (%lt d (%add base span)) (do (%oset! %distance-code d code) (fill (%add d 1))) ()))
            base)
           ((fn (fill d) (if (%lt d (%add base span)) (do (%oset! %distance-code (%add 257 (%shr (%sub d 1) 7)) code) (fill (%add d 128))) ()))
            base))
         (self (%add code 1)))
     ()))
 0)

(def %dcode
  (fn (_ d) (if (%lt d 257) (%oref %distance-code d) (%oref %distance-code (%add 257 (%shr (%sub d 1) 7))))))

; The 9-bit reversal, once: slot i+1 holds the bits of i the other way.
(def %rev9 (Vector make 512 0))
((fn (self i)
   (if (%lt i 512)
     (do (%oset! %rev9 (%add i 1) (%or (%shr (%oref %rev9 (%add (%shr i 1) 1)) 1) (%shl (%and i 1) 8)))
         (self (%add i 1)))
     ()))
 1)

; The low len bits of code (len up to 15) reversed: a Huffman code is
; written most significant bit first into a stream read least first.
(def %reverse
  (fn (_ code len)
    (if (%lt len 10) (%shr (%oref %rev9 (%add code 1)) (%sub 9 len))
      (%or (%shl (%oref %rev9 (%add (%and code 511) 1)) (%sub len 9))
           (%shr (%oref %rev9 (%add (%shr code 9) 1)) (%sub 18 len))))))

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
    (%and (%add (%mul (%and (%pref p i 1) 255) 1089)
                (%add (%mul (%and (%pref p (%add i 1) 1) 255) 33)
                      (%and (%pref p (%add i 2) 1) 255)))
          %HMASK)))

; The tables are byte regions, not vectors: a Vector of 32768 slots costs
; 12.7M objects to make (its fill is a loop), a region one allocation and
; a memset.  The hash and chain tables hold 4-byte slots, a position kept
; plus one so a zeroed slot reads as none; the token tables hold 8-byte
; words, which the compiled writer reads as words.
(def %tref (fn (_ t i) (%pref t (%shl i 3) 8)))
(def %tset! (fn (_ t i v) (%pset! t (%shl i 3) v 8)))

(def %table
  (fn (_ slots)
    (def r (%make-str (%shl slots 2)))
    (%mem-set (%str->ptr r) 0 (%shl slots 2))
    (pair r (%str->ptr r))))

; Position i entered: its chain link is what the hash headed before.
(def %insert!
  (fn (_ p i head prev)
    (def h (%shl (%hash p i) 2))
    (%pset! prev (%shl (%and i %WMASK) 2) (%pref head h 4) 4)
    (%pset! head h (%add i 1) 4)))

; How many bytes from a and b agree, up to limit: eight at a time while
; eight are left, then one.
(def %agree
  (fn (self p a b k limit)
    (if (%lt (%sub limit k) 8)
      (%agree-bytes p a b k limit)
      (if (%eq (%pref p (%add a k) 8) (%pref p (%add b k) 8))
        (self p a b (%add k 8) limit)
        (%agree-bytes p a b k limit)))))

(def %agree-bytes
  (fn (self p a b k limit)
    (if (%lt k limit)
      (if (%eq (%pref p (%add a k) 1) (%pref p (%add b k) 1))
        (self p a b (%add k 1) limit)
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
    (if (if (%lt cand 0) #t
          (if (%lt %WSIZE (%sub i cand)) #t
            (if (%eq steps 0) #t
              (if (%lt %NICE blen) #t (%lt (%sub limit 1) blen)))))
      (pair blen bdist)
      (do (def len (if (%eq (%pref p (%add cand blen) 1) (%pref p (%add i blen) 1))
                     (%agree p cand i 0 limit)
                     0))
          (def next (%sub (%pref prev (%shl (%and cand %WMASK) 2) 4) 1))
          (if (%lt blen len)
            (self p i limit next prev (%sub steps 1) len (%sub i cand))
            (self p i limit next prev (%sub steps 1) blen bdist))))))

; The tokens of n bytes at p: slot t+1 of lens holds a match's length, 0
; for a literal; of vals its distance, or the literal byte.  Answers the
; token count.  The positions inside a match of up to %MAXINSERT bytes are
; entered in the hash so later matches can start there; a longer match is
; skipped over, as zlib's deflate_fast does, since what it covers is
; already a repeat.
(def %tokenize!
  (fn (self p i n head prev lens vals t)
    (if (%lt i n)
      (do (def m (if (%lt (%sub n i) %MINMATCH) (pair 0 0)
                   (do (def h (%shl (%hash p i) 2))
                       (def cand (%sub (%pref head h 4) 1))
                       (%pset! prev (%shl (%and i %WMASK) 2) (%add cand 1) 4)
                       (%pset! head h (%add i 1) 4)
                       (%longest p i (if (%lt (%sub n i) %MAXMATCH) (%sub n i) %MAXMATCH)
                         cand prev %MAXCHAIN (%sub %MINMATCH 1) 0))))
          (if (%lt (first m) %MINMATCH)
            (do (%tset! lens t 0)
                (%tset! vals t (%and (%pref p i 1) 255))
                (self p (%add i 1) n head prev lens vals (%add t 1)))
            (do (%tset! lens t (first m))
                (%tset! vals t (rest m))
                (if (%lt %MAXINSERT (first m)) () (%insert-run! p (%add i 1) (%add i (first m)) n head prev))
                (self p (%add i (first m)) n head prev lens vals (%add t 1)))))
      t)))

; Positions from i below end entered, while three bytes remain at each.
(def %insert-run!
  (fn (self p i end n head prev)
    (if (%lt i end)
      (do (if (%lt (%sub n i) %MINMATCH) () (%insert! p i head prev))
          (self p (%add i 1) end n head prev))
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
      ((%lt (first (first front)) (first (first leaves))) (list (first front) leaves (rest front) back))
      (#t (list (first leaves) (rest leaves) front back)))))

(def %merge-tree
  (fn (self leaves front back)
    (if (if (null? front) (not (null? back)) #f) (self leaves (List reverse back) ())
     (if (if (null? leaves) (if (null? back) (null? (rest front)) #f) #f) (first front)
      (do (def a (%take-least leaves front back))
          (def b (%take-least (first (rest a)) (first (rest (rest a))) (first (rest (rest (rest a))))))
          (def node (list (%add (first (first a)) (first (first b))) (first a) (first b)))
          (self (first (rest b)) (first (rest (rest b))) (pair node (first (rest (rest (rest b)))))))))))

; Each leaf's depth into lengths (slot sym+1), from a node at depth d.
(def %depths!
  (fn (self node d lengths)
    (if (null? (rest (rest node)))
      (%oset! lengths (%add (first (rest node)) 1) d)
      (do (self (first (rest node)) (%add d 1) lengths)
          (self (first (rest (rest node))) (%add d 1) lengths)))))

(def %max-length
  (fn (self lengths i n best)
    (if (%lt i n)
      (self lengths (%add i 1) n (if (%lt best (%oref lengths (%add i 1))) (%oref lengths (%add i 1)) best))
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
        ((%eq used 0) (list (list 1 0) (list 1 1)))
        ((%eq used 1) (list (list 1 (if (%eq (%oref freqs 1) 0) 0 1))))
        (#t ())))
    (def leaves
      (List sort (fn (_ a b) (%lt (first a) (first b)))
        ((fn (collect i acc)
           (if (%lt i n)
             (collect (%add i 1) (if (%lt 0 (%oref freqs (%add i 1))) (pair (list (%oref freqs (%add i 1)) i) acc) acc))
             acc))
         0 pads)))
    (def lengths (Vector make n 0))
    (%depths! (%merge-tree leaves () ()) 0 lengths)
    (if (%lt limit (%max-length lengths 0 n 0))
      (do (def halved (Vector make n 0))
          ((fn (halve i)
             (if (%lt i n)
               (do (def f (%oref freqs (%add i 1)))
                   (%oset! halved (%add i 1) (if (%lt 1 f) (%shr f 1) f))
                   (halve (%add i 1)))
               ()))
           0)
          (self halved n limit))
      lengths)))

; How many of n symbols have a frequency.
(def %symbols-used
  (fn (self freqs i n k)
    (if (%lt i n) (self freqs (%add i 1) n (if (%lt 0 (%oref freqs (%add i 1))) (%add k 1) k)) k)))

; The canonical codes for lengths (slot sym+1), reversed for writing, into
; codes: each length's first code is the one past the length before's
; last, doubled (3.2.2).
(def %canonical!
  (fn (_ lengths n codes)
    (def counts (Vector make 16 0))
    ((fn (count i) (if (%lt i n) (do (def l (%oref lengths (%add i 1))) (if (%eq l 0) () (%oset! counts (%add l 1) (%add (%oref counts (%add l 1)) 1))) (count (%add i 1))) ()))
     0)
    (def next (Vector make 16 0))
    ((fn (first-codes len code)
       (if (%lt len 16)
         (do (%oset! next (%add len 1) code)
             (first-codes (%add len 1) (%shl (%add code (%oref counts (%add len 1))) 1)))
         ()))
     1 0)
    ((fn (assign i)
       (if (%lt i n)
         (do (def l (%oref lengths (%add i 1)))
             (if (%eq l 0) ()
               (do (%oset! codes (%add i 1) (%reverse (%oref next (%add l 1)) l))
                   (%oset! next (%add l 1) (%add (%oref next (%add l 1)) 1))))
             (assign (%add i 1)))
         ()))
     0)))

; The fixed codes (3.2.6): literal/length lengths 8 to 143, 9 to 255, 7 to
; 279, 8 to 287; every distance 5.
(def %fixed-lit-lengths (Vector make 288 0))
((fn (self i) (if (%lt i 288) (do (%oset! %fixed-lit-lengths (%add i 1) (if (%lt i 144) 8 (if (%lt i 256) 9 (if (%lt i 280) 7 8)))) (self (%add i 1))) ())) 0)
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
    (if (%lt t t1)
      (do (def len (%tref lens t))
          (if (%eq len 0)
            (do (def s (%add (%tref vals t) 1)) (%oset! lfreq s (%add (%oref lfreq s) 1)))
            (do (def s (%add (%add 257 (%oref %length-code (%add len 1))) 1))
                (%oset! lfreq s (%add (%oref lfreq s) 1))
                (def d (%add (%dcode (%tref vals t)) 1))
                (%oset! dfreq d (%add (%oref dfreq d) 1))))
          (self lens vals (%add t 1) t1 lfreq dfreq (%add b (if (%eq len 0) 1 len))))
      b)))

; The bits n symbols take: each one's count times its code's length.
(def %freq-cost
  (fn (self freqs lengths i n bits)
    (if (%lt i n)
      (self freqs lengths (%add i 1) n (%add bits (%mul (%oref freqs (%add i 1)) (%oref lengths (%add i 1)))))
      bits)))

; The extra bits of the block's lengths and distances, whatever the codes.
(def %extra-bits
  (fn (self freqs ext base i n bits)
    (if (%lt i n)
      (self freqs ext base (%add i 1) n (%add bits (%mul (%oref freqs (%add (%add base i) 1)) (%oref ext (%add i 1)))))
      bits)))

; A code's symbol written: its reversed code, its length bits.
(def %put-code!
  (fn (_ w codes lengths sym)
    (%put-bits! w (%oref codes (%add sym 1)) (%oref lengths (%add sym 1)))))

; The tokens t0 below t1 written under the codes, then the end code.
(def %put-tokens!
  (fn (self w lens vals t t1 lcodes llen dcodes dlen)
    (if (%lt t t1)
      (do (def len (%tref lens t))
          (if (%eq len 0)
            (%put-code! w lcodes llen (%tref vals t))
            (do (def lc (%oref %length-code (%add len 1)))
                (%put-code! w lcodes llen (%add 257 lc))
                (if (%eq (%oref %lext (%add lc 1)) 0) ()
                  (%put-bits! w (%sub len (%oref %lbase (%add lc 1))) (%oref %lext (%add lc 1))))
                (def d (%tref vals t))
                (def dc (%dcode d))
                (%put-code! w dcodes dlen dc)
                (if (%eq (%oref %dext (%add dc 1)) 0) ()
                  (%put-bits! w (%sub d (%oref %dbase (%add dc 1))) (%oref %dext (%add dc 1))))))
          (self w lens vals (%add t 1) t1 lcodes llen dcodes dlen))
      (%put-code! w lcodes llen 256))))

; --- The dynamic header (3.2.7) ---

; The order the code-length code's lengths are sent in.
(def %order (Vector from-list (list 16 17 18 0 8 7 9 6 10 5 11 4 12 3 13 2 14 1 15)))

; The last slot of lengths (n of them) that is not zero, plus one; at least
; floor.
(def %used
  (fn (self lengths i floor)
    (if (%lt i floor) floor
      (if (%eq (%oref lengths (%add i 1)) 0) (self lengths (%sub i 1) floor) (%add i 1)))))

; The lit/len lengths then the dist lengths as one sequence, run-length
; coded as the code-length alphabet has it: a length as itself; 16, the
; last one again 3..6 times; 17, zero 3..10 times; 18, zero 11..138 times.
; Each item into items as (SYM . EXTRA), their count answered; freqs of
; the 19 symbols tallied.
(def %length-at
  (fn (_ llen hlit dlen i) (if (%lt i hlit) (%oref llen (%add i 1)) (%oref dlen (%add (%sub i hlit) 1)))))

(def %run-length
  (fn (self llen hlit dlen total i items k freqs)
    (if (%lt i total)
      (do (def cur (%length-at llen hlit dlen i))
          (def run ((fn (count j) (if (if (%lt j total) (%eq (%length-at llen hlit dlen j) cur) #f) (count (%add j 1)) (%sub j i))) (%add i 1)))
          (if (%eq cur 0)
            (if (%lt run 3)
              (self llen hlit dlen total (%add i 1) items (%item! items k freqs 0 0) freqs)
              (if (%lt run 11)
                (self llen hlit dlen total (%add i run) items (%item! items k freqs 17 (%sub run 3)) freqs)
                (do (def take (if (%lt 138 run) 138 run))
                    (self llen hlit dlen total (%add i take) items (%item! items k freqs 18 (%sub take 11)) freqs))))
            (do (def k1 (%item! items k freqs cur 0))
                (def rep (%sub run 1))
                (if (%lt rep 3)
                  (self llen hlit dlen total (%add i 1) items k1 freqs)
                  (do (def take (if (%lt 6 rep) 6 rep))
                      (self llen hlit dlen total (%add (%add i 1) take) items (%item! items k1 freqs 16 (%sub take 3)) freqs))))))
      k)))

(def %item!
  (fn (_ items k freqs sym extra)
    (%oset! items (%add k 1) (pair sym extra))
    (%oset! freqs (%add sym 1) (%add (%oref freqs (%add sym 1)) 1))
    (%add k 1)))

(def %clext (Vector from-list (list 2 3 7)))

; The header written: HLIT, HDIST, HCLEN, the code-length code's lengths in
; %order, then the two codes' lengths through it.  Answers nothing; the
; cost of the same, in bits, is %header-cost.
(def %put-header!
  (fn (_ w hlit hdist cllen clcodes hclen items nitems)
    (%put-bits! w (%sub hlit 257) 5)
    (%put-bits! w (%sub hdist 1) 5)
    (%put-bits! w (%sub hclen 4) 4)
    ((fn (self i) (if (%lt i hclen) (do (%put-bits! w (%oref cllen (%add (%oref %order (%add i 1)) 1)) 3) (self (%add i 1))) ())) 0)
    ((fn (self k)
       (if (%lt k nitems)
         (do (def it (%oref items (%add k 1)))
             (%put-code! w clcodes cllen (first it))
             (if (%lt (first it) 16) () (%put-bits! w (rest it) (%oref %clext (%add (%sub (first it) 16) 1))))
             (self (%add k 1)))
         ()))
     0)))

(def %header-cost
  (fn (self cllen hclen items k nitems bits)
    (if (%lt k nitems)
      (do (def it (%oref items (%add k 1)))
          (self cllen hclen items (%add k 1) nitems
            (%add bits (%add (%oref cllen (%add (first it) 1)) (if (%lt (first it) 16) 0 (%oref %clext (%add (%sub (first it) 16) 1)))))))
      (%add bits (%add 14 (%mul 3 hclen))))))

; The order's position of the last code-length code used, plus one; at
; least 4.
(def %hclen
  (fn (self cllen i)
    (if (%lt i 4) 4
      (if (%eq (%oref cllen (%add (%oref %order (%add i 1)) 1)) 0) (self cllen (%sub i 1)) (%add i 1)))))

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
    (def items (Vector make (%add hlit hdist) ()))
    (def clfreq (Vector make 19 0))
    (def nitems (%run-length llen hlit dlen (%add hlit hdist) 0 items 0 clfreq))
    (def cllen (%code-lengths clfreq 19 7))
    (def hclen (%hclen cllen 18))
    (def extra (%add (%extra-bits lfreq %lext 257 0 29 0) (%extra-bits dfreq %dext 0 0 30 0)))
    (def dynamic (%add (%add (%header-cost cllen hclen items 0 nitems 0) extra)
                       (%add (%freq-cost lfreq llen 0 286 0) (%freq-cost dfreq dlen 0 30 0))))
    (def fixed (%add extra (%add (%freq-cost lfreq %fixed-lit-lengths 0 286 0) (%freq-cost dfreq %fixed-dist-lengths 0 30 0))))
    (def stored (%add (%mul 8 (%add (%sub b1 b0) 5)) (%mul 40 (%shr (%sub b1 b0) 16))))
    (match
      ((if (%lt stored dynamic) (%lt stored fixed) #f)
        (%stored! w src b0 b1 final?))
      ((%lt fixed dynamic)
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

; All the tokens in blocks of %BLOCK-TOKENS at most, the last one final.
(def %blocks!
  (fn (self w src lens vals t ntok b put)
    (def t1 (if (%lt %BLOCK-TOKENS (%sub ntok t)) (%add t %BLOCK-TOKENS) ntok))
    (def lfreq (Vector make 286 0))
    (def dfreq (Vector make 30 0))
    (%oset! lfreq 257 1)
    (def b1 (%count! lens vals t t1 lfreq dfreq b))
    (%block! w src lens vals t t1 b b1 (%eq t1 ntok) put lfreq dfreq)
    (if (%eq t1 ntok) () (self w src lens vals t1 ntok b1 put))))

; A raw stream of n bytes at src, compressed, its tokens written by put.
; An empty input is one empty final block of fixed codes: the end code
; alone.
(def %compress-with!
  (fn (_ w src n put)
    ; The regions are held here so the pointers into them stay good.
    (def head (%table %HSIZE))
    (def prev (%table %WSIZE))
    (def lens (%make-str (%shl (%add n 1) 3)))
    (def vals (%make-str (%shl (%add n 1) 3)))
    (def ntok (%tokenize! src 0 n (rest head) (rest prev) (%str->ptr lens) (%str->ptr vals) 0))
    (if (%eq ntok 0)
      (do (%put-bits! w 1 1) (%put-bits! w 1 2) (%put-code! w %fixed-lit-codes %fixed-lit-lengths 256))
      (%blocks! w src (%str->ptr lens) (%str->ptr vals) 0 ntok 0 put))
    (%align! w)))

(def %compress!
  (fn (_ w src n) (%compress-with! w src n (%tokens-for n))))

; --- The compiled engine (JIT), adopted only when it proves out ------
;
; x/codec/deflate-jit compiles the token writer, the encoder's hot part:
; on input that does not repeat it was four fifths of the cost (10 KB:
; 10M objects writing blocks against 2.3M finding matches).  As inflate's
; engine is, it is an entry of Compiled's made on demand, built for an
; input of %jit-threshold bytes or more or on (Deflate jit!), and adopted
; only after the streams it writes for the check inputs below are byte for
; byte the ones %put-tokens! writes.

; The check inputs: a short repeat (fixed codes), varied text with repeats
; at many distances (dynamic codes, every length and distance class), and
; six-bit symbols from a generator (literals under dynamic codes).
(def %check-input
  (fn (_ which n)
    (def r (%make-str n))
    (def p (%str->ptr r))
    ((fn (self i s)
       (if (%lt i n)
         (do (%pset! p i
               (match
                 ((%eq which 0) (%add 97 (%int-mod i 3)))
                 ((%eq which 1) (%add 97 (%int-mod (%add (%mul i i) (%int-div i 7)) 23)))
                 (#t (%add 32 (%and s 63))))
               1)
             (self (%add i 1) (%int-mod (%mul s 75) 65537)))
         ()))
     0 1)
    r))

(def %int-mod (prim-ref (lit int) (lit %)))
(def %int-div (prim-ref (lit int) (lit /)))
(def %mem-cmp (prim-ref (lit mem) (lit cmp)))

; Does a token writer write what %put-tokens! writes, on every check input?
(def %agrees?
  (fn (_ put)
    (List all?
      (fn (_ c)
        (def r (%check-input (first c) (rest c)))
        (def want (%writer 64))
        (%compress-with! want (%str->ptr r) (rest c) %put-tokens!)
        (def got (%writer 64))
        (%compress-with! got (%str->ptr r) (rest c) put)
        (and (%eq (%oref want %OUTCNT) (%oref got %OUTCNT))
             (%eq 0 (%mem-cmp (%oref want %OUTP) (%oref got %OUTP) (%oref want %OUTCNT)))))
      (list (pair 0 30) (pair 1 3000) (pair 2 2000)))))

; THE BAR: the engine's build is seconds of compiling, worth it past some
; tens of thousands of tokens; below the bar the pure-x writer serves.
(def %jit-threshold 32768)
(def %entry ())

(def %jit-try!
  (fn (_)
    (if (null? %entry)
      (set! %entry
        (Compiled make-on-demand (lit deflate) %put-tokens!
          (fn (_)
            (import x/codec/deflate-jit)
            ((prim-ref (lit deflate) (lit jit-make))
             (list (pair (lit outp) %OUTP) (pair (lit outcap) %OUTCAP) (pair (lit outcnt) %OUTCNT)
                   (pair (lit bitbuf) %BITBUF) (pair (lit bitcnt) %BITCNT))
             (list %length-code %lbase %lext %distance-code %dbase %dext)
             %room! %put-code! %agrees?))
          (fn (_ v) ())))
      ())
    ((fn (_ entry)
       (if (eq? (entry state) (lit interpreted)) (entry compile!) ())
       (eq? (entry state) (lit compiled)))
     %entry)))

; The token writer for an input of n bytes: the engine's when it is built,
; or when n is past the bar and a build succeeds; else %put-tokens!.
(def %tokens-for
  (fn (_ n)
    (if (if (%lt n %jit-threshold) #f
          ((fn (_ entry) (if (null? entry) #t (eq? (entry state) (lit interpreted)))) %entry))
      (%jit-try!)
      ())
    ((fn (_ entry)
       (if (if (null? entry) #f (eq? (entry state) (lit compiled)))
         (entry compiled)
         %put-tokens!))
     %entry)))

; Adler-32 (RFC 1950 8) of n bytes at p, as inflate.x sums it.
(def %adler32
  (fn (self p n i a b)
    (if (%eq i n) (%or (%shl b 16) a)
      (do (def a1 (%add a (%and (%pref p i 1) 255)))
          (def a2 (if (%lt a1 65521) a1 (%sub a1 65521)))
          (def b1 (%add b a2))
          (self p n (%add i 1) a2 (if (%lt b1 65521) b1 (%sub b1 65521)))))))

; The zlib wrapper (RFC 1950) around a raw stream written by body: the
; two-byte header, then the Adler-32 of the n bytes at src, big-endian.
(def %zlib!
  (fn (_ w src n body header)
    (%emit! w 120)
    (%emit! w header)
    (body w src n)
    (def sum (%adler32 src n 0 1 0))
    (%emit! w (%and (%shr sum 24) 255))
    (%emit! w (%and (%shr sum 16) 255))
    (%emit! w (%and (%shr sum 8) 255))
    (%emit! w (%and sum 255))))

(def %span
  (fn (_ s span)
    (match
      ((null? span) (list 0 (%str-byte-len s)))
      ((null? (rest span)) (list (first span) (%sub (%str-byte-len s) (first span))))
      (#t (list (first span) (first (rest span)))))))

; Room for the stored blocks of n bytes: five a block, and one block at
; least; what any writer starts from, as no stream grows past it by more
; than the bits round up.
(def %stored-room
  (fn (_ n) (%add (%add n (%mul 5 (%add 1 (%shr n 16)))) 16)))

(def %answer (fn (_ w) (list (%oref w %OUT) (%oref w %OUTCNT))))

(def %stored-body (fn (_ w src n) (%stored! w src 0 n #t)))

(def %run
  (fn (_ s span body header)
    (def sp (%span s span))
    (def n (first (rest sp)))
    (def w (%writer (%stored-room n)))
    (def src (%at (%str->ptr s) (first sp)))
    (if (null? header) (body w src n) (%zlib! w src n body header))
    (%answer w)))

(def-class Deflate ()
  (doc "DEFLATE streams written in pure x-lang: stored, or compressed with LZ77 and Huffman codes as zlib's deflate does at its default level. Each writer answers (OUT N): a byte region and how many of its bytes the stream is.")
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
    (method jit! (self)
      (doc "Build and adopt the compiled token writer (JIT; ARM64 and x86-64 backends) now, if the streams it writes for the check inputs are byte for byte the pure-x writer's. Idempotent. Answers #t when the engine is active, #f when unavailable -- the pure-x writer carries on, with the same output. raw and zlib build it on their own for an input of 32KB or more."
        (returns BOOL "#t when the compiled engine is active"))
      (%jit-try!))))

(doc (provide x/codec/deflate Deflate)
  "DEFLATE streams written in pure x-lang: (Deflate raw s) and (Deflate zlib s) compressed, (Deflate stored s) and (Deflate zlib-stored s) the bytes as they are; each answers (OUT N).")

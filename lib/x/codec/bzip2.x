; bzip2.x -- Bzip2: bzip2 compression in pure x-lang.
;
; bzip2 writes .bz2 files where no libbz2 is present, as gzip writes .gz on
; Deflate.  This is the compressor busybox carries (archival/libarchive/bz/,
; Julian Seward's bzip2 1.0.4 adapted by Denys Vlasenko), and its output is
; byte for byte busybox's: a stream is "BZh" and a block size digit, then
; blocks of up to 100000 bytes a step of the digit, then an end marker and
; the CRC of the whole.  A block is the input run-length coded (runs of four
; to 255 bytes as four bytes and a count), sorted by the Burrows-Wheeler
; transform, move-to-front and zero-run coded, and written under up to six
; Huffman tables, a table chosen for each group of fifty symbols.
;
; The sort is busybox's fallbackSort: a bucket sort refined by doubling
; prefix lengths, each bucket three-way quicksorted.  busybox runs its main
; sort first and this one when the main sort's budget runs out; the two
; order the rotations alike, and rotations they could order apart are
; equal only in a block that repeats a period, where the main sort spends
; its budget and falls back.  So the fallback alone writes busybox's bytes.
;
; Input is a byte region, a start and a length, so a NUL is a byte like any
; other.  A stream can be fed a piece at a time: a block is compressed once
; it is full, and the last piece writes the rest.  The tables shared by the
; steps are words in one region, the sort's arrays words in another, so the
; compiled engine (bzip2-jit.x) works on the same memory as this file.
(module x/codec/bzip2)

(import x/type/vector)
(import x/tool/compiled)

(import x/core/doors int% int& int+ int- int->ptr int/ int< int<< int= int>> int| mem-cmp mem-copy obj-ref obj-set! ptr->int ptr-ref ptr-set! str->ptr str-byte-len str-make type-of)

; The two coordinates the doors module does not carry.  There is no int >
; or >= either: a > b is (int< b a).
(def %mem-set (prim-ref (lit mem) (lit set)))
(def %xor (prim-ref (lit int) (lit ^)))

(def %int-type (type-of 0))

(def %M32 4294967295)

; --- memory ------------------------------------------------------------------

(def %at (fn (_ p off) (int->ptr (int+ (ptr->int p) off))))
(def %wref (fn (_ p i) (ptr-ref p (int<< i 3) 8)))
(def %wset! (fn (_ p i v) (ptr-set! p (int<< i 3) v 8)))
(def %bref (fn (_ p i) (int& (ptr-ref p i 1) 255)))
(def %bset! (fn (_ p i v) (ptr-set! p i v 1)))

; A region of n words, zeroed.
(def %words
  (fn (_ n)
    (def r (str-make (int<< n 3)))
    (%mem-set (str->ptr r) 0 (int<< n 3))
    r))

(def %clear!
  (fn (self p k n)
    (if (int= n 0) () (do (%wset! p k 0) (self p (int+ k 1) (int- n 1))))))

(def %min (fn (_ a b) (if (int< a b) a b)))

; --- the encoder's state -----------------------------------------------------

(def %LEVEL 1)      ; the block size digit
(def %NBMAX 2)      ; bytes a block takes before it is compressed
(def %BLOCK 3)      ; the block's bytes, and their address
(def %BLOCKP 4)
(def %NBLOCK 5)
(def %INCH 6)       ; the run in hand: its byte (256 for none) and length
(def %INRUN 7)
(def %CRC 8)        ; the block's CRC and the stream's
(def %COMBINED 9)
(def %BLOCKNO 10)
(def %TABLES 11)    ; the shared tables, words, and their address
(def %TABP 12)
(def %OUT 13)       ; the output, its address, size and count
(def %OUTP 14)
(def %OUTCAP 15)
(def %OUTCNT 16)
(def %BSBUFF 17)    ; bits not yet a byte, most significant first, and how many
(def %BSLIVE 18)
(def %WORK 19)      ; the sort's arrays, their address, and the entries each holds
(def %WORKP 20)
(def %WORKN 21)
(def %SEL 22)       ; the selectors and their move-to-front values, bytes
(def %SELP 23)
(def %ENGINE 24)    ; (TAKE SORT MTF SELECT WRITE)
(def %NINUSE 25)    ; how many byte values the block uses
(def %NSLOTS 25)

; The shared tables, word offsets: the CRC table, which bytes the block
; uses, each used byte's place among them, the symbols' counts, and six
; tables' code lengths, counts and codes.
(def %CT 0)
(def %INUSE 256)
(def %UNSEQ 512)
(def %MTFFREQ 768)
(def %LENS 1026)
(def %RFREQ 2574)
(def %CODES 4122)
(def %TWORDS 5670)
(def %ASIZE 258)

; The selectors: up to 18002 a block, their move-to-front values after.
(def %SELMTF 18016)
(def %SELBYTES 36032)

(def %t (fn (_ e k) (%wref (obj-ref e %TABP) k)))
(def %t! (fn (_ e k v) (%wset! (obj-ref e %TABP) k v)))

; --- the CRC -----------------------------------------------------------------

; CRC-32 as bzip2 takes it: most significant bit first, polynomial 0x04C11DB7.
(def %crc-entry
  (fn (self c k)
    (if (int= k 0) c
      (self (if (int= (int& c 2147483648) 0)
              (int& (int<< c 1) %M32)
              (%xor (int& (int<< c 1) %M32) 79764919))
            (int- k 1)))))

(def %crc-fill!
  (fn (self p i)
    (if (int= i 256) ()
      (do (%wset! p i (%crc-entry (int<< i 24) 8)) (self p (int+ i 1))))))

(def %crc-byte
  (fn (_ p crc b)
    (%xor (int& (int<< crc 8) %M32) (%wref p (int& (%xor (int>> crc 24) b) 255)))))

(def %crc-run
  (fn (self p crc b k)
    (if (int= k 0) crc (self p (%crc-byte p crc b) b (int- k 1)))))

; --- the output --------------------------------------------------------------

(def %room!
  (fn (_ e n)
    (def need (int+ (obj-ref e %OUTCNT) n))
    (if (int< (obj-ref e %OUTCAP) need) (%grow! e need) ())))

(def %grow!
  (fn (_ e need)
    (def cap ((fn (self c) (if (int< c need) (self (int<< c 1)) c)) (int<< (obj-ref e %OUTCAP) 1)))
    (def r (str-make cap))
    (mem-copy (str->ptr r) (obj-ref e %OUTP) (obj-ref e %OUTCNT))
    (obj-set! e %OUT r)
    (obj-set! e %OUTP (str->ptr r))
    (obj-set! e %OUTCAP cap)))

(def %byte-out!
  (fn (_ e b)
    (%room! e 1)
    (%bset! (obj-ref e %OUTP) (obj-ref e %OUTCNT) b)
    (obj-set! e %OUTCNT (int+ (obj-ref e %OUTCNT) 1))))

; Whole bytes of the bit buffer out until fewer than eight bits are left.
(def %drain!
  (fn (self e)
    (if (int< (obj-ref e %BSLIVE) 8) ()
      (do (%byte-out! e (int>> (obj-ref e %BSBUFF) 24))
          (obj-set! e %BSBUFF (int& (int<< (obj-ref e %BSBUFF) 8) %M32))
          (obj-set! e %BSLIVE (int- (obj-ref e %BSLIVE) 8))
          (self e)))))

; The low n bits of v written, most significant first; n is at most 24.
(def %bits!
  (fn (_ e n v)
    (%drain! e)
    (obj-set! e %BSBUFF (int| (obj-ref e %BSBUFF) (int<< v (int- (int- 32 (obj-ref e %BSLIVE)) n))))
    (obj-set! e %BSLIVE (int+ (obj-ref e %BSLIVE) n))))

(def %u16! (fn (_ e u) (%bits! e 16 u)))
(def %u32! (fn (_ e u) (%bits! e 16 (int>> u 16)) (%bits! e 16 (int& u 65535))))

; The bits left written out, the last byte padded with zeros.
(def %finish-bits!
  (fn (self e)
    (if (int< 0 (obj-ref e %BSLIVE))
      (do (%byte-out! e (int>> (obj-ref e %BSBUFF) 24))
          (obj-set! e %BSBUFF (int& (int<< (obj-ref e %BSBUFF) 8) %M32))
          (obj-set! e %BSLIVE (int- (obj-ref e %BSLIVE) 8))
          (self e))
      (obj-set! e %BSLIVE 0))))

; --- the input: runs coded into the block -------------------------------------

(def %new-block!
  (fn (_ e)
    (obj-set! e %NBLOCK 0)
    (obj-set! e %CRC %M32)
    (%clear! (obj-ref e %TABP) %INUSE 256)
    (obj-set! e %BLOCKNO (int+ (obj-ref e %BLOCKNO) 1))))

(def %fill-bytes!
  (fn (self p at b k)
    (if (int= k 0) () (do (%bset! p at b) (self p (int+ at 1) b (int- k 1))))))

; A run of len copies of ch into the block: up to three as they are, four
; or more as four and a byte counting the rest.
(def %add-pair!
  (fn (_ e ch len)
    (def p (obj-ref e %TABP))
    (obj-set! e %CRC (%crc-run p (obj-ref e %CRC) ch len))
    (%wset! p (int+ %INUSE ch) 1)
    (def b (obj-ref e %BLOCKP))
    (def n (obj-ref e %NBLOCK))
    (if (int< len 4)
      (do (%fill-bytes! b n ch len) (obj-set! e %NBLOCK (int+ n len)))
      (do (%wset! p (int+ %INUSE (int- len 4)) 1)
          (%fill-bytes! b n ch 4)
          (%bset! b (int+ n 4) (int- len 4))
          (obj-set! e %NBLOCK (int+ n 5))))))

(def %add-char!
  (fn (_ e c)
    (def ch (obj-ref e %INCH))
    (def len (obj-ref e %INRUN))
    (if (if (int= c ch) (int< len 255) #f)
      (obj-set! e %INRUN (int+ len 1))
      (do (if (int< ch 256) (%add-pair! e ch len) ())
          (obj-set! e %INCH c)
          (obj-set! e %INRUN 1)))))

; The bytes of p from i to end taken into the block until it is full.
; Answers where it stopped.
(def %take!
  (fn (self e p i end)
    (if (if (int< i end) (int< (obj-ref e %NBLOCK) (obj-ref e %NBMAX)) #f)
      (do (%add-char! e (%bref p i)) (self e p (int+ i 1) end))
      i)))

; The run in hand, if any, into the block.
(def %flush-run!
  (fn (_ e)
    (if (int< (obj-ref e %INCH) 256) (%add-pair! e (obj-ref e %INCH) (obj-ref e %INRUN)) ())
    (obj-set! e %INCH 256)
    (obj-set! e %INRUN 0)))

; --- the sort ----------------------------------------------------------------

; The sort's three arrays, of at least n + 64 entries each: the sorted
; order, each position's bucket, and the bucket heads.
(def %work!
  (fn (_ e n)
    (if (int< (obj-ref e %WORKN) (int+ n 64))
      (do (def w (int+ n 64))
          (obj-set! e %WORK (%words (* 3 w)))
          (obj-set! e %WORKP (str->ptr (obj-ref e %WORK)))
          (obj-set! e %WORKN w))
      ())))

(def %fmap (fn (_ e) (obj-ref e %WORKP)))
(def %eclass (fn (_ e) (%at (obj-ref e %WORKP) (int<< (obj-ref e %WORKN) 3))))
(def %bhtab (fn (_ e) (%at (obj-ref e %WORKP) (int<< (obj-ref e %WORKN) 4))))

(def %swap!
  (fn (_ p i j)
    (def t (%wref p i))
    (%wset! p i (%wref p j))
    (%wset! p j t)))

(def %vswap!
  (fn (self p i j n)
    (if (int< 0 n) (do (%swap! p i j) (self p (int+ i 1) (int+ j 1) (int- n 1))) ())))

; fallbackSimpleSort: insertion sorts by bucket, a stride of four then one.
(def %ins!
  (fn (self fm ec h hi tmp c j)
    (if (if (int< hi j) #f (int< (%wref ec (%wref fm j)) c))
      (do (%wset! fm (int- j h) (%wref fm j)) (self fm ec h hi tmp c (int+ j h)))
      (%wset! fm (int- j h) tmp))))

(def %ins-pass!
  (fn (self fm ec h lo hi i)
    (if (int< i lo) ()
      (do (def tmp (%wref fm i))
          (%ins! fm ec h hi tmp (%wref ec tmp) (int+ i h))
          (self fm ec h lo hi (int- i 1))))))

(def %simple-sort!
  (fn (_ fm ec lo hi)
    (if (int= lo hi) ()
      (do (if (int< 3 (int- hi lo)) (%ins-pass! fm ec 4 lo hi (int- hi 4)) ())
          (%ins-pass! fm ec 1 lo hi (int- hi 1))))))

; fallbackQSort3's partition around med: entries equal to it gathered at
; both ends.  Answers (LTLO UNLO UNHI GTHI).
(def %part-lo
  (fn (self fm ec med ltlo unlo unhi gthi)
    (if (int< unhi unlo) (%part-hi fm ec med ltlo unlo unhi gthi)
      (do (def n (int- (%wref ec (%wref fm unlo)) med))
          (match
            ((int= n 0) (do (%swap! fm unlo ltlo) (self fm ec med (int+ ltlo 1) (int+ unlo 1) unhi gthi)))
            ((int< 0 n) (%part-hi fm ec med ltlo unlo unhi gthi))
            (#t (self fm ec med ltlo (int+ unlo 1) unhi gthi)))))))

(def %part-hi
  (fn (self fm ec med ltlo unlo unhi gthi)
    (if (int< unhi unlo) (list ltlo unlo unhi gthi)
      (do (def n (int- (%wref ec (%wref fm unhi)) med))
          (match
            ((int= n 0) (do (%swap! fm unhi gthi) (self fm ec med ltlo unlo (int- unhi 1) (int- gthi 1))))
            ((int< n 0) (do (%swap! fm unlo unhi) (%part-lo fm ec med ltlo (int+ unlo 1) (int- unhi 1) gthi)))
            (#t (self fm ec med ltlo unlo (int- unhi 1) gthi)))))))

; fallbackQSort3: a stack of (LO . HI) ranges, the pivot chosen by a
; pseudo-random sequence that starts again at each call.
(def %fq-loop!
  (fn (self fm ec stack r)
    (if (null? stack) ()
      (do (def lo (first (first stack)))
          (def hi (rest (first stack)))
          (def st (rest stack))
          (if (int< (int- hi lo) 10)
            (do (%simple-sort! fm ec lo hi) (self fm ec st r))
            (do (def r1 (int& (int+ (* r 7621) 1) 32767))
                (def r3 (int% r1 3))
                (def med (%wref ec (%wref fm (match ((int= r3 0) lo) ((int= r3 1) (int>> (int+ lo hi) 1)) (#t hi)))))
                (def part (%part-lo fm ec med lo lo hi hi))
                (def ltlo (first part))
                (def unlo (first (rest part)))
                (def unhi (first (rest (rest part))))
                (def gthi (first (rest (rest (rest part)))))
                (if (int< gthi ltlo) (self fm ec st r1)
                  (do (def n0 (%min (int- ltlo lo) (int- unlo ltlo)))
                      (%vswap! fm lo (int- unlo n0) n0)
                      (def m0 (%min (int- hi gthi) (int- gthi unhi)))
                      (%vswap! fm unlo (int+ (int- hi m0) 1) m0)
                      (def n1 (int- (int+ lo unlo) (int+ ltlo 1)))
                      (def m1 (int+ (int- hi (int- gthi unhi)) 1))
                      (if (int< (int- hi m1) (int- n1 lo))
                        (self fm ec (pair (pair m1 hi) (pair (pair lo n1) st)) r1)
                        (self fm ec (pair (pair lo n1) (pair (pair m1 hi) st)) r1))))))))))

(def %count-bytes!
  (fn (self b ftab i n)
    (if (int= i n) ()
      (do (def c (int+ (%bref b i) 1))
          (obj-set! ftab c (int+ (obj-ref ftab c) 1))
          (self b ftab (int+ i 1) n)))))

(def %cumulate!
  (fn (self ftab i j)
    (if (int= i 257) ()
      (do (def k (int+ j (obj-ref ftab (int+ i 1))))
          (obj-set! ftab (int+ i 1) k)
          (self ftab (int+ i 1) k)))))

(def %place!
  (fn (self b ftab fm i n)
    (if (int= i n) ()
      (do (def c (int+ (%bref b i) 1))
          (def k (int- (obj-ref ftab c) 1))
          (obj-set! ftab c k)
          (%wset! fm k i)
          (self b ftab fm (int+ i 1) n)))))

(def %heads!
  (fn (self ftab bh i)
    (if (int= i 256) () (do (%wset! bh (obj-ref ftab (int+ i 1)) 1) (self ftab bh (int+ i 1))))))

; Block-end sentinels: alternate heads past the end stop every scan.
(def %sentinels!
  (fn (self bh n i)
    (if (int= i 32) ()
      (do (%wset! bh (int+ n (int<< i 1)) 1)
          (%wset! bh (int+ (int+ n (int<< i 1)) 1) 0)
          (self bh n (int+ i 1))))))

; Each position's bucket for this round: the head of the bucket holding
; the position H on.
(def %classes!
  (fn (self fm ec bh n h i j)
    (if (int= i n) ()
      (do (def j1 (if (int= (%wref bh i) 0) j i))
          (def k (int- (%wref fm i) h))
          (%wset! ec (if (int< k 0) (int+ k n) k) j1)
          (self fm ec bh n h (int+ i 1) j1)))))

(def %skip-heads (fn (self bh k) (if (int= (%wref bh k) 0) k (self bh (int+ k 1)))))
(def %skip-rest (fn (self bh k) (if (int= (%wref bh k) 0) (self bh (int+ k 1)) k)))

; A sorted bucket's heads marked where its entries' classes change.
(def %mark-heads!
  (fn (self fm ec bh i r cc)
    (if (int< r i) ()
      (do (def cc1 (%wref ec (%wref fm i)))
          (if (int= cc cc1) () (%wset! bh i 1))
          (self fm ec bh (int+ i 1) r cc1)))))

; Every bucket of more than one entry sorted by class.  Answers how many
; entries such buckets held.
(def %buckets!
  (fn (self fm ec bh n r notdone)
    (def k (%skip-heads bh (int+ r 1)))
    (def l (int- k 1))
    (if (int< l n)
      (do (def r1 (int- (%skip-rest bh k) 1))
          (if (int< r1 n)
            (if (int< l r1)
              (do (%fq-loop! fm ec (list (pair l r1)) 0)
                  (%mark-heads! fm ec bh l r1 -1)
                  (self fm ec bh n r1 (int+ notdone (int+ (int- r1 l) 1))))
              (self fm ec bh n r1 notdone))
            notdone))
      notdone)))

(def %rounds!
  (fn (self fm ec bh n h)
    (%classes! fm ec bh n h 0 0)
    (def notdone (%buckets! fm ec bh n -1 0))
    (def h2 (int<< h 1))
    (if (if (int< n h2) #t (int= notdone 0)) () (self fm ec bh n h2))))

(def %origin
  (fn (self fm i) (if (int= (%wref fm i) 0) i (self fm (int+ i 1)))))

; fallbackSort: the block's rotations sorted into the work's order.
; Answers the origin, where the unrotated block sorts to.
(def %sort-x
  (fn (_ e)
    (def n (obj-ref e %NBLOCK))
    (%work! e n)
    (def b (obj-ref e %BLOCKP))
    (def fm (%fmap e))
    (def ec (%eclass e))
    (def bh (%bhtab e))
    (def ftab (Vector make 257 0))
    (%count-bytes! b ftab 0 n)
    (%cumulate! ftab 0 0)
    (%place! b ftab fm 0 n)
    (%clear! bh 0 (int+ n 64))
    (%heads! ftab bh 0)
    (%sentinels! bh n 0)
    (%rounds! fm ec bh n 1)
    (%origin fm 0)))

; --- move-to-front and zero runs ----------------------------------------------

(def %maps!
  (fn (self e i cnt)
    (if (int= i 256) cnt
      (if (int= (%t e (int+ %INUSE i)) 0) (self e (int+ i 1) cnt)
        (do (%t! e (int+ %UNSEQ i) cnt) (self e (int+ i 1) (int+ cnt 1)))))))

; The symbol v written at wr and counted.
(def %mtf-out!
  (fn (_ e mv wr v)
    (%wset! mv wr v)
    (%t! e (int+ %MTFFREQ v) (int+ (%t e (int+ %MTFFREQ v)) 1))
    (int+ wr 1)))

; A run of z zeros as RUNA and RUNB symbols, bijective base 2.  Answers wr.
(def %zrun!
  (fn (self e mv wr z)
    (def wr1 (%mtf-out! e mv wr (int& z 1)))
    (def z1 (int- z 2))
    (if (int< z1 0) wr1 (self e mv wr1 (int>> z1 1)))))

; ll moved to the front of yy, the others down one.  Answers its place.
(def %mtf-shift!
  (fn (self yy ll j tmp)
    (if (int= tmp ll)
      (do (obj-set! yy 1 tmp) (int- j 1))
      (do (def next (obj-ref yy (int+ j 1)))
          (obj-set! yy (int+ j 1) tmp)
          (self yy ll (int+ j 1) next)))))

(def %mtf-loop!
  (fn (self e b fm mv yy n i wr zpend)
    (if (int= i n)
      (do (def wr1 (if (int< 0 zpend) (%zrun! e mv wr (int- zpend 1)) wr))
          (%mtf-out! e mv wr1 (int+ (obj-ref e %NINUSE) 1)))
      (do (def j0 (int- (%wref fm i) 1))
          (def j (if (int< j0 0) (int+ j0 n) j0))
          (def ll (%t e (int+ %UNSEQ (%bref b j))))
          (if (int= (obj-ref yy 1) ll)
            (self e b fm mv yy n (int+ i 1) wr (int+ zpend 1))
            (do (def wr1 (if (int< 0 zpend) (%zrun! e mv wr (int- zpend 1)) wr))
                (def tmp (obj-ref yy 2))
                (obj-set! yy 2 (obj-ref yy 1))
                (def k (%mtf-shift! yy ll 2 tmp))
                (self e b fm mv yy n (int+ i 1) (%mtf-out! e mv wr1 (int+ k 1)) 0)))))))

; generateMTFValues: the sorted block's last column as move-to-front
; places, zero runs as RUNA/RUNB, then the end symbol, into the work's
; second array.  Answers the symbol count; the used byte count is kept
; for the end symbol and the tables.
(def %mtf-x
  (fn (_ e)
    (def nuse (%maps! e 0 0))
    (obj-set! e %NINUSE nuse)
    (%clear! (obj-ref e %TABP) %MTFFREQ %ASIZE)
    (def yy (Vector make 256 0))
    ((fn (self i) (if (int= i nuse) () (do (obj-set! yy (int+ i 1) i) (self (int+ i 1))))) 0)
    (%mtf-loop! e (obj-ref e %BLOCKP) (%fmap e) (%eclass e) yy (obj-ref e %NBLOCK) 0 0 0)))

; --- the tables --------------------------------------------------------------

(def %len (fn (_ e t v) (%t e (int+ %LENS (int+ (* t %ASIZE) v)))))
(def %len! (fn (_ e t v x) (%t! e (int+ %LENS (int+ (* t %ASIZE) v)) x)))

; One pass of the selection: each group of fifty symbols given the table
; that codes it in fewest bits (the first, of equals), and its symbols
; counted for that table.  Answers the selector count.
(def %cost
  (fn (self e mv t i ge c)
    (if (int< ge i) c (self e mv t (int+ i 1) ge (int+ c (%len e t (%wref mv i)))))))

(def %best
  (fn (self e mv ngroups gs ge t bt bc)
    (if (int= t ngroups) bt
      (do (def c (%cost e mv t gs ge 0))
          (if (int< c bc) (self e mv ngroups gs ge (int+ t 1) t c) (self e mv ngroups gs ge (int+ t 1) bt bc))))))

(def %tally!
  (fn (self e mv bt i ge)
    (if (int< ge i) ()
      (do (def k (int+ %RFREQ (int+ (* bt %ASIZE) (%wref mv i))))
          (%t! e k (int+ (%t e k) 1))
          (self e mv bt (int+ i 1) ge)))))

(def %select-x
  (fn (_ e nmtf ngroups)
    (def mv (%eclass e))
    (def sp (obj-ref e %SELP))
    ((fn (self gs nsel)
       (if (int< gs nmtf)
         (do (def ge (%min (int+ gs 49) (int- nmtf 1)))
             (def bt (%best e mv ngroups gs ge 1 0 (%cost e mv 0 gs ge 0)))
             (%bset! sp nsel bt)
             (%tally! e mv bt gs ge)
             (self (int+ ge 1) (int+ nsel 1)))
         nsel))
     0 0)))

; Huffman code lengths of at most maxlen bits for freq, as bzip2's
; hbMakeCodeLengths: a heap of weights whose low byte is the subtree's
; depth, the counts halved and tried again while a code is too long.
(def %upheap!
  (fn (_ heap weight z)
    (def tmp (obj-ref heap (int+ z 1)))
    (def zz ((fn (self zz)
               (def up (obj-ref heap (int+ (int>> zz 1) 1)))
               (if (int< (obj-ref weight (int+ tmp 1)) (obj-ref weight (int+ up 1)))
                 (do (obj-set! heap (int+ zz 1) up) (self (int>> zz 1)))
                 zz))
             z))
    (obj-set! heap (int+ zz 1) tmp)))

(def %downheap!
  (fn (_ heap weight nheap)
    (def tmp (obj-ref heap 2))
    (def w (fn (_ k) (obj-ref weight (int+ (obj-ref heap (int+ k 1)) 1))))
    (def zz ((fn (self zz)
               (def yy0 (int<< zz 1))
               (if (int< nheap yy0) zz
                 (do (def yy (if (if (int< yy0 nheap) (int< (w (int+ yy0 1)) (w yy0)) #f) (int+ yy0 1) yy0))
                     (if (int< (obj-ref weight (int+ tmp 1)) (w yy)) zz
                       (do (obj-set! heap (int+ zz 1) (obj-ref heap (int+ yy 1))) (self yy))))))
             1))
    (obj-set! heap (int+ zz 1) tmp)))

(def %pop!
  (fn (_ heap weight nheap)
    (def n1 (obj-ref heap 2))
    (obj-set! heap 2 (obj-ref heap (int+ nheap 1)))
    (%downheap! heap weight (int- nheap 1))
    n1))

(def %add-weights
  (fn (_ a b)
    (def da (int& a 255))
    (def db (int& b 255))
    (int| (int+ (int& a 4294967040) (int& b 4294967040)) (int+ 1 (if (int< da db) db da)))))

(def %depth
  (fn (self parent k j)
    (def p (obj-ref parent (int+ k 1)))
    (if (int< p 0) j (self parent p (int+ j 1)))))

(def %code-lengths!
  (fn (self e t alpha maxlen weight)
    (def heap (Vector make 260 0))
    (def parent (Vector make 516 0))
    (obj-set! parent 1 -2)
    ((fn (self i)
       (unless (int< alpha i)
         (do (obj-set! parent (int+ i 1) -1)
             (obj-set! heap (int+ i 1) i)
             (%upheap! heap weight i)
             (self (int+ i 1)))))
     1)
    ; the tree: two lightest joined until one is left
    ((fn (self nheap nnodes)
       (if (int< 1 nheap)
         (do (def n1 (%pop! heap weight nheap))
             (def n2 (%pop! heap weight (int- nheap 1)))
             (def nn (int+ nnodes 1))
             (obj-set! parent (int+ n1 1) nn)
             (obj-set! parent (int+ n2 1) nn)
             (obj-set! weight (int+ nn 1) (%add-weights (obj-ref weight (int+ n1 1)) (obj-ref weight (int+ n2 1))))
             (obj-set! parent (int+ nn 1) -1)
             (obj-set! heap nheap nn)
             (%upheap! heap weight (int- nheap 1))
             (self (int- nheap 1) nn))
         nnodes))
     alpha alpha)
    (def toolong
      ((fn (self i long)
         (if (int< alpha i) long
           (do (def j (%depth parent i 0))
               (%len! e t (int- i 1) j)
               (self (int+ i 1) (if (int< maxlen j) #t long)))))
       1 #f))
    (when toolong
      ((fn (self i)
         (unless (int< alpha i)
           (do (obj-set! weight (int+ i 1) (int<< (int+ 1 (int>> (int>> (obj-ref weight (int+ i 1)) 8) 1)) 8))
               (self (int+ i 1)))))
       1)
      (self e t alpha maxlen weight))))

(def %make-lengths!
  (fn (_ e t alpha)
    (def weight (Vector make 516 0))
    (def base (int+ %RFREQ (* t %ASIZE)))
    ((fn (self i)
       (unless (int= i alpha)
         (do (def f (%t e (int+ base i)))
             (obj-set! weight (int+ i 2) (int<< (if (int= f 0) 1 f) 8))
             (self (int+ i 1)))))
     0)
    (%code-lengths! e t alpha 17 weight)))

; The tables' first lengths: the symbols cut into ngroups runs of about
; equal counts, each table cheap on its own run.
(def %initial-lengths!
  (fn (self e nmtf ngroups alpha npart remf gs)
    (unless (int= npart 0)
      (do (def tfreq (int/ remf npart))
          (def stop ((fn (self ge af) (if (if (int< af tfreq) (int< ge alpha) #f) (self (int+ ge 1) (int+ af (%t e (int+ %MTFFREQ ge)))) (list ge af))) gs 0))
          (def ge0 (int- (first stop) 1))
          (def af0 (first (rest stop)))
          (def odd (if (if (int< gs ge0) (if (int= npart ngroups) #f (if (int= npart 1) #f (int= (int& (int- ngroups npart) 1) 1))) #f) #t #f))
          (def ge (if odd (int- ge0 1) ge0))
          (def af (if odd (int- af0 (%t e (int+ %MTFFREQ ge0))) af0))
          ((fn (self v)
             (unless (int= v alpha)
               (do (%len! e (int- npart 1) v (if (if (int< v gs) #f (not (int< ge v))) 0 15))
                   (self (int+ v 1)))))
           0)
          (self e nmtf ngroups alpha (int- npart 1) (int- remf af) (int+ ge 1))))))

(def %groups-for
  (fn (_ nmtf)
    (match
      ((int< nmtf 200) 2)
      ((int< nmtf 600) 3)
      ((int< nmtf 1200) 4)
      ((int< nmtf 2400) 5)
      (#t 6))))

; The selectors' move-to-front values.
(def %selector-mtf!
  (fn (_ e nsel ngroups)
    (def sp (obj-ref e %SELP))
    (def pos (Vector make 6 0))
    ((fn (self i) (unless (int= i ngroups) (do (obj-set! pos (int+ i 1) i) (self (int+ i 1))))) 0)
    ((fn (self i)
       (unless (int= i nsel)
         (do (def ll (%bref sp i))
             (def j ((fn (self j tmp)
                       (if (int= ll tmp) j
                         (do (def next (obj-ref pos (int+ j 2)))
                             (obj-set! pos (int+ j 2) tmp)
                             (self (int+ j 1) next))))
                     0 (obj-ref pos 1)))
             (obj-set! pos 1 ll)
             (%bset! sp (int+ %SELMTF i) j)
             (self (int+ i 1)))))
     0)))

; hbAssignCodes: canonical codes, shortest first, in symbol order.
(def %assign-codes!
  (fn (_ e t alpha)
    (def lens ((fn (self i lo hi) (if (int= i alpha) (pair lo hi) (do (def l (%len e t i)) (self (int+ i 1) (%min lo l) (if (int< hi l) l hi))))) 0 32 0))
    ((fn (self n vec)
       (unless (int< (rest lens) n)
         (self (int+ n 1)
               (int<< ((fn (self i vec)
                        (if (int= i alpha) vec
                          (if (int= (%len e t i) n)
                            (do (%t! e (int+ %CODES (int+ (* t %ASIZE) i)) vec) (self (int+ i 1) (int+ vec 1)))
                            (self (int+ i 1) vec))))
                      0 vec)
                     1))))
     (first lens) 0)))

(def %write-map!
  (fn (_ e)
    (def any16 (fn (_ i) ((fn (self j) (if (int= j 16) 0 (if (int= (%t e (int+ %INUSE (int+ (int<< i 4) j))) 0) (self (int+ j 1)) 1))) 0)))
    (def in16 ((fn (self i v) (if (int= i 16) v (self (int+ i 1) (int+ (int<< v 1) (any16 i))))) 0 0))
    (%u16! e in16)
    ((fn (self i)
       (unless (int= i 16)
         (do (unless (int= (any16 i) 0)
               (%u16! e ((fn (self j v) (if (int= j 16) v (self (int+ j 1) (int+ (int<< v 1) (%t e (int+ %INUSE (int+ (int<< i 4) j))))))) 0 0)))
             (self (int+ i 1)))))
     0)))

(def %write-selectors!
  (fn (self e i nsel)
    (unless (int= i nsel)
      (do ((fn (self k) (unless (int= k 0) (do (%bits! e 1 1) (self (int- k 1))))) (%bref (obj-ref e %SELP) (int+ %SELMTF i)))
          (%bits! e 1 0)
          (self e (int+ i 1) nsel)))))

(def %write-lengths!
  (fn (_ e t alpha)
    (%bits! e 5 (%len e t 0))
    ((fn (self i curr)
       (unless (int= i alpha)
         (do (def l (%len e t i))
             (def c ((fn (self c)
                       (match
                         ((int< c l) (do (%bits! e 2 2) (self (int+ c 1))))
                         ((int< l c) (do (%bits! e 2 3) (self (int- c 1))))
                         (#t c)))
                     curr))
             (%bits! e 1 0)
             (self (int+ i 1) c))))
     0 (%len e t 0))))

; The block's symbols, each group under its selector's codes.
(def %write-x
  (fn (_ e nmtf nsel)
    (def mv (%eclass e))
    (def sp (obj-ref e %SELP))
    ((fn (self gs s)
       (when (int< gs nmtf)
         (do (def ge (%min (int+ gs 49) (int- nmtf 1)))
             (def base (* (%bref sp s) %ASIZE))
             ((fn (self i)
                (unless (int< ge i)
                  (do (def v (int+ base (%wref mv i)))
                      (%bits! e (%t e (int+ %LENS v)) (%t e (int+ %CODES v)))
                      (self (int+ i 1)))))
              gs)
             (self (int+ ge 1) (int+ s 1)))))
     0 0)))

; sendMTFValues: the tables chosen, improved four times, and written with
; the selectors and the symbols.
(def %send!
  (fn (_ e nmtf)
    (def engine (obj-ref e %ENGINE))
    (def alpha (int+ (obj-ref e %NINUSE) 2))
    (def ngroups (%groups-for nmtf))
    ((fn (self t) (unless (int= t 6) (do ((fn (self v) (unless (int= v alpha) (do (%len! e t v 15) (self (int+ v 1))))) 0) (self (int+ t 1))))) 0)
    (%initial-lengths! e nmtf ngroups alpha ngroups nmtf 0)
    (def nsel
      ((fn (self iter nsel)
         (if (int= iter 4) nsel
           (do (%clear! (obj-ref e %TABP) %RFREQ (* 6 %ASIZE))
               (def n ((first (rest (rest (rest engine)))) e nmtf ngroups))
               ((fn (self t) (unless (int= t ngroups) (do (%make-lengths! e t alpha) (self (int+ t 1))))) 0)
               (self (int+ iter 1) n))))
       0 0))
    (%selector-mtf! e nsel ngroups)
    ((fn (self t) (unless (int= t ngroups) (do (%assign-codes! e t alpha) (self (int+ t 1))))) 0)
    (%write-map! e)
    (%bits! e 3 ngroups)
    (%bits! e 15 nsel)
    (%write-selectors! e 0 nsel)
    ((fn (self t) (unless (int= t ngroups) (do (%write-lengths! e t alpha) (self (int+ t 1))))) 0)
    ((first (rest (rest (rest (rest engine))))) e nmtf nsel)))

; --- blocks and the stream ----------------------------------------------------

(def %compress-block!
  (fn (_ e last?)
    (def engine (obj-ref e %ENGINE))
    (def n (obj-ref e %NBLOCK))
    (def origin
      (if (int= n 0) 0
        (do (obj-set! e %CRC (%xor (obj-ref e %CRC) %M32))
            (def c (obj-ref e %COMBINED))
            (obj-set! e %COMBINED (%xor (int& (int| (int<< c 1) (int>> c 31)) %M32) (obj-ref e %CRC)))
            ((first (rest engine)) e))))
    (when (int= (obj-ref e %BLOCKNO) 1)
      (%u32! e (int+ 1113221168 (obj-ref e %LEVEL))))
    (unless (int= n 0)
      (%u32! e 826366246)
      (%u16! e 21337)
      (%u32! e (obj-ref e %CRC))
      (%bits! e 1 0)
      (%bits! e 24 origin)
      (%send! e ((first (rest (rest engine))) e)))
    (when last?
      (%u32! e 393364792)
      (%u16! e 20624)
      (%u32! e (obj-ref e %COMBINED))
      (%finish-bits! e))))

(def %encoder
  (fn (_ level engine)
    (def e (Vector make %NSLOTS 0))
    (def n (* 100000 level))
    (obj-set! e %LEVEL level)
    (obj-set! e %NBMAX (int- n 19))
    (obj-set! e %BLOCK (str-make (int+ n 64)))
    (obj-set! e %BLOCKP (str->ptr (obj-ref e %BLOCK)))
    (obj-set! e %TABLES (%words %TWORDS))
    (obj-set! e %TABP (str->ptr (obj-ref e %TABLES)))
    (%crc-fill! (obj-ref e %TABP) 0)
    (obj-set! e %OUT (str-make 4096))
    (obj-set! e %OUTP (str->ptr (obj-ref e %OUT)))
    (obj-set! e %OUTCAP 4096)
    (obj-set! e %WORK ())
    (obj-set! e %SEL (str-make %SELBYTES))
    (obj-set! e %SELP (str->ptr (obj-ref e %SEL)))
    (obj-set! e %INCH 256)
    (obj-set! e %ENGINE engine)
    (%new-block! e)
    e))

; n more bytes of buf from start compressed: each block that fills, and with
; final? the rest and the end.  Answers (OUT N), the whole bytes made.
(def %feed
  (fn (_ e buf start n final?)
    (obj-set! e %OUTCNT 0)
    (def p (%at (str->ptr buf) start))
    ((fn (self i)
       (def j ((first (obj-ref e %ENGINE)) e p i n))
       (match
         ((if final? (int= j n) #f)
           (do (%flush-run! e) (%compress-block! e #t)))
         ((int< (obj-ref e %NBLOCK) (obj-ref e %NBMAX)) ())
         (#t (do (%compress-block! e #f) (%new-block! e) (self j)))))
     0)
    (def out (%region-of (obj-ref e %OUTCNT)))
    (mem-copy (str->ptr out) (obj-ref e %OUTP) (obj-ref e %OUTCNT))
    (list out (obj-ref e %OUTCNT))))

(def %pure (list %take! %sort-x %mtf-x %select-x %write-x))

; --- The compiled engine (JIT), adopted only when it proves out --------------
;
; x/codec/bzip2-jit compiles the five loops that run once a byte or a
; symbol.  As Deflate's engine is, it is an entry of Compiled's made on
; demand, built for an input of %jit-threshold bytes or more, for a stream,
; or on (Bzip2 jit!), and adopted only after the streams it writes for the
; inputs below are byte for byte this file's.  The entry's value is the list
; (TAKE SORT MTF SELECT WRITE): this file's five, or the engine's.

; Text with every table count's boundary near, a period (the sort's equal
; rotations), and runs either side of four and of 255 bytes.
(def %check-inputs
  (fn (_)
    (def rep (fn (self s k acc) (if (int= k 0) acc (self s (int- k 1) (Str8 append acc s)))))
    (list (rep "the quick brown fox jumps over the lazy dog, " 7 "")
          (rep "abcab" 40 "")
          (Str8 append (rep "x" 300 "") "yyyy" (rep "z" 255 "") "zzzzq" (rep "pq" 30 "")))))

(def %agrees?
  (fn (_ engine)
    (List all?
      (fn (_ s)
        (def n (str-byte-len s))
        (def want (%feed (%encoder 9 %pure) s 0 n #t))
        (def got (%feed (%encoder 9 engine) s 0 n #t))
        (and (= (first (rest want)) (first (rest got)))
             (= 0 (mem-cmp (str->ptr (first want)) (str->ptr (first got)) (first (rest want))))))
      (%check-inputs))))

(def %entry ())
(def %jit-threshold 4096)

(def %jit-try!
  (fn (_)
    (when (null? %entry)
      (set! %entry
        (Compiled make-on-demand (lit bzip2) %pure
          (fn (_)
            (import x/codec/bzip2-jit)
            ((prim-ref (lit bzip2) (lit jit-make))
             (list (pair (lit blockp) %BLOCKP) (pair (lit nblock) %NBLOCK) (pair (lit nbmax) %NBMAX)
                   (pair (lit inch) %INCH) (pair (lit inrun) %INRUN) (pair (lit crc) %CRC)
                   (pair (lit tabp) %TABP) (pair (lit workp) %WORKP) (pair (lit workn) %WORKN)
                   (pair (lit outp) %OUTP) (pair (lit outcnt) %OUTCNT)
                   (pair (lit bsbuff) %BSBUFF) (pair (lit bslive) %BSLIVE) (pair (lit selp) %SELP)
                   (pair (lit ninuse) %NINUSE))
             %work! %room! %agrees?))
          (fn (_ _) ()))))
    ((fn (_ entry)
       (when (eq? (entry state) (lit interpreted)) (entry compile!))
       (eq? (entry state) (lit compiled)))
     %entry)))

; (TAKE SORT MTF SELECT WRITE) for n bytes of input: the engine's when it
; is built, or when n is past the bar and a build succeeds; else this file's.
(def %engine-for
  (fn (_ n)
    (do (when (and (>= n %jit-threshold)
                   ((fn (_ entry) (if (null? entry) #t (eq? (entry state) (lit interpreted)))) %entry))
          (%jit-try!))
        ((fn (_ entry)
           (if (if (null? entry) #f (eq? (entry state) (lit compiled)))
             (entry compiled)
             %pure))
         %entry))))

; A region of n bytes, never of none: a (str make) of 0 is no buffer.
(def %region-of (fn (_ n) (str-make (if (int< n 1) 1 n))))

(def %span
  (fn (_ s span)
    (match
      ((null? span) (list 0 (str-byte-len s)))
      ((null? (rest span)) (list (first span) (int- (str-byte-len s) (first span))))
      (#t (list (first span) (first (rest span)))))))

(def %level-ok
  (fn (_ level)
    (if (if (eq? (type-of level) %int-type) (if (int< level 1) #f (int< level 10)) #f) level
      (Err raise (lit value) "Bzip2: the level is not 1 to 9" (list (pair (lit bzip2) (lit level)))))))

(def-class Bzip2 ()
  (doc "bzip2 compression in pure x-lang, byte for byte as busybox's bzip2 writes it. (Bzip2 compress s level) answers (OUT N); a stream can also be written a piece at a time: stream, feed.")
  (static
    (method compress (self (param s STRING "The bytes to compress")
                           (param level INTEGER "The block size digit, 1 to 9: blocks of 100000 bytes a step")
                           . (param span LIST "START, then LENGTH: where the bytes start in s and how many; default all of s"))
      (doc "One bzip2 stream: \"BZh\" and the level, the blocks, the end marker and the stream's CRC, as busybox's bzip2 -LEVEL writes it. Give LENGTH for binary input: s's own length is measured to its first NUL."
        (returns LIST "(OUT N): a region and how many of its bytes the stream is")
        (example "(first (rest (Bzip2 compress \"\" 9)))" "14"))
      (def sp (%span s span))
      (%feed (%encoder (%level-ok level) (%engine-for (first (rest sp))))
             s (first sp) (first (rest sp)) #t))
    (method stream (self (param level INTEGER "The block size digit, 1 to 9"))
      (doc "A bzip2 stream written a piece at a time with (Bzip2 feed): what bzip2 wants of a file it must not read whole. The output is the bytes compress writes for the pieces joined."
        (returns OBJECT "The stream"))
      ; A piece at a time says nothing about the whole, so a stream asks for
      ; the engine outright rather than by the first piece's size.
      (%encoder (%level-ok level) (%engine-for %jit-threshold)))
    (method feed (self (param z OBJECT "A (Bzip2 stream)")
                       (param s STRING "Bytes holding the next piece")
                       (param start INTEGER "Where the piece starts in s")
                       (param n INTEGER "How many bytes it is")
                       (param final BOOL "Is this the last piece? The last block and the end marker are then written"))
      (doc "Compress n more bytes into the stream. Answers the whole bytes of stream the blocks they fill make; a block is written once it is full, the bits short of a byte wait, and the last piece (final) writes the rest."
        (returns LIST "(OUT N): a region and how many of its bytes the stream gained"))
      (%feed z s start n final))
    (method jit! (self)
      (doc "Build and adopt the compiled run, sort, move-to-front, selection and writing loops (JIT; ARM64 and x86-64 backends) now, if they write the check streams exactly as the pure-x ones do. Idempotent. Answers #t when the engine is active, #f when unavailable -- the pure-x compressor carries on, with the same bytes. compress builds it on its own for an input of 4KB or more, and a stream always."
        (returns BOOL "#t when the compiled engine is active"))
      (%jit-try!))))

(doc (provide x/codec/bzip2 Bzip2)
  "bzip2 compression in pure x-lang, busybox's compressor: (Bzip2 compress s level) answers (OUT N); stream and feed write one a piece at a time.")

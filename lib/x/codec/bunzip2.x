; bunzip2.x -- Bunzip2: bzip2 decompression in pure x-lang.
;
; bunzip2, bzcat and tar's j read .bz2 files where no libbz2 is present, as
; gunzip reads .gz on Inflate.  This is the decoder busybox carries
; (archival/libarchive/decompress_bunzip2.c, after Rob Landley and Manuel
; Novoa III): a stream is "BZh" and a block size digit, then blocks, each
; a 48-bit magic, its CRC, the Burrows-Wheeler origin, the byte map, the
; Huffman group selectors and tables and the coded symbols, then an end
; marker and the CRC of the whole.  A block decodes to the move-to-front
; and run-length coded symbols of its sorted text; the inverse transform
; walks them back to the bytes, undoing the four-byte run coding as it
; goes.  The blocks are not byte-aligned: the bits read ahead carry over.
;
; Input is a byte region, a start and a length, so a NUL is a byte like any
; other.  A stream can also be fed a piece at a time, a block decoded once
; the input holds it whole: see the stream below.  A malformed stream
; raises a label 'value whose data names what was wrong, (bunzip . KIND),
; KIND one of 'magic ("BZ" missing), 'header (no "h" and size digit),
; 'data, 'obsolete (a randomised block) or 'crc; input that ends inside the
; stream adds (short . #t).
(module x/codec/bunzip2)

(import x/type/vector)
(import x/tool/compiled)

(import x/core/doors int& int+ int- int->ptr int< int<< int= int>> int| mem-cmp mem-copy obj-ref obj-set! ptr->int ptr-ref ptr-set! str->ptr str-byte-len str-make)

; The int doors: the generic comparisons and bit operations dispatch
; through the tower.  There is no int > or >=: a > b is (int< b a).
(def %xor (prim-ref (lit int) (lit ^)))

(def %M32 4294967295)
(def %M40 1099511627775)

; A decoder's state, in the slots of one vector (slot k holds field k): the
; input's address, its length and how much of it is read; the bits read
; ahead and how many; the block buffer, its size in entries and how many it
; holds; the output region, its address, its size and how much is written.
(def %IN 1)
(def %INLEN 2)
(def %INCNT 3)
(def %BITBUF 4)
(def %BITCNT 5)
(def %DBUF 6)
(def %DBUFP 7)
(def %DBUFSIZE 8)
(def %OUT 9)
(def %OUTP 10)
(def %OUTCAP 11)
(def %OUTCNT 12)
(def %ENGINE 13)
(def %NSLOTS 13)

(def %fail
  (fn (_ kind what)
    (Err raise (lit value) (Str8 append "Bunzip2: " what) (list (pair (lit bunzip) kind)))))

; The input used up before the stream is: data (short . #t) as well, so a
; stream fed a piece at a time knows to wait for the next
(def %short
  (fn (_)
    (Err raise (lit value) "Bunzip2: the input ends inside the stream"
      (list (pair (lit bunzip) (lit data)) (pair (lit short) #t)))))

(def %short?
  (fn (_ e)
    (if (Err err? e)
      (if (eq? (Err label e) (lit value))
        ((fn (self d) (if (null? d) #f (if (eq? (first (first d)) (lit short)) #t (self (rest d))))) (e data))
        #f)
      #f)))

(def %at (fn (_ p off) (int->ptr (int+ (ptr->int p) off))))

; The paths below run once a bit, a symbol or a byte, so they are written
; in primitives alone, as inflate.x's are: def in a body, if, do and
; self-calls of top-level functions.

; Bytes read ahead until the buffer holds `need` bits, most significant
; first.  The buffer keeps 40 bits: those in hand and those just read, so a
; look ahead can be taken back.
(def %fill!
  (fn (self s need)
    (def cnt (obj-ref s %BITCNT))
    (if (int< cnt need)
      (do (def i (obj-ref s %INCNT))
          (if (int= i (obj-ref s %INLEN)) (%short) ())
          (obj-set! s %INCNT (int+ i 1))
          (obj-set! s %BITBUF (int& (int| (int<< (obj-ref s %BITBUF) 8) (int& (ptr-ref (obj-ref s %IN) i 1) 255)) %M40))
          (obj-set! s %BITCNT (int+ cnt 8))
          (self s need))
      ())))

; The next `need` bits, looked at, not read.
(def %peek
  (fn (_ s need)
    (%fill! s need)
    (int& (int>> (obj-ref s %BITBUF) (int- (obj-ref s %BITCNT) need)) (int- (int<< 1 need) 1))))

(def %skip! (fn (_ s n) (obj-set! s %BITCNT (int- (obj-ref s %BITCNT) n))))

(def %bits
  (fn (_ s need)
    (def v (%peek s need))
    (%skip! s need)
    v))

; The whole bytes read ahead given back to the input: the count of input
; used steps back over them.
(def %unread-bytes!
  (fn (_ s)
    (def back (int>> (obj-ref s %BITCNT) 3))
    (if (int< 0 back)
      (do (obj-set! s %INCNT (int- (obj-ref s %INCNT) back))
          (obj-set! s %BITCNT (int- (obj-ref s %BITCNT) (int<< back 3))))
      ())))

; --- the CRC ------------------------------------------------------------------

; bzip2's CRC-32: polynomial 0x04C11DB7, most significant bit first.  Slot
; i+1 holds the table entry for byte i.
(def %crc-entry
  (fn (self c k)
    (if (int= k 0) c
      (self (if (int= (int& c 2147483648) 0)
              (int& (int<< c 1) %M32)
              (%xor (int& (int<< c 1) %M32) 79764919))
            (int- k 1)))))

(def %crc-table (Vector make 256 0))
((fn (self i)
   (if (int< i 256)
     (do (obj-set! %crc-table (int+ i 1) (%crc-entry (int<< i 24) 8))
         (self (int+ i 1)))
     ()))
 0)

(def %crc-byte
  (fn (_ crc b)
    (%xor (int& (int<< crc 8) %M32) (obj-ref %crc-table (int+ (int& (%xor (int>> crc 24) b) 255) 1)))))

; --- the block header ---------------------------------------------------------

; The byte map: sixteen ranges of sixteen bytes, a bit for each range used
; and then a bit for each of its bytes.  Fills sym->byte and answers how many
; bytes the block uses.
(def %byte-map!
  (fn (_ s sym->byte)
    (def ranges (%bits s 16))
    (%map-ranges! s sym->byte ranges 0 0)))

(def %map-ranges!
  (fn (self s sym->byte ranges r total)
    (if (int= r 16) total
      (if (int= (int& ranges (int>> 32768 r)) 0)
        (self s sym->byte ranges (int+ r 1) total)
        (self s sym->byte ranges (int+ r 1) (%map-bytes! s sym->byte (%bits s 16) (int<< r 4) 0 total))))))

(def %map-bytes!
  (fn (self s sym->byte inner base k total)
    (if (int= k 16) total
      (if (int= (int& inner (int>> 32768 k)) 0)
        (self s sym->byte inner base (int+ k 1) total)
        (do (obj-set! sym->byte (int+ total 1) (int+ base k))
            (self s sym->byte inner base (int+ k 1) (int+ total 1)))))))

; The selectors: nsel unary-coded move-to-front positions over the groups,
; each the group the next fifty symbols are coded with.
(def %selectors!
  (fn (self s sel mtf groups i nsel)
    (if (int= i nsel) ()
      (do (def n (%unary s groups 0))
          (def g (obj-ref mtf (int+ n 1)))
          (%mtf-shift! mtf n)
          (obj-set! mtf 1 g)
          (ptr-set! sel i g 1)
          (self s sel mtf groups (int+ i 1) nsel)))))

(def %unary
  (fn (self s groups n)
    (if (int= (%bits s 1) 0) n
      (if (int< n (int- groups 1)) (self s groups (int+ n 1))
        (%fail (lit data) "a selector past the groups")))))

; Slot i+1 of v holds i, from i below n.
(def %identity!
  (fn (self v i n)
    (if (int< i n) (do (obj-set! v (int+ i 1) i) (self v (int+ i 1) n)) ())))

; Slots n down to 1 of mtf each moved up one.
(def %mtf-shift!
  (fn (self mtf n)
    (if (int= n 0) ()
      (do (obj-set! mtf (int+ n 1) (obj-ref mtf n))
          (self mtf (int- n 1))))))

; A group's code lengths: the first in five bits, each next one a run of
; +1 and -1 steps from the last, ended by a 0 bit.  Slot i+1 of lens holds
; symbol i's.
(def %lengths!
  (fn (self s lens i count len)
    (if (int= i count) ()
      (do (def l (%step-length s len))
          (obj-set! lens (int+ i 1) l)
          (self s lens (int+ i 1) count l)))))

(def %step-length
  (fn (self s len)
    (if (if (int< len 1) #t (int< 20 len)) (%fail (lit data) "a code length out of range") ())
    (def two (%peek s 2))
    (if (int< two 2)
      (do (%skip! s 1) len)
      (do (%skip! s 2) (self s (if (int= two 3) (int- len 1) (int+ len 1)))))))

(def %min-max
  (fn (self lens i count lo hi)
    (if (int= i count) (pair lo hi)
      (do (def l (obj-ref lens (int+ i 1)))
          (self lens (int+ i 1) count (if (int< l lo) l lo) (if (int< hi l) l hi))))))

; A group's decoding tables, as busybox lays them out: permute lists the
; symbols by code length, limit[len] is the largest code of len bits read
; as maxlen bits with the trailing ones set, base[len] what to take from a
; len-bit code to index permute.  Slot len+1 of limit and base; slot k+1 of
; permute.  Answers (MINLEN MAXLEN LIMIT BASE PERMUTE).
(def %group-table
  (fn (_ lens count)
    (def mm (%min-max lens 1 count (obj-ref lens 1) (obj-ref lens 1)))
    (def lo (first mm))
    (def hi (rest mm))
    (def permute (Vector make 258 0))
    (def limit (Vector make 23 0))
    (def base (Vector make 23 0))
    (def temp (Vector make 23 0))
    (%permute! lens count permute lo hi 0)
    (%count-lengths! lens temp 0 count)
    (def pp (%limits! limit base temp lo hi 0 0))
    (obj-set! limit (int+ hi 1) (int- (int+ pp (obj-ref temp (int+ hi 1))) 1))
    (obj-set! limit (int+ hi 2) 2147483647)
    (obj-set! base (int+ lo 1) 0)
    (list lo hi limit base permute)))

(def %permute!
  (fn (self lens count permute len hi pp)
    (if (int< hi len) ()
      (self lens count permute (int+ len 1) hi (%permute-len! lens count permute len 0 pp)))))

(def %permute-len!
  (fn (self lens count permute len k pp)
    (if (int= k count) pp
      (if (int= (obj-ref lens (int+ k 1)) len)
        (do (obj-set! permute (int+ pp 1) k) (self lens count permute len (int+ k 1) (int+ pp 1)))
        (self lens count permute len (int+ k 1) pp)))))

(def %count-lengths!
  (fn (self lens temp i count)
    (if (int= i count) ()
      (do (def l (int+ (obj-ref lens (int+ i 1)) 1))
          (obj-set! temp l (int+ (obj-ref temp l) 1))
          (self lens temp (int+ i 1) count)))))

; limit[i] and base[i+1] for i from lo below hi; pp and t carried, pp
; answered.
(def %limits!
  (fn (self limit base temp i hi pp t)
    (if (int< i hi)
      (do (def ti (obj-ref temp (int+ i 1)))
          (def pp2 (int+ pp ti))
          (obj-set! limit (int+ i 1) (int- (int<< pp2 (int- hi i)) 1))
          (def pp3 (int<< pp2 1))
          (def t2 (int+ t ti))
          (obj-set! base (int+ i 2) (int- pp3 t2))
          (self limit base temp (int+ i 1) hi pp3 t2))
      pp)))

; --- the symbols --------------------------------------------------------------

; The next symbol in group g: maxlen bits looked at, the code's own length
; found against limit, the rest given back.
(def %symbol
  (fn (_ s g)
    (def lo (first g))
    (def hi (first (rest g)))
    (def limit (first (rest (rest g))))
    (def v (%peek s hi))
    (def len (%code-length limit v lo))
    (def back (int- hi len))
    (if (int< back 0) (%fail (lit data) "a code no table holds") ())
    (%skip! s len)
    (def k (int- (int>> v back) (obj-ref (first (rest (rest (rest g)))) (int+ len 1))))
    (if (if (int< k 0) #t (int< 257 k)) (%fail (lit data) "a code no table holds") ())
    (obj-ref (first (rest (rest (rest (rest g))))) (int+ k 1))))

(def %code-length
  (fn (self limit v len)
    (if (int< (obj-ref limit (int+ len 1)) v) (self limit v (int+ len 1)) len)))

; The block's symbols decoded into the block buffer: runs of RUNA and RUNB
; spell a repeat count of the byte at the front of the move-to-front list,
; any other symbol below the end one brings the byte at its position to the
; front.  Every byte counted in counts.  Answers how many entries.
(def %decode-symbols!
  (fn (_ s groups ngroups sel nsel sym->byte total counts)
    (def mtf (Vector make 256 0))
    (%identity! mtf 0 256)
    (%symbols! s groups ngroups sel nsel sym->byte (int+ total 1) counts mtf 0 0 0 0 0 0)))

; sn: the next selector; left: symbols left in the group in hand; g: that
; group; run: the run's place value, 0 outside a run; cnt: the run's count;
; n: entries written.
(def %symbols!
  (fn (self s groups ngroups sel nsel sym->byte eob counts mtf sn left g run cnt n)
    (if (int= left 0)
      (do (if (int< sn nsel) () (%fail (lit data) "more symbols than selectors"))
          (def gi (int& (ptr-ref sel sn 1) 255))
          (if (int< gi ngroups) () (%fail (lit data) "a selector past the groups"))
          (self s groups ngroups sel nsel sym->byte eob counts mtf (int+ sn 1) 50 (obj-ref groups (int+ gi 1)) run cnt n))
      (do (def sym (%symbol s g))
          (if (int< sym 2)
            ; RUNA adds the place value, RUNB twice it
            (do (def place (if (int= run 0) 1 run))
                (def cnt2 (int+ (if (int= run 0) 0 cnt) (int<< place sym)))
                (def size (obj-ref s %DBUFSIZE))
                (self s groups ngroups sel nsel sym->byte eob counts mtf sn (int- left 1) g
                  (if (int< place size) (int<< place 1) place) cnt2 n))
            (do (def n2 (if (int= run 0) n (%run-out! s sym->byte counts mtf cnt n)))
                (if (int< sym eob)
                  (do (if (int< n2 (obj-ref s %DBUFSIZE)) () (%fail (lit data) "a block longer than its size"))
                      (def i (int- sym 1))
                      (def u (obj-ref mtf (int+ i 1)))
                      (%mtf-shift! mtf i)
                      (obj-set! mtf 1 u)
                      (def b (obj-ref sym->byte (int+ u 1)))
                      (obj-set! counts (int+ b 1) (int+ (obj-ref counts (int+ b 1)) 1))
                      (ptr-set! (obj-ref s %DBUFP) (int<< n2 3) b 8)
                      (self s groups ngroups sel nsel sym->byte eob counts mtf sn (int- left 1) g 0 0 (int+ n2 1)))
                  n2)))))))

; A run's cnt copies of the front byte written from n; the new count.
(def %run-out!
  (fn (_ s sym->byte counts mtf cnt n)
    (def end (int+ n cnt))
    (if (int< (obj-ref s %DBUFSIZE) end) (%fail (lit data) "a run past the block's size") ())
    (def b (obj-ref sym->byte (int+ (obj-ref mtf 1) 1)))
    (obj-set! counts (int+ b 1) (int+ (obj-ref counts (int+ b 1)) cnt))
    (%fill-run! (obj-ref s %DBUFP) n end b)
    end))

(def %fill-run!
  (fn (self p i end b)
    (if (int< i end)
      (do (ptr-set! p (int<< i 3) b 8) (self p (int+ i 1) end b))
      ())))

; --- the inverse transform ----------------------------------------------------

; counts made cumulative, then each entry's successor linked: entry i's
; byte, sorted, sits at counts[byte], which gets i in its upper bits.
(def %link!
  (fn (_ s counts n)
    (%cumulative! counts 0 0)
    (%link-entries! (obj-ref s %DBUFP) counts 0 n)))

; Each count from i on replaced by the sum of those before it, j so far.
(def %cumulative!
  (fn (self counts i j)
    (if (int< i 256)
      (do (def c (obj-ref counts (int+ i 1)))
          (obj-set! counts (int+ i 1) j)
          (self counts (int+ i 1) (int+ j c)))
      ())))

(def %link-entries!
  (fn (self p counts i n)
    (if (int< i n)
      (do (def b (int& (ptr-ref p (int<< i 3) 8) 255))
          (def at (obj-ref counts (int+ b 1)))
          (ptr-set! p (int<< at 3) (int| (ptr-ref p (int<< at 3) 8) (int<< i 8)) 8)
          (obj-set! counts (int+ b 1) (int+ at 1))
          (self p counts (int+ i 1) n))
      ())))

; Room for n more output bytes, the region doubled until it fits.
(def %room!
  (fn (_ s n)
    (def need (int+ (obj-ref s %OUTCNT) n))
    (if (int< (obj-ref s %OUTCAP) need) (%grow! s need (int<< (obj-ref s %OUTCAP) 1)) ())))

(def %grow!
  (fn (self s need ncap)
    (if (int< ncap need) (self s need (int<< ncap 1))
      (do (def r (str-make ncap))
          (def cnt (obj-ref s %OUTCNT))
          (if (int< 0 cnt) (mem-copy (str->ptr r) (obj-ref s %OUTP) cnt) ())
          (obj-set! s %OUT r)
          (obj-set! s %OUTP (str->ptr r))
          (obj-set! s %OUTCAP ncap)))))

; copies+1 bytes b written; the CRC over them answered.
(def %emit!
  (fn (self s b copies crc)
    (def cnt (obj-ref s %OUTCNT))
    (ptr-set! (obj-ref s %OUTP) cnt b 1)
    (obj-set! s %OUTCNT (int+ cnt 1))
    (if (int= copies 0) (%crc-byte crc b)
      (self s b (int- copies 1) (%crc-byte crc b)))))

; read_bunzip's walk: left entries to follow from pos, the byte in hand
; and the one before it, and the countdown to a run's count byte -- after
; four alike, the next byte is how many more.  Answers the block's CRC.
(def %walk!
  (fn (self s p pos cur left countdown crc)
    (if (int= left 0) (%xor crc %M32)
      (do (def e (ptr-ref p (int<< pos 3) 8))
          (def next (int& e 255))
          (def npos (int>> e 8))
          (def cd (int- countdown 1))
          (if (int= cd 0)
            ; a run's count: next more copies of cur
            (if (int= next 0)
              (self s p npos cur (int- left 1) 5 crc)
              (do (%room! s next)
                  (self s p npos cur (int- left 1) 5 (%emit! s cur (int- next 1) crc))))
            (do (%room! s 1)
                (self s p npos next (int- left 1) (if (int= next cur) cd 4) (%emit! s next 0 crc))))))))

; --- a block ------------------------------------------------------------------

; One block, its magic already read and found a block's: decoded and
; written to the output.  Answers its CRC, which the caller checks against
; the stored one.
(def %block!
  (fn (_ s)
    (if (int= (%bits s 1) 1) (%fail (lit obsolete) "a randomised block") ())
    (def origin (%bits s 24))
    (if (int< (obj-ref s %DBUFSIZE) origin) (%fail (lit data) "an origin past the block's size") ())
    (def sym->byte (Vector make 256 0))
    (def total (%byte-map! s sym->byte))
    (def ngroups (%bits s 3))
    (if (if (int< ngroups 2) #t (int< 6 ngroups)) (%fail (lit data) "a group count out of range") ())
    (def nsel (%bits s 15))
    (if (int= nsel 0) (%fail (lit data) "no selectors") ())
    (def sel (str-make nsel))
    (def mtf (Vector make 6 0))
    (%identity! mtf 0 6)
    (%selectors! s (str->ptr sel) mtf ngroups 0 nsel)
    (def count (int+ total 2))
    (def groups (Vector make ngroups 0))
    (%groups! s groups 0 ngroups count)
    (def counts (Vector make 256 0))
    (def engine (obj-ref s %ENGINE))
    (def n ((first engine) s groups ngroups (str->ptr sel) nsel sym->byte total counts))
    ((first (rest engine)) s counts n)
    (if (int= n 0) 0
      (do (if (int< origin n) () (%fail (lit data) "an origin past the block"))
          (def e (ptr-ref (obj-ref s %DBUFP) (int<< origin 3) 8))
          ((first (rest (rest engine))) s (int>> e 8) (int& e 255) n)))))

; The walk over a whole block: n entries from pos, cur in hand.
(def %walk-block!
  (fn (_ s pos cur n) (%walk! s (obj-ref s %DBUFP) pos cur n 5 %M32)))

(def %groups!
  (fn (self s groups j ngroups count)
    (if (int= j ngroups) ()
      (do (def lens (Vector make 258 0))
          (%lengths! s lens 0 count (%bits s 5))
          (obj-set! groups (int+ j 1) (%group-table lens count))
          (self s groups (int+ j 1) ngroups count)))))

; --- a stream -----------------------------------------------------------------

; A decoder over the bytes of buf from start, n of them, its loops
; the engine's three, (SYMBOLS LINK WALK).
(def %decoder
  (fn (_ buf start n engine)
    (def s (Vector make %NSLOTS 0))
    (obj-set! s %ENGINE engine)
    (obj-set! s %IN (%at (str->ptr buf) start))
    (obj-set! s %INLEN n)
    (obj-set! s %OUT (str-make 4096))
    (obj-set! s %OUTP (str->ptr (obj-ref s %OUT)))
    (obj-set! s %OUTCAP 4096)
    s))

; "BZh" and the size digit: the block buffer made for 100000 entries a
; step of the digit.
(def %header!
  (fn (_ s)
    (if (int= (%bits s 16) 16986) () (%fail (lit magic) "no BZ magic"))
    (def h (%bits s 16))
    (def k (int- h 26672))
    (if (if (int< k 1) #t (int< 9 k)) (%fail (lit header) "no block size header") ())
    (def size (* 100000 k))
    (obj-set! s %DBUF (str-make (int<< size 3)))
    (obj-set! s %DBUFP (str->ptr (obj-ref s %DBUF)))
    (obj-set! s %DBUFSIZE size)))

; The next block or the end: a block decoded and its CRC folded into
; combined, answered; or, at the end marker, (end . STORED-CRC).  A block
; whose CRC is not the stored one answers (bad . CRC).
(def %next!
  (fn (_ s combined)
    (def i (%bits s 24))
    (def j (%bits s 24))
    (def stored (%bits s 32))
    (match
      ((if (int= i 1536581) (int= j 3690640) #f) (pair (lit end) stored))
      ((if (int= i 3227993) (int= j 2511705) #f)
        (do (def crc (%block! s))
            (if (int= crc stored)
              (%xor (int& (int| (int<< combined 1) (int>> combined 31)) %M32) crc)
              (pair (lit bad) crc))))
      (#t (%fail (lit data) "no block magic")))))

; --- whole input --------------------------------------------------------------

(def %decode-all
  (fn (_ buf start n engine)
    (def s (%decoder buf start n engine))
    (%header! s)
    (def end (%blocks! s 0))
    (if (pair? end) (%fail (lit crc) "a block's CRC is wrong") ())
    (%unread-bytes! s)
    (list (obj-ref s %OUT) (obj-ref s %OUTCNT) (obj-ref s %INCNT))))

; Blocks to the end marker: the combined CRC checked there.
(def %blocks!
  (fn (self s combined)
    (def r (%next! s combined))
    (match
      ((not (pair? r)) (self s r))
      ((eq? (first r) (lit bad)) r)
      ((int= (rest r) combined) combined)
      (#t (%fail (lit crc) "the stream's CRC is wrong")))))

; --- a stream fed a piece at a time ------------------------------------------

; The stream's state: the input held, its capacity and count, the count it
; had at the last attempt that ran out, the bits carried from the block
; before, the decoder once the header is read, the combined CRC, and
; whether the end is reached and whether every CRC held.
(def %ZIN 1)
(def %ZINCAP 2)
(def %ZINCNT 3)
(def %ZTRIED 4)
(def %ZBITBUF 5)
(def %ZBITCNT 6)
(def %ZDEC 7)
(def %ZCRC 8)
(def %ZDONE 9)
(def %ZOK 10)

(def %stream-new
  (fn (_)
    (def z (Vector make 10 0))
    (obj-set! z %ZIN (str-make 4096))
    (obj-set! z %ZINCAP 4096)
    (obj-set! z %ZDEC ())
    (obj-set! z %ZDONE #f)
    (obj-set! z %ZOK #t)
    z))

; n bytes of buf from start held after those already held.
(def %take-input!
  (fn (_ z buf start n)
    (def have (obj-ref z %ZINCNT))
    (def total (int+ have n))
    (if (int< (obj-ref z %ZINCAP) total)
      (do (def cap ((fn (self c) (if (int< c total) (self (int<< c 1)) c)) (int<< (obj-ref z %ZINCAP) 1)))
          (def r (str-make cap))
          (if (int< 0 have) (mem-copy (str->ptr r) (str->ptr (obj-ref z %ZIN)) have) ())
          (obj-set! z %ZIN r)
          (obj-set! z %ZINCAP cap))
      ())
    (if (int< 0 n) (mem-copy (%at (str->ptr (obj-ref z %ZIN)) have) (%at (str->ptr buf) start) n) ())
    (obj-set! z %ZINCNT total)))

; The decoder pointed at the input held, its bits carried over, its output
; emptied.
(def %rewind!
  (fn (_ z)
    (def s (obj-ref z %ZDEC))
    (obj-set! s %IN (str->ptr (obj-ref z %ZIN)))
    (obj-set! s %INLEN (obj-ref z %ZINCNT))
    (obj-set! s %INCNT 0)
    (obj-set! s %BITBUF (obj-ref z %ZBITBUF))
    (obj-set! s %BITCNT (obj-ref z %ZBITCNT))
    (obj-set! s %OUTCNT 0)
    s))

; The input the decoder used dropped from the front, and its bits kept.
(def %consume!
  (fn (_ z s)
    (def used (obj-ref s %INCNT))
    (def left (int- (obj-ref z %ZINCNT) used))
    (if (if (int< 0 used) (int< 0 left) #f)
      (do (def r (str-make (obj-ref z %ZINCAP)))
          (mem-copy (str->ptr r) (%at (str->ptr (obj-ref z %ZIN)) used) left)
          (obj-set! z %ZIN r))
      ())
    (obj-set! z %ZINCNT left)
    (obj-set! z %ZBITBUF (obj-ref s %BITBUF))
    (obj-set! z %ZBITCNT (obj-ref s %BITCNT))
    (obj-set! z %ZTRIED 0)))

; The output of what the input held decoded: the header once, then blocks
; while the input holds them whole.  pieces gathers (REGION . N) pairs,
; newest first.  final? says the input has ended, so running out is an
; error, not a wait.
(def %stream-run
  (fn (self z pieces final?)
    (if (obj-ref z %ZDONE) pieces
      (do (def d (obj-ref z %ZDEC))
          (def s (if (null? d)
                   (%decoder (obj-ref z %ZIN) 0 (obj-ref z %ZINCNT) (%engine-for %jit-threshold))
                   (%rewind! z)))
          (def r (guard (e (if (if (%short? e) (not final?) #f) () (error e)))
                   (do (if (null? d) (%header! s) ())
                       (if (null? d) (lit header) (%next! s (obj-ref z %ZCRC))))))
          (match
            ((null? r) (do (obj-set! z %ZTRIED (obj-ref z %ZINCNT)) pieces))
            ((eq? r (lit header))
              (do (obj-set! z %ZDEC s) (%consume! z s) (self z pieces final?)))
            ((not (pair? r))
              (do (obj-set! z %ZCRC r)
                  (%consume! z s)
                  (self z (%piece s pieces) final?)))
            ((eq? (first r) (lit bad))
              (do (obj-set! z %ZOK #f) (obj-set! z %ZDONE #t)
                  (%unread-bytes! s) (%consume! z s)
                  (%piece s pieces)))
            (#t
              (do (if (int= (rest r) (obj-ref z %ZCRC)) () (obj-set! z %ZOK #f))
                  (obj-set! z %ZDONE #t)
                  ; the rest of the last byte is padding
                  (%unread-bytes! s)
                  (obj-set! s %BITCNT 0)
                  (%consume! z s)
                  pieces)))))))

(def %piece
  (fn (_ s pieces)
    (def n (obj-ref s %OUTCNT))
    (if (int= n 0) pieces
      (do (def r (str-make n))
          (mem-copy (str->ptr r) (obj-ref s %OUTP) n)
          (pair (pair r n) pieces)))))

; The pieces, oldest first, as one (OUT N).
(def %join
  (fn (_ pieces)
    (def total (List fold (fn (_ acc p) (int+ acc (rest p))) 0 pieces))
    (def out (%region-of total))
    (List fold (fn (_ at p) (do (mem-copy (%at (str->ptr out) at) (str->ptr (first p)) (rest p)) (int+ at (rest p))))
      0 (List reverse pieces))
    (list out total)))

; Another attempt only once the input held has doubled since the last that
; ran out: a block is retried from its start, and doubling keeps the work
; linear in the input.
(def %stream-feed
  (fn (_ z buf start n)
    (%take-input! z buf start n)
    (if (int< (obj-ref z %ZINCNT) (int<< (obj-ref z %ZTRIED) 1))
      (list %empty 0)
      (%join (%stream-run z () #f)))))

; --- The compiled engine (JIT), adopted only when it proves out --------------
;
; x/codec/bunzip2-jit compiles the three loops that run once a symbol or a
; byte: %decode-symbols!, %link! and %walk-block!.  As Inflate's engine is, it
; is an entry of Compiled's made on demand, built for an input of
; %jit-threshold bytes or more or on (Bunzip2 jit!), and adopted only after
; it decodes the streams below exactly as they do.  The entry's value is the
; list (SYMBOLS LINK WALK): this file's three, or the engine's.

(def %pure (list %decode-symbols! %link! %walk-block!))

; Streams written by bzip2 -9: 181 bytes of mixed text, and a run of 3000
; bytes with two more after it (the run codes and the count bytes).
(def %check-streams
  (list (Str8 append
          "425a68393141592653590151fa6400001b5b80243060057fe80c003ffffff020"
          "0088229a311900069a69a68001a04a9a26434d40c834018d43469b511620e151"
          "0fea635372012d9a81793106fbaf74c18c0a62b60f846b5372af5e0cc6e8bcbf"
          "ba97f7158d13365ea8cc11579c479be9712ba087167e6a92823448c8ad8347d7"
          "dbd54aac36aca10698583d26d2e5ebc0a87b9b966b553642721b373a784a4208"
          "933da88816a42d4b590fe2ee48a70a12002a3f4c80")
        (Str8 append
          "425a68393141592653593c85851f0000068188b000001000008008200030cd00"
          "8a313aa9280385dc914e14240f216147c0")))

(def %region
  (fn (_ bytes)
    (let ((r (str-make (List length bytes))))
      (do ((fn (self i l) (unless (null? l) (do (ptr-set! (str->ptr r) i (first l) 1) (self (int+ i 1) (rest l)))))
           0 bytes)
          r))))


; Does an engine decode every check stream as this file's loops do, byte for
; byte, using as much input?
(def %agrees?
  (fn (_ engine)
    (import x/codec/hex)
    (List all?
      (fn (_ hex)
        (let ((bytes (Hex decode-bytes hex)))
          (let ((in (%region bytes)) (n (List length bytes)))
            (let ((want (%decode-all in 0 n %pure)) (got (%decode-all in 0 n engine)))
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
        (Compiled make-on-demand (lit bunzip2) %pure
          (fn (_)
            (import x/codec/bunzip2-jit)
            ((prim-ref (lit bunzip2) (lit jit-make))
             (list (pair (lit in) %IN) (pair (lit inlen) %INLEN) (pair (lit incnt) %INCNT)
                   (pair (lit bitbuf) %BITBUF) (pair (lit bitcnt) %BITCNT)
                   (pair (lit dbufp) %DBUFP) (pair (lit dbufsize) %DBUFSIZE)
                   (pair (lit outp) %OUTP) (pair (lit outcap) %OUTCAP) (pair (lit outcnt) %OUTCNT))
             %room! %crc-table %agrees?))
          (fn (_ _) ()))))
    ((fn (_ entry)
       (when (eq? (entry state) (lit interpreted)) (entry compile!))
       (eq? (entry state) (lit compiled)))
     %entry)))

; (SYMBOLS LINK WALK) for n bytes of input: the engine's when it is built,
; or when n is past the bar and a build succeeds; else this file's.
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

(def %empty (%region-of 0))


(def %span
  (fn (_ s span)
    (match
      ((null? span) (list 0 (str-byte-len s)))
      ((null? (rest span)) (list (first span) (int- (str-byte-len s) (first span))))
      (#t (list (first span) (first (rest span)))))))

(def-class Bunzip2 ()
  (doc "bzip2 decompression in pure x-lang, as busybox's bunzip2 decodes it. (Bunzip2 decode s) answers (OUT N USED) for one whole stream; a stream can also be fed a piece at a time: stream, feed, finish, done?, ok?, rest. A malformed stream raises a label 'value whose data holds (bunzip . KIND), KIND one of 'magic, 'header, 'data, 'obsolete or 'crc, and (short . #t) when the input ends inside it.")
  (static
    (method decode (self (param s STRING "Bytes holding a bzip2 stream")
                         . (param span LIST "START, then LENGTH: where the stream starts in s and how many bytes of s it may use; default all of s"))
      (doc "Decompress one bzip2 stream: \"BZh\", its blocks, the end marker. Every block's CRC and the stream's are checked. Give LENGTH for binary input: s's own length is measured to its first NUL."
        (returns LIST "(OUT N USED): the output region, its byte count, and the input bytes the stream used"))
      (def sp (%span s span))
      (%decode-all s (first sp) (first (rest sp)) (%engine-for (first (rest sp)))))
    (method stream (self)
      (doc "A bzip2 stream to be fed a piece at a time with (Bunzip2 feed), what bunzip2 wants of a file it must not read whole. A block is decoded once the input holds it whole; the input held is at most about a block's."
        (returns OBJECT "The stream")
        (example "(let ((z (Bunzip2 stream))) (Bunzip2 done? z))" "#f"))
      (%stream-new))
    (method feed (self (param z OBJECT "A (Bunzip2 stream)")
                       (param s STRING "Bytes holding the next piece")
                       (param start INTEGER "Where the piece starts in s")
                       (param n INTEGER "How many bytes it is"))
      (doc "Give the stream n more bytes. Answers what the blocks they complete decode to; once the end marker is read, more bytes are kept for (Bunzip2 rest) and answer none. A block whose CRC is wrong is answered all the same and ends the stream, ok? then #f. Raises a label 'value on a malformed stream."
        (returns LIST "(OUT N): a region and how many of its bytes came out"))
      (%stream-feed z s start n))
    (method finish (self (param z OBJECT "A (Bunzip2 stream)"))
      (doc "The input has ended: what is held is decoded, and a stream cut short raises a label 'value whose data holds (short . #t)."
        (returns LIST "(OUT N), as feed answers"))
      (%join (%stream-run z () #t)))
    (method done? (self (param z OBJECT "A (Bunzip2 stream)"))
      (doc "Has the stream's end been reached: its end marker read, or a block whose CRC is wrong?"
        (returns BOOL "#t once it has"))
      (obj-ref z %ZDONE))
    (method ok? (self (param z OBJECT "A (Bunzip2 stream)"))
      (doc "Has every CRC read so far held: each block's, and the stream's at its end?"
        (returns BOOL "#f once one has not"))
      (obj-ref z %ZOK))
    (method rest (self (param z OBJECT "A (Bunzip2 stream)"))
      (doc "The input not used: once the stream is done, the bytes after its end -- the next stream of a file that holds several, say."
        (returns LIST "(BUF N): a region and how many bytes of it"))
      (list (obj-ref z %ZIN) (obj-ref z %ZINCNT)))
    (method jit! (self)
      (doc "Build and adopt the compiled symbol, link and walk loops (JIT; ARM64 and x86-64 backends) now, if they decode the check streams exactly as the pure-x ones do. Idempotent. Answers #t when the engine is active, #f when unavailable -- the pure-x decoder carries on, with the same output. decode builds it on its own for an input of 4KB or more, and a fed stream always."
        (returns BOOL "#t when the compiled engine is active"))
      (%jit-try!))))

(doc (provide x/codec/bunzip2 Bunzip2)
  "bzip2 decompression in pure x-lang, busybox's decoder: (Bunzip2 decode s) answers (OUT N USED); stream, feed, finish, done?, ok? and rest decode a piece at a time.")

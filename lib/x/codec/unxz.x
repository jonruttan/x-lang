; unxz.x -- Unxz: .xz decompression in pure x-lang.
;
; Reads the .xz format as busybox's unxz and xzcat do (archival/libarchive/
; decompress_unxz.c over XZ Embedded's xz_dec_stream.c and xz_dec_lzma2.c,
; Lasse Collin's).  A stream is a 12-byte header -- the magic, two flag
; bytes naming the check, their CRC32 -- then blocks, an index of the
; blocks' sizes, and a 12-byte footer.  A block is a header naming its
; filters, the compressed data, padding to four bytes, and the check of
; what it decodes to.  Streams can follow one another, zero bytes between.
;
; The one filter is LZMA2, as busybox builds it: no BCJ filter, so a block
; asking for one is refused.  LZMA2 frames LZMA as chunks of at most 64KB
; packed: a control byte says whether the chunk is a copy or a run of
; decisions, and whether the window, the state or the properties are reset
; first.  The decisions are Unlzma's own coder, held across chunks by
; x/codec/unlzma's unlzma-chunks, on whichever engine Unlzma runs.
;
; Of the checks only CRC32 is verified, as busybox verifies it; CRC64 and
; SHA-256, and the check IDs no one has assigned, are skipped by their
; size.  The index is checked against the blocks decoded: their count, and
; each block's sizes.
;
; A stream fed a piece at a time decodes a chunk once all of it is held, so
; what is held between pieces is under a chunk's framing and 64KB.  A
; stream that ends inside a chunk decodes what of the chunk it has before
; it raises, as busybox writes it.
(module x/codec/unxz)

(import x/type/vector)
(import x/codec/bytes)
(import x/codec/crc32)
(import x/codec/unlzma unlzma-chunks)
(import x/core/doors int& int* int+ int- int< int= int>> mem-copy obj-ref obj-set! ptr->int int->ptr ptr-ref str->ptr str-byte-len str-make)

(def %chunk (fn (_ name) (rest (Assoc entry name unlzma-chunks))))
(def %lz-decoder (%chunk (lit decoder)))
(def %lz-dict-reset! (%chunk (lit dict-reset!)))
(def %lz-state-reset! (%chunk (lit state-reset!)))
(def %lz-props! (%chunk (lit props!)))
(def %lz-lzma! (%chunk (lit lzma!)))
(def %lz-copy! (%chunk (lit copy!)))
(def %lz-take! (%chunk (lit take!)))
(def %lz-error? (%chunk (lit error?)))

(def %fail
  (fn (_ kind what)
    (Err raise (lit value) (Str8 append "Unxz: " what) (list (pair (lit xz) kind)))))

; The Check field's size by its ID, as the format assigns them in threes.
(def %check-sizes (list 0 4 4 4 8 8 8 16 16 16 32 32 32 64 64 64))

; --- the stream's state, in the slots of one vector ---------------------------
;
; The input held, its capacity and count, and how much of it is read; where
; the stream is; the check its header names and its flag bytes; the LZMA2
; decoder of the block being decoded; whether the next chunk must reset the
; window, and whether it must set properties; the block header's size, the
; sizes it declares (-1 for none), and those seen so far; the CRC32 of the
; block's output; the blocks decoded, each its (UNPADDED . UNCOMPRESSED),
; latest first; the output this call has decoded, as (OUT . N) pieces,
; latest first; and how many streams have ended.
(def %IN 1)
(def %INCAP 2)
(def %INCNT 3)
(def %POS 4)
(def %PHASE 5)
(def %CHECK 6)
(def %FLAGS 7)
(def %DEC 8)
(def %NEEDDICT 9)
(def %NEEDPROPS 10)
(def %BHSIZE 11)
(def %BDCOMP 12)
(def %BDUNC 13)
(def %BCOMP 14)
(def %BUNC 15)
(def %CRC 16)
(def %BLOCKS 17)
(def %PIECES 18)
(def %STREAMS 19)
(def %ISIZE 20)
(def %NSLOTS 20)

; --- the input held -------------------------------------------------------------

(def %at (fn (_ p off) (int->ptr (int+ (ptr->int p) off))))
(def %have (fn (_ z) (int- (obj-ref z %INCNT) (obj-ref z %POS))))
(def %b (fn (_ z i) (int& (ptr-ref (str->ptr (obj-ref z %IN)) (int+ (obj-ref z %POS) i) 1) 255)))
(def %skip! (fn (_ z n) (obj-set! z %POS (int+ (obj-ref z %POS) n))))

; n bytes from i, least significant first, as the number they are.
(def %le
  (fn (_ z i n)
    ((fn (self k acc) (if (int< k 0) acc (self (int- k 1) (+ (* acc 256) (%b z (int+ i k))))))
     (int- n 1) 0)))

(def %crc-of (fn (_ z i n) (Crc32 of (obj-ref z %IN) (int+ (obj-ref z %POS) i) n)))

; A variable-length integer at i of the held bytes, as (VALUE . LENGTH): seven
; bits a byte, least significant first, the top bit set on every byte but
; the last.  () when the bytes held end inside it.  Nine bytes at most, and
; no zero byte ending one of two or more.
(def %vli
  (fn (_ z i limit)
    ((fn (self k acc m)
       (match
         ((int< 8 k) (%fail (lit data) "a number runs past nine bytes"))
         ((int< (int- limit 1) (int+ i k)) ())
         (#t (do (def b (%b z (int+ i k)))
                 (def acc2 (+ acc (* m (int& b 127))))
                 (if (int< b 128)
                   (if (if (int= b 0) (int< 0 k) #f)
                     (%fail (lit data) "a number is not written in its fewest bytes")
                     (pair acc2 (int+ k 1)))
                   (self (int+ k 1) acc2 (* m 128)))))))
     0 0 1)))

; n bytes of buf from start held after those not yet read, which move to the
; front first.
(def %take-input!
  (fn (_ z buf start n)
    (def left (%have z))
    (def total (int+ left n))
    (def cap ((fn (self c) (if (int< c total) (self (* c 2)) c)) (obj-ref z %INCAP)))
    ; the bytes left go to a region of their own unless they are at its front
    ; already, so no copy reads where it writes
    (def r (if (if (int< (obj-ref z %INCAP) total) #t (if (int< 0 left) (int< 0 (obj-ref z %POS)) #f))
             (str-make cap) (obj-ref z %IN)))
    (if (int< 0 left) (mem-copy (str->ptr r) (%at (str->ptr (obj-ref z %IN)) (obj-ref z %POS)) left) ())
    (if (int< 0 n) (mem-copy (%at (str->ptr r) left) (%at (str->ptr buf) start) n) ())
    (obj-set! z %IN r)
    (obj-set! z %INCAP cap)
    (obj-set! z %INCNT total)
    (obj-set! z %POS 0)))

; --- the output -------------------------------------------------------------------

; The decoder's output since the last take, onto this call's pieces and into
; the block's check.
(def %take-out!
  (fn (_ z)
    (def o (%lz-take! (obj-ref z %DEC)))
    (def n (first (rest o)))
    (if (int< 0 n)
      (do (obj-set! z %PIECES (pair (pair (first o) n) (obj-ref z %PIECES)))
          (if (int= 1 (obj-ref z %CHECK)) (obj-set! z %CRC (Crc32 update (obj-ref z %CRC) (first o) 0 n)) ()))
      ())))

; This call's pieces as one region, (OUT N).
(def %joined
  (fn (_ z)
    (def ps (List reverse (obj-ref z %PIECES)))
    (obj-set! z %PIECES ())
    (match
      ((null? ps) (list (first (Bytes zeros 1)) 0))
      ((null? (rest ps)) (list (first (first ps)) (rest (first ps))))
      (#t (do (def total (List fold (fn (_ acc p) (int+ acc (rest p))) 0 ps))
              (def r (str-make total))
              (List fold (fn (_ at p) (do (mem-copy (%at (str->ptr r) at) (str->ptr (first p)) (rest p)) (int+ at (rest p)))) 0 ps)
              (list r total))))))

; --- the stream header and footer ---------------------------------------------------

(def %magic (list 253 55 122 88 90 0))

(def %magic?
  (fn (_ z)
    ((fn (self i l) (if (null? l) #t (if (int= (first l) (%b z i)) (self (int+ i 1) (rest l)) #f))) 0 %magic)))

(def %stream-header!
  (fn (_ z)
    (match
      ((not (%magic? z)) (%fail (lit format) "the input is not an .xz stream"))
      ((not (= (%crc-of z 6 2) (%le z 8 4))) (%fail (lit data) "the stream header's CRC32 does not match"))
      ((not (int= 0 (%b z 6))) (%fail (lit options) "the stream flags name an option this decoder does not know"))
      ((int< 15 (%b z 7)) (%fail (lit options) "the stream names a check that is not one"))
      (#t (do (obj-set! z %CHECK (%b z 7))
              (obj-set! z %BLOCKS ())
              (%skip! z 12)
              (obj-set! z %PHASE (lit block)))))))

; The footer: its CRC32, the index's size in fours, the stream's flags again
; and the magic YZ.
(def %stream-footer!
  (fn (_ z index-size)
    (match
      ((not (if (int= 89 (%b z 10)) (int= 90 (%b z 11)) #f)) (%fail (lit data) "the stream footer's magic is wrong"))
      ((not (= (%crc-of z 4 6) (%le z 0 4))) (%fail (lit data) "the stream footer's CRC32 does not match"))
      ((not (= (%le z 4 4) (int>> index-size 2))) (%fail (lit data) "the stream footer's index size is wrong"))
      ((not (if (int= 0 (%b z 8)) (int= (obj-ref z %CHECK) (%b z 9)) #f))
        (%fail (lit data) "the stream footer's flags differ from its header's"))
      (#t (do (%skip! z 12)
              (obj-set! z %STREAMS (int+ 1 (obj-ref z %STREAMS)))
              (obj-set! z %PHASE (lit padding)))))))

; --- a block header -----------------------------------------------------------------
;
; Its size in fours, flags, the compressed and uncompressed sizes where the
; flags say they are there, one filter's flags, padding, and its CRC32.  The
; filter must be LZMA2, 0x21, with one byte of properties: the window's
; size, 2 or 3 times a power of two from 4KB.

(def %block-header!
  (fn (_ z size)
    (def flags (%b z 1))
    (def body (int- size 4))
    (if (= (%crc-of z 0 body) (%le z body 4)) ()
      (%fail (lit data) "a block header's CRC32 does not match"))
    (if (int= 0 (int& flags 63)) ()
      (%fail (lit options) "a block asks for a filter this decoder does not have"))
    (def comp (if (int= 0 (int& flags 64)) (pair -1 0) (%vli z 2 body)))
    (if (null? comp) (%fail (lit data) "a block header ends inside its sizes") ())
    (def unc (if (int= 0 (int& flags 128)) (pair -1 0) (%vli z (int+ 2 (rest comp)) body)))
    (if (null? unc) (%fail (lit data) "a block header ends inside its sizes") ())
    (def f (int+ 2 (int+ (rest comp) (rest unc))))
    (if (int< body (int+ f 3)) (%fail (lit data) "a block header ends inside its filter") ())
    (if (int= 33 (%b z f)) () (%fail (lit options) "a block's filter is not LZMA2"))
    (if (int= 1 (%b z (int+ f 1))) () (%fail (lit options) "a block's LZMA2 properties are not one byte"))
    (def props (%b z (int+ f 2)))
    (if (int< 39 props) (%fail (lit options) "a block's window is past 3GB") ())
    ((fn (self i) (if (int< i body) (if (int= 0 (%b z i)) (self (int+ i 1)) (%fail (lit options) "a block header's padding is not zero")) ()))
     (int+ f 3))
    (obj-set! z %DEC (%lz-decoder ((fn (self v k) (if (int< k 1) v (self (* v 2) (int- k 1))))
                                   (int+ 2 (int& props 1)) (int+ (int>> props 1) 11))))
    (obj-set! z %NEEDDICT #t)
    (obj-set! z %NEEDPROPS #t)
    (obj-set! z %BHSIZE size)
    (obj-set! z %BDCOMP (first comp))
    (obj-set! z %BDUNC (first unc))
    (obj-set! z %BCOMP 0)
    (obj-set! z %BUNC 0)
    (obj-set! z %CRC 0)
    (%skip! z size)
    (obj-set! z %PHASE (lit chunk))))

; --- LZMA2 chunks ---------------------------------------------------------------------
;
; The control byte: 0 ends the block's data; 1 resets the window and copies,
; 2 copies, each its size in two bytes; from 0x80 an LZMA chunk, its
; unpacked size in the low five bits and two bytes, its packed size in two
; more, and from 0xC0 a properties byte.  Above 0x80 the bits say what is
; reset first: 0xA0 the state, 0xC0 the properties and state, 0xE0 the
; window as well.  A block's first chunk resets the window, and the first
; LZMA chunk after a window reset sets properties.

; The bytes a chunk's framing takes, by its control byte.
(def %framing
  (fn (_ c) (match ((int< c 3) 3) ((int< c 192) 5) (#t 6))))

; The block's sizes so far against those its header declares.
(def %sizes-ok!
  (fn (_ z)
    (if (if (int< (obj-ref z %BDCOMP) 0) #f (< (obj-ref z %BDCOMP) (obj-ref z %BCOMP)))
      (%fail (lit data) "a block is longer than its header says") ())
    (if (if (int< (obj-ref z %BDUNC) 0) #f (< (obj-ref z %BDUNC) (obj-ref z %BUNC)))
      (%fail (lit data) "a block decodes to more than its header says") ())))

; One chunk once all of it is held; #f when it is not held whole yet.  With
; final?, a chunk cut short decodes what it holds and raises.
(def %chunk!
  (fn (_ z final?)
    (def c (%b z 0))
    (def d (obj-ref z %DEC))
    (def frame (%framing c))
    (match
      ((int= c 0)
        (do (%skip! z 1)
            (obj-set! z %BCOMP (int+ 1 (obj-ref z %BCOMP)))
            (%sizes-ok! z)
            (obj-set! z %PHASE (lit block-end))
            #t))
      ((if (int< 2 c) (int< c 128) #f) (%fail (lit data) "a chunk's control byte is not one"))
      ((if (int= c 1) #f (if (int< c 224) (obj-ref z %NEEDDICT) #f))
        (%fail (lit data) "a block's first chunk does not reset the window"))
      ((if (int< c 3) #f (if (int< c 192) (obj-ref z %NEEDPROPS) #f))
        (%fail (lit data) "an LZMA chunk after a window reset sets no properties"))
      ((int< (%have z) frame) (if final? (%fail (lit short) "the stream ends inside a chunk's framing") #f))
      (#t
        (do (def unpacked (if (int< c 3) (int+ 1 (%le-be z 1)) (int+ 1 (+ (* 65536 (int& c 31)) (%le-be z 1)))))
            (def packed (if (int< c 3) unpacked (int+ 1 (%le-be z 3))))
            (if (if (int< 2 c) (int< packed 5) #f) (%fail (lit data) "an LZMA chunk is too short for its coder") ())
            (def whole (not (int< (%have z) (int+ frame packed))))
            (if (if whole #t final?)
              (do (if (if (int= c 1) #t (int< 223 c))
                    (do (%lz-dict-reset! d) (obj-set! z %NEEDDICT #f) (obj-set! z %NEEDPROPS (int= c 1)))
                    ())
                  (match
                    ((int< 191 c)
                      (if (%lz-props! d (%b z 5)) (obj-set! z %NEEDPROPS #f)
                        (%fail (lit data) "a chunk's properties byte is out of range")))
                    ((int< 159 c) (%lz-state-reset! d))
                    (#t ()))
                  (def avail (int- (%have z) frame))
                  (def at (int+ (obj-ref z %POS) frame))
                  (if whole
                    (do (if (int< c 3) (%lz-copy! d (obj-ref z %IN) at unpacked)
                          (%lz-lzma! d (obj-ref z %IN) at packed unpacked))
                        (%take-out! z)
                        (%skip! z (int+ frame packed))
                        (obj-set! z %BCOMP (+ (obj-ref z %BCOMP) (int+ frame packed)))
                        (obj-set! z %BUNC (+ (obj-ref z %BUNC) unpacked))
                        (%sizes-ok! z)
                        #t)
                    (do (if (int< c 3) (%lz-copy! d (obj-ref z %IN) at avail)
                          (%lz-lzma! d (obj-ref z %IN) at avail unpacked))
                        (%fail (lit short) "the stream ends inside a chunk"))))
              #f)))))))

; Two bytes, most significant first, from i.
(def %le-be (fn (_ z i) (int+ (* 256 (%b z i)) (%b z (int+ i 1)))))

; After the data: padding to a multiple of four, then the check.  The block's
; sizes go to the list the index is checked against.
(def %block-end!
  (fn (_ z final?)
    (def pad (int& (int- 4 (int& (obj-ref z %BCOMP) 3)) 3))
    (def csize (List ref (obj-ref z %CHECK) %check-sizes))
    (if (int< (%have z) (int+ pad csize))
      (if final? (%fail (lit short) "the stream ends inside a block's check") #f)
      (do ((fn (self i) (if (int< i pad) (if (int= 0 (%b z i)) (self (int+ i 1)) (%fail (lit data) "a block's padding is not zero")) ())) 0)
          (if (int= 1 (obj-ref z %CHECK))
            (if (= (obj-ref z %CRC) (%le z pad 4)) () (%fail (lit data) "a block's CRC32 does not match"))
            ())
          (if (if (int< (obj-ref z %BDCOMP) 0) #f (not (= (obj-ref z %BDCOMP) (obj-ref z %BCOMP))))
            (%fail (lit data) "a block is shorter than its header says") ())
          (if (if (int< (obj-ref z %BDUNC) 0) #f (not (= (obj-ref z %BDUNC) (obj-ref z %BUNC))))
            (%fail (lit data) "a block decodes to less than its header says") ())
          (obj-set! z %BLOCKS (pair (pair (+ (obj-ref z %BHSIZE) (+ (obj-ref z %BCOMP) csize)) (obj-ref z %BUNC))
                                    (obj-ref z %BLOCKS)))
          (obj-set! z %DEC ())
          (%skip! z (int+ pad csize))
          (obj-set! z %PHASE (lit block))
          #t))))

; --- the index ---------------------------------------------------------------------
;
; A zero byte, the count of records, each record's unpadded and uncompressed
; sizes, padding to four, and its CRC32: read once all of it is held, and
; held against the blocks decoded.  Answers the index's size without its
; CRC32, or () while it is not held whole.

(def %index
  (fn (_ z)
    (def limit (%have z))
    (def count (%vli z 1 limit))
    (if (null? count) ()
      ((fn (self i k recs)
         (if (int< 0 k)
           (let ((u (%vli z i limit)))
             (if (null? u) ()
               (let ((c (%vli z (int+ i (rest u)) limit)))
                 (if (null? c) ()
                   (self (int+ i (int+ (rest u) (rest c))) (int- k 1) (pair (pair (first u) (first c)) recs))))))
           (do (def size (int+ i (int& (int- 4 (int& i 3)) 3)))
               (if (int< limit (int+ size 4)) ()
                 (do ((fn (self j) (if (int< j size) (if (int= 0 (%b z j)) (self (int+ j 1)) (%fail (lit data) "the index's padding is not zero")) ())) i)
                     (if (= (%crc-of z 0 size) (%le z size 4)) () (%fail (lit data) "the index's CRC32 does not match"))
                     (if (equal? recs (obj-ref z %BLOCKS)) () (%fail (lit data) "the index does not match the blocks"))
                     size)))))
       (int+ 1 (rest count)) (first count) ()))))

; --- the stream ----------------------------------------------------------------------

; One step from the bytes held: #t when it read some, #f when it waits for
; more.  final? says no more will come.
(def %step!
  (fn (_ z final?)
    (def ph (obj-ref z %PHASE))
    (def have (%have z))
    (match
      ((eq? ph (lit done)) #f)
      ((eq? ph (lit header))
        (if (int< have 12) (if final? (%fail (lit short) "the stream ends inside its header") #f)
          (do (%stream-header! z) #t)))
      ((eq? ph (lit block))
        (match
          ((int< have 1) (if final? (%fail (lit short) "the stream ends before its index") #f))
          ((int= 0 (%b z 0)) (do (obj-set! z %PHASE (lit index)) #t))
          (#t (do (def size (int* 4 (int+ 1 (%b z 0))))
                  (if (int< have size) (if final? (%fail (lit short) "the stream ends inside a block header") #f)
                    (do (%block-header! z size) #t))))))
      ((eq? ph (lit chunk))
        (if (int< have 1) (if final? (%fail (lit short) "the stream ends inside a block") #f)
          (%chunk! z final?)))
      ((eq? ph (lit block-end)) (%block-end! z final?))
      ((eq? ph (lit index))
        (do (def size (%index z))
            (if (null? size) (if final? (%fail (lit short) "the stream ends inside its index") #f)
              (do (%skip! z (int+ size 4)) (obj-set! z %PHASE (lit footer)) (obj-set! z %ISIZE size) #t))))
      ((eq? ph (lit footer))
        (if (int< have 12) (if final? (%fail (lit short) "the stream ends inside its footer") #f)
          (do (%stream-footer! z (obj-ref z %ISIZE)) #t)))
      ; zero bytes between streams, then another stream, or the end: a byte
      ; that cannot start one is left for rest, as busybox stops there
      (#t (match
            ((int< have 1) #f)
            ((int= 0 (%b z 0)) (do (%skip! z 1) #t))
            ((int= 253 (%b z 0)) (do (obj-set! z %PHASE (lit header)) #t))
            (#t (do (obj-set! z %PHASE (lit done)) #f)))))))

(def %steps!
  (fn (self z final?) (if (%step! z final?) (self z final?) ())))

; Is e a malformed stream's raise, Unxz's own or the coder's?
(def %xz-error?
  (fn (_ e)
    (and (eq? (Err label e) (lit value))
         (List any? (fn (_ p) (and (pair? p) (eq? (first p) (lit xz)))) (e data)))))

; What the bytes held decode to, as (OUT N).  A stream gone bad is over, and
; its raise carries what this call decoded before the step that failed.
(def %run
  (fn (_ z final?)
    (guard (e (if (if (%xz-error? e) #t (%lz-error? e)) (%gone-bad! z e) (error e)))
      (do (%steps! z final?)
          (if final?
            (if (match ((eq? (obj-ref z %PHASE) (lit done)) #t)
                       ((eq? (obj-ref z %PHASE) (lit padding)) #t)
                       (#t #f))
              ()
              (%fail (lit short) "the stream ends early"))
            ())
          (if final? (obj-set! z %PHASE (lit done)) ())
          (%joined z)))))

; The coder's kinds are the container's: short input, else bad data.
(def %gone-bad!
  (fn (_ z e)
    (if (null? (obj-ref z %DEC)) () (%take-out! z))
    (def kind (if (List any? (fn (_ p) (and (pair? p) (eq? (rest p) (lit short)))) (e data)) (lit short)
                ((fn (_ p) (if (null? p) (lit data) (rest p)))
                 (List find (fn (_ p) (and (pair? p) (eq? (first p) (lit xz)))) (e data)))))
    (def msg (if (%lz-error? e) (Str8 append "Unxz: " (Str8 sub 8 (int- (str-byte-len (e msg)) 8) (e msg))) (e msg)))
    (def out (%joined z))
    (obj-set! z %PHASE (lit done))
    (Err raise (lit value) msg (list (pair (lit xz) kind) (pair (lit out) out)))))

(def %stream-new
  (fn (_)
    (def z (Vector make %NSLOTS 0))
    (obj-set! z %IN (str-make 4096))
    (obj-set! z %INCAP 4096)
    (obj-set! z %PHASE (lit header))
    (obj-set! z %DEC ())
    (obj-set! z %BLOCKS ())
    (obj-set! z %PIECES ())
    z))

(def %feed
  (fn (_ z buf start n)
    (if (eq? (obj-ref z %PHASE) (lit done))
      (do (%take-input! z buf start n) (list (first (Bytes zeros 1)) 0))
      (do (%take-input! z buf start n) (%run z #f)))))

(def %finish
  (fn (_ z)
    (if (eq? (obj-ref z %PHASE) (lit done)) (list (first (Bytes zeros 1)) 0) (%run z #t))))

(def %span
  (fn (_ s span)
    (match
      ((null? span) (list 0 (str-byte-len s)))
      ((null? (rest span)) (list (first span) (int- (str-byte-len s) (first span))))
      (#t (list (first span) (first (rest span)))))))

(def-class Unxz ()
  (doc "xz decompression in pure x-lang, the .xz format busybox's unxz and xzcat read: LZMA2 blocks, CRC32 checks verified and the others skipped, concatenated streams. (Unxz decode s start n) answers (OUT N USED); a stream can also be fed a piece at a time: stream, feed, finish, done?, rest. A malformed stream raises a label 'value whose data holds (xz . KIND) -- 'short when the input ends inside it, 'format when it is not .xz, 'options for a filter or flag it does not support, else 'data -- and (out OUT N), what that call decoded before the step that failed."
    (example "(do (import x/codec/bytes) (def z (Bytes of-hex \"fd377a585a000004e6d6b44604c00905210116000000000000000000bf792567010004616263640a00000000a0c3db19868851500001250543911fb81fb6f37d010000000004595a\")) (first (rest (Unxz decode (first z) 0 (Bytes length z)))))" "5"))
  (static
    (method decode (self (param s STRING "Bytes holding .xz streams")
                         . (param span INTEGER "START, then LENGTH: where the streams start in s and how many bytes of s they may use; default all of s"))
      (doc "Decompress the .xz streams in s, one after another, zero bytes between them, to the end of the bytes or to a byte that cannot start a stream. Give LENGTH for binary input: s's own length is measured to its first NUL, and a header holds one."
        (returns LIST "(OUT N USED): the output region, its byte count, and the input bytes the streams used")
        (example "(do (import x/codec/bytes) (def z (Bytes of-hex \"fd377a585a0000016922de36000000001cdf44219042990d010000000001595a\")) (first (rest (Unxz decode (first z) 0 (Bytes length z)))))" "0"))
      (def sp (%span s span))
      (def z (%stream-new))
      (def a (%feed z s (first sp) (first (rest sp))))
      (def b (%finish z))
      (obj-set! z %PIECES (list (pair (first b) (first (rest b))) (pair (first a) (first (rest a)))))
      (def out (%joined z))
      (list (first out) (first (rest out)) (int- (first (rest sp)) (%have z))))
    (method stream (self)
      (doc "An .xz stream to be fed a piece at a time with (Unxz feed), what unxz wants of a file it must not read whole. A chunk is decoded once all of it is held, so between pieces the input held is under 64KB and a chunk's framing."
        (returns VECTOR "The stream")
        (example "(let ((z (Unxz stream))) (Unxz done? z))" "#f"))
      (%stream-new))
    (method feed (self (param z VECTOR "A (Unxz stream)")
                       (param s STRING "Bytes holding the next piece")
                       (param start INTEGER "Where the piece starts in s")
                       (param n INTEGER "How many bytes it is"))
      (doc "Give the stream n more bytes. Answers what the chunks they complete decode to. Once the end is reached, more bytes are kept for (Unxz rest) and answer none. A malformed stream raises a label 'value whose data holds (xz . KIND) and (out OUT N), what this call decoded before the step that failed, and the stream is over."
        (returns LIST "(OUT N): a region and how many of its bytes came out")
        (example "(do (import x/codec/bytes) (def b (Bytes of-hex \"fd377a585a000004e6d6b44604c00905210116000000000000000000bf792567010004616263640a00000000a0c3db19868851500001250543911fb81fb6f37d010000000004595a\")) (def z (Unxz stream)) (first (rest (Unxz feed z (first b) 0 (Bytes length b)))))" "5"))
      (%feed z s start n))
    (method finish (self (param z VECTOR "A (Unxz stream)"))
      (doc "The input has ended: what is held is decoded, and a stream cut short raises a label 'value whose data holds (xz . short) and (out OUT N), what this call decoded before it ran out, a cut chunk's bytes among them, as busybox writes them before it stops."
        (returns LIST "(OUT N), as feed answers")
        (example "(do (import x/codec/bytes) (def b (Bytes of-hex \"fd377a585a000004e6d6b44604c00905210116000000000000000000bf792567010004616263640a00000000a0c3db19868851500001250543911fb81fb6f37d010000000004595a\")) (def z (Unxz stream)) (Unxz feed z (first b) 0 (Bytes length b)) (first (rest (Unxz finish z))))" "0"))
      (%finish z))
    (method done? (self (param z VECTOR "A (Unxz stream)"))
      (doc "Has the end been reached: a byte that cannot start a stream after one ends, finish, or a raise?"
        (returns BOOL "#t once it has")
        (example "(do (import x/codec/bytes) (def b (Bytes of-hex \"fd377a585a0000016922de36000000001cdf44219042990d010000000001595a\")) (def z (Unxz stream)) (Unxz feed z (first b) 0 (Bytes length b)) (Unxz finish z) (Unxz done? z))" "#t"))
      (eq? (obj-ref z %PHASE) (lit done)))
    (method rest (self (param z VECTOR "A (Unxz stream)"))
      (doc "The input not used: once the stream is done, the bytes from the first that cannot start a stream."
        (returns LIST "(BUF N): a region and how many bytes of it")
        (example "(do (import x/codec/bytes) (def b (Bytes of-hex \"fd377a585a0000016922de36000000001cdf44219042990d010000000001595a414243\")) (def z (Unxz stream)) (Unxz feed z (first b) 0 (Bytes length b)) (Unxz finish z) (first (rest (Unxz rest z))))" "3"))
      (def n (%have z))
      (def r (str-make (if (int< n 1) 1 n)))
      (if (int< 0 n) (mem-copy (str->ptr r) (%at (str->ptr (obj-ref z %IN)) (obj-ref z %POS)) n) ())
      (list r n))))

(doc (provide x/codec/unxz Unxz)
  (example "(do (import x/codec/bytes) (def z (Bytes of-hex \"fd377a585a000004e6d6b44604c00905210116000000000000000000bf792567010004616263640a00000000a0c3db19868851500001250543911fb81fb6f37d010000000004595a\")) (def r (Unxz decode (first z) 0 (Bytes length z))) (Bytes hex (list (first r) 0 (first (rest r)))))" "\"616263640a\"")
  "xz decompression in pure x-lang, the .xz format: (Unxz decode s start n) answers (OUT N USED); stream, feed, finish, done? and rest decode a piece at a time.")

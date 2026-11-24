; jpeg.x -- Jpeg: baseline JPEG images (ITU T.81, JFIF) decoded to RGBA in pure x-lang.
;
; A JPEG is markers, each 0xFF and a code, most leading a segment that
; starts with its own length.  DQT holds quantization tables, DHT Huffman
; tables, SOF the frame: its size and its components, each with its
; sampling factors and quantization table.  SOS starts a scan: entropy-coded
; data for one component or several interleaved, up to the next marker,
; 0xFF in it stuffed as 0xFF 0x00 and cut into restart intervals by RSTn
; when DRI asks.  The data is 8 x 8 blocks of DCT coefficients, a block's
; DC coded as the difference from the one before it in its component and
; its AC in zig-zag order as runs of zeros and values.
;
; Out comes RGBA at 8 bits a sample.  The arithmetic follows libjpeg's
; defaults so the pixels are the same as its: the accurate integer inverse
; DCT (jidctint.c), "fancy" triangle upsampling of 2:1 chroma (jdsample.c)
; and its fixed-point YCbCr to RGB (jdcolor.c).  One component is grey;
; three are YCbCr unless an Adobe marker says RGB or the components are
; named R, G and B.  Baseline and extended sequential Huffman frames at 8
; bits are decoded; a progressive, arithmetic-coded, lossless, 12-bit or
; four-component image raises.  A malformed image raises a label 'value
; naming what was wrong.
(module x/codec/jpeg)

(import x/codec/bytes)
(import x/sys/gc)
(import x/core/doors int& int* int+ int- int->ptr int/ int< int<< int= int>> int| ptr->int ptr-ref ptr-set! str->ptr str-byte-len)

(def %fail (fn (_ what) (Err raise (lit value) (Str8 append "Jpeg: " what) ())))

(def %at (fn (_ p off) (int->ptr (int+ (ptr->int p) off))))
(def %u8 (fn (_ p i) (int& (ptr-ref p i 1) 255)))
(def %u16 (fn (_ p i) (int| (int<< (%u8 p i) 8) (%u8 p (int+ i 1)))))
; Word slots, signed.
(def %w (fn (_ p i) (ptr-ref p (int<< i 3) 8)))
(def %w! (fn (_ p i v) (ptr-set! p (int<< i 3) v 8)))
; A zeroed buffer.  Each is held by its string: a collect frees a buffer
; only a pointer reaches.
(def %buf (fn (_ n) (first (Bytes zeros n))))
; A collect every eighth row or MCU: x collects only where asked, and each
; step leaves its lists and closures behind.
(def %tidy (fn (_ i) (when (int= (int& i 7) 7) (Heap collect))))
(def %clamp (fn (_ v) (match ((int< v 0) 0) ((int< 255 v) 255) (#t v))))
(def %div-up (fn (_ a b) (int/ (int- (int+ a b) 1) b)))
; Whether AT answers 0 for each of 1 to 7: a column or row with no AC.
(def %ac-zero? (fn (_ at) ((fn (self r) (match ((int< 7 r) #t) ((int= (at r) 0) (self (int+ r 1))) (#t #f))) 1)))

(def %span
  (fn (_ s span)
    (match
      ((null? span) (list 0 (str-byte-len s)))
      ((null? (rest span)) (list (first span) (int- (str-byte-len s) (first span))))
      (#t (list (first span) (first (rest span)))))))

(def %need (fn (_ i n end) (when (int< end (int+ i n)) (%fail "the file ends early"))))

; The natural (row-major) index of each zig-zag position.  The string is
; what is kept: a pointer alone would not hold it across a collect.
(def %zig-zag
  (first (Bytes of-hex "000108100902030a11182019120b04050c131a21283029221b140d06070e151c232a313839322b241d160f171e252c333a3b342d261f272e353c3d362f373e3f")))
(def %natural (fn (_ k) (%u8 (str->ptr %zig-zag) k)))

; --- Bits -----------------------------------------------------------------

; The entropy-coded data's reader, in word slots: 0 the offset of the next
; byte, 1 the bits on hand, 2 how many, 3 1 once a marker is reached (from
; there it answers zeros, as libjpeg does), 4 the end of the data.
(def %fill!
  (fn (self p st)
    (when (int< (%w st 2) 25)
      (do
        (def i (%w st 0))
        (def b
          (match
            ((int= (%w st 3) 1) 0)
            ((not (int< i (%w st 4))) (do (%w! st 3 1) 0))
            ((not (int= (%u8 p i) 255)) (do (%w! st 0 (int+ i 1)) (%u8 p i)))
            ((match ((int< (int+ i 1) (%w st 4)) (int= (%u8 p (int+ i 1)) 0)) (#t #f))
              (do (%w! st 0 (int+ i 2)) 255))
            (#t (do (%w! st 3 1) 0))))
        (%w! st 1 (int| (int<< (%w st 1) 8) b))
        (%w! st 2 (int+ (%w st 2) 8))
        (self p st)))))

; The next K bits, most significant first.
(def %bits
  (fn (_ p st k)
    (if (int= k 0) 0
      (do
        (%fill! p st)
        (def n (int- (%w st 2) k))
        (def v (int& (int>> (%w st 1) n) (int- (int<< 1 k) 1)))
        (%w! st 1 (int& (%w st 1) (int- (int<< 1 n) 1)))
        (%w! st 2 n)
        v))))

; K bits read as a coefficient: the high half positive, the low negative.
(def %extend
  (fn (_ v k)
    (if (int< v (int<< 1 (int- k 1))) (int+ (int- v (int<< 1 k)) 1) v)))

; --- Huffman tables -------------------------------------------------------

; A table in a buffer of 54 words and 256 bytes: words 0-17 the largest
; code of each length (-1 for none), 18-35 the smallest, 36-53 where that
; length's values start; then the values.  Eight tables: DC 0-3, AC 4-7.
(def %table-size 688)

(def %huff-build!
  (fn (_ t counts p vals total)
    ((fn (self l code k)
       (when (int< l 17)
         (do
           (def n (%u8 counts (int- l 1)))
           (%w! t (int+ 18 l) code)
           (%w! t (int+ 36 l) k)
           (%w! t l (if (int= n 0) -1 (int- (int+ code n) 1)))
           (self (int+ l 1) (int<< (int+ code n) 1) (int+ k n)))))
     1 0 0)
    (%w! t 17 -1)
    ((fn (self i) (when (int< i total) (do (ptr-set! t (int+ 432 i) (%u8 p (int+ vals i)) 1) (self (int+ i 1))))) 0)))

(def %decode-huff
  (fn (_ p st t)
    ((fn (self code l)
       (match
         ((int< 16 l) (%fail "the data holds a Huffman code no table defines"))
         ((int< (%w t l) code)
           (self (int| (int<< code 1) (%bits p st 1)) (int+ l 1)))
         (#t (%u8 t (int+ 432 (int+ (%w t (int+ 36 l)) (int- code (%w t (int+ 18 l)))))))))
     (%bits p st 1) 1)))

; --- Inverse DCT ----------------------------------------------------------

; libjpeg's jpeg_idct_islow: the 64 dequantized coefficients C, in natural
; order, to an 8 x 8 block of samples at OUT, STRIDE bytes a row.  W is 64
; words of workspace.
(def %descale (fn (_ x n) (int>> (int+ x (int<< 1 (int- n 1))) n)))
(def %range (fn (_ x) (do (def r (int& x 1023)) (%clamp (int+ 128 (if (int< r 512) r (int- r 1024)))))))

(def %idct-column!
  (fn (_ c w k)
    (def at (fn (_ r) (%w c (int+ k (int<< r 3)))))
    (def put! (fn (_ r v) (%w! w (int+ k (int<< r 3)) v)))
    (if (%ac-zero? at)
      ((fn (self r v) (when (int< r 8) (do (put! r v) (self (int+ r 1) v)))) 0 (int<< (at 0) 2))
      (do
        (def z1 (int* (int+ (at 2) (at 6)) 4433))
        (def t2 (int+ z1 (int* (at 6) -15137)))
        (def t3 (int+ z1 (int* (at 2) 6270)))
        (def t0 (int<< (int+ (at 0) (at 4)) 13))
        (def t1 (int<< (int- (at 0) (at 4)) 13))
        (def t10 (int+ t0 t3))
        (def t13 (int- t0 t3))
        (def t11 (int+ t1 t2))
        (def t12 (int- t1 t2))
        (def odd (%idct-odd (at 7) (at 5) (at 3) (at 1)))
        (put! 0 (%descale (int+ t10 (List ref 3 odd)) 11))
        (put! 7 (%descale (int- t10 (List ref 3 odd)) 11))
        (put! 1 (%descale (int+ t11 (List ref 2 odd)) 11))
        (put! 6 (%descale (int- t11 (List ref 2 odd)) 11))
        (put! 2 (%descale (int+ t12 (List ref 1 odd)) 11))
        (put! 5 (%descale (int- t12 (List ref 1 odd)) 11))
        (put! 3 (%descale (int+ t13 (first odd)) 11))
        (put! 4 (%descale (int- t13 (first odd)) 11))))))

; The odd part of either pass from inputs 7, 5, 3 and 1: (TMP0 TMP1 TMP2 TMP3).
(def %idct-odd
  (fn (_ a b c d)
    (def z5 (int* (int+ (int+ a c) (int+ b d)) 9633))
    (def z1 (int* (int+ a d) -7373))
    (def z2 (int* (int+ b c) -20995))
    (def z3 (int+ (int* (int+ a c) -16069) z5))
    (def z4 (int+ (int* (int+ b d) -3196) z5))
    (list (int+ (int* a 2446) (int+ z1 z3))
          (int+ (int* b 16819) (int+ z2 z4))
          (int+ (int* c 25172) (int+ z2 z3))
          (int+ (int* d 12299) (int+ z1 z4)))))

(def %idct-row!
  (fn (_ w k out stride)
    (def at (fn (_ i) (%w w (int+ (int<< k 3) i))))
    (def o (int* k stride))
    (def put! (fn (_ i v) (ptr-set! out (int+ o i) v 1)))
    (if (%ac-zero? at)
      ((fn (self i v) (when (int< i 8) (do (put! i v) (self (int+ i 1) v)))) 0 (%range (%descale (at 0) 5)))
      (do
        (def z1 (int* (int+ (at 2) (at 6)) 4433))
        (def t2 (int+ z1 (int* (at 6) -15137)))
        (def t3 (int+ z1 (int* (at 2) 6270)))
        (def t0 (int<< (int+ (at 0) (at 4)) 13))
        (def t1 (int<< (int- (at 0) (at 4)) 13))
        (def t10 (int+ t0 t3))
        (def t13 (int- t0 t3))
        (def t11 (int+ t1 t2))
        (def t12 (int- t1 t2))
        (def odd (%idct-odd (at 7) (at 5) (at 3) (at 1)))
        (put! 0 (%range (%descale (int+ t10 (List ref 3 odd)) 18)))
        (put! 7 (%range (%descale (int- t10 (List ref 3 odd)) 18)))
        (put! 1 (%range (%descale (int+ t11 (List ref 2 odd)) 18)))
        (put! 6 (%range (%descale (int- t11 (List ref 2 odd)) 18)))
        (put! 2 (%range (%descale (int+ t12 (List ref 1 odd)) 18)))
        (put! 5 (%range (%descale (int- t12 (List ref 1 odd)) 18)))
        (put! 3 (%range (%descale (int+ t13 (first odd)) 18)))
        (put! 4 (%range (%descale (int- t13 (first odd)) 18)))))))

(def %idct!
  (fn (_ c w out stride)
    ((fn (self k) (when (int< k 8) (do (%idct-column! c w k) (self (int+ k 1))))) 0)
    ((fn (self k) (when (int< k 8) (do (%idct-row! w k out stride) (self (int+ k 1))))) 0)))

; --- Frame and scans ------------------------------------------------------

; A component in 12 word slots of the frame's buffer FR, at 16 + 12 x I:
; 0 its id, 1 H, 2 V, 3 its quantization table, 4 its plane, 5 the plane's
; width, 6 its height, 7 the DC before, 8 its DC table, 9 its AC table,
; 10 its width in samples, 11 its height.  FR words 0-15: 0 the width,
; 1 the height, 2 the component count, 3 the largest H, 4 the largest V,
; 5 MCUs across, 6 MCUs down, 7 the restart interval, 8 1 once a frame is
; read, 9 1 for a JFIF marker, 10 the Adobe transform or -1.
(def %comp (fn (_ i) (int+ 16 (int* 12 i))))
(def %cw (fn (_ fr i f) (%w fr (int+ (%comp i) f))))
(def %cw! (fn (_ fr i f v) (%w! fr (int+ (%comp i) f) v)))

(def %frame!
  (fn (_ p i len fr planes)
    (when (int= (%w fr 8) 1) (%fail "a second frame"))
    (%need i 8 len)
    (unless (int= (%u8 p i) 8) (%fail "a sample precision other than 8 bits"))
    (def h (%u16 p (int+ i 1)))
    (def w (%u16 p (int+ i 3)))
    (def n (%u8 p (int+ i 5)))
    (when (match ((int= w 0) #t) ((int= h 0) #t) (#t #f)) (%fail "a frame with no size (DNL is not read)"))
    (unless (match ((int= n 1) #t) ((int= n 3) #t) (#t #f)) (%fail "a component count other than 1 or 3"))
    (%need (int+ i 6) (int* n 3) len)
    (%w! fr 0 w) (%w! fr 1 h) (%w! fr 2 n) (%w! fr 8 1)
    ((fn (self k hm vm)
       (if (int< k n)
         (do
           (def at (int+ (int+ i 6) (int* k 3)))
           (def hv (%u8 p (int+ at 1)))
           (def hk (int>> hv 4))
           (def vk (int& hv 15))
           (when (match ((int< hk 1) #t) ((int< 4 hk) #t) ((int< vk 1) #t) ((int< 4 vk) #t) (#t #f))
             (%fail "a sampling factor outside 1 to 4"))
           (when (int< 3 (%u8 p (int+ at 2))) (%fail "a quantization table number past 3"))
           (%cw! fr k 0 (%u8 p at)) (%cw! fr k 1 hk) (%cw! fr k 2 vk) (%cw! fr k 3 (%u8 p (int+ at 2)))
           (self (int+ k 1) (if (int< hm hk) hk hm) (if (int< vm vk) vk vm)))
         (do (%w! fr 3 hm) (%w! fr 4 vm))))
     0 1 1)
    (%w! fr 5 (%div-up w (int<< (%w fr 3) 3)))
    (%w! fr 6 (%div-up h (int<< (%w fr 4) 3)))
    ((fn (self k acc)
       (if (int< k n)
         (do
           (def pw (int<< (int* (%w fr 5) (%cw fr k 1)) 3))
           (def ph (int<< (int* (%w fr 6) (%cw fr k 2)) 3))
           (def plane (first (Bytes zeros (int* pw ph))))
           (%cw! fr k 4 (ptr->int (str->ptr plane)))
           (%cw! fr k 5 pw)
           (%cw! fr k 6 ph)
           (%cw! fr k 10 (%div-up (int* w (%cw fr k 1)) (%w fr 3)))
           (%cw! fr k 11 (%div-up (int* h (%cw fr k 2)) (%w fr 4)))
           (self (int+ k 1) (pair plane acc)))
         acc))
     0 planes)))


; One block of component K at block column BX, row BY: its coefficients
; decoded, dequantized and put through the inverse DCT into its plane.
(def %block!
  (fn (_ p st fr k bx by qt ht c w)
    (def q (%at qt (int<< (%cw fr k 3) 9)))
    ((fn (self i) (when (int< i 64) (do (%w! c i 0) (self (int+ i 1))))) 0)
    (def s (%decode-huff p st (%at ht (int* (%cw fr k 8) %table-size))))
    (def dc (int+ (%cw fr k 7) (if (int= s 0) 0 (%extend (%bits p st s) s))))
    (%cw! fr k 7 dc)
    (%w! c 0 (int* dc (%w q 0)))
    (def ac (%at ht (int* (int+ 4 (%cw fr k 9)) %table-size)))
    ((fn (self i)
       (when (int< i 64)
         ((fn (_ rs)
            (def r (int>> rs 4))
            (def z (int& rs 15))
            (match
              ((not (int= z 0))
                (do (def j (int+ i r))
                    (def at (if (int< 63 j) 63 (%natural j)))
                    (%w! c at (int* (%extend (%bits p st z) z) (%w q at)))
                    (self (int+ j 1))))
              ((int= r 15) (self (int+ i 16)))
              (#t ())))
          (%decode-huff p st ac))))
     1)
    (def stride (%cw fr k 5))
    (%idct! c w (%at (int->ptr (%cw fr k 4)) (int+ (int* (int<< by 3) stride) (int<< bx 3))) stride)))

; A restart: the bits on hand dropped, an RSTn passed over, each
; component's DC back to 0.
(def %restart!
  (fn (_ p st fr ks)
    (%w! st 1 0) (%w! st 2 0) (%w! st 3 0)
    ((fn (self i)
       (match
         ((not (int< (int+ i 1) (%w st 4))) (%w! st 0 i))
         ((match ((int= (%u8 p i) 255) (match ((int< 207 (%u8 p (int+ i 1))) (int< (%u8 p (int+ i 1)) 216)) (#t #f))) (#t #f))
           (%w! st 0 (int+ i 2)))
         (#t (self (int+ i 1)))))
     (%w st 0))
    (List for-each (fn (_ k) (%cw! fr k 7 0)) ks)))

; The scan whose header is at I: its data decoded.  Answers the offset of
; the marker after it.
(def %scan!
  (fn (_ p i len fr qt ht)
    (unless (int= (%w fr 8) 1) (%fail "a scan before the frame"))
    (%need i 1 len)
    (def n (%u8 p i))
    (when (match ((int< n 1) #t) ((int< 4 n) #t) (#t #f)) (%fail "a scan of no components or more than four"))
    (%need (int+ i 1) (int+ (int* n 2) 3) len)
    (def ks
      ((fn (self j acc)
         (if (int< j 0) acc
           (do
             (def at (int+ (int+ i 1) (int* j 2)))
             (def id (%u8 p at))
             (def k ((fn (find k) (match ((int< k (%w fr 2)) (if (int= (%cw fr k 0) id) k (find (int+ k 1)))) (#t (%fail "a scan names a component the frame has not"))))
                     0))
             (def tables (%u8 p (int+ at 1)))
             (when (match ((int< 3 (int>> tables 4)) #t) ((int< 3 (int& tables 15)) #t) (#t #f)) (%fail "a Huffman table number past 3"))
             (%cw! fr k 8 (int>> tables 4))
             (%cw! fr k 9 (int& tables 15))
             (%cw! fr k 7 0)
             (self (int- j 1) (pair k acc)))))
       (int- n 1) ()))
    (def st-buf (%buf 40))
    (def st (str->ptr st-buf))
    (%w! st 0 (int+ (int+ i 1) (int+ (int* n 2) 3)))
    (%w! st 4 len)
    (def c-buf (%buf 512))
    (def c (str->ptr c-buf))
    (def w-buf (%buf 512))
    (def w (str->ptr w-buf))
    (def ri (%w fr 7))
    (def step!
      (fn (_ m)
        (when (match ((int< 0 ri) (match ((int< 0 m) (int= 0 (int- m (int* ri (int/ m ri))))) (#t #f))) (#t #f))
          (%restart! p st fr ks))))
    (if (int= n 1)
      (do
        (def k (first ks))
        (def across (%div-up (%cw fr k 10) 8))
        (def down (%div-up (%cw fr k 11) 8))
        ((fn (self m)
           (when (int< m (int* across down))
             (do (step! m) (%tidy m)
                 (%block! p st fr k (int- m (int* across (int/ m across))) (int/ m across) qt ht c w)
                 (self (int+ m 1)))))
         0))
      (do
        (def across (%w fr 5))
        ((fn (self m)
           (when (int< m (int* across (%w fr 6)))
             (do
               (step! m) (%tidy m)
               (def mx (int- m (int* across (int/ m across))))
               (def my (int/ m across))
               (List for-each
                 (fn (_ k)
                   (def hk (%cw fr k 1))
                   (def vk (%cw fr k 2))
                   ((fn (rows v)
                      (when (int< v vk)
                        (do ((fn (cols h)
                               (when (int< h hk)
                                 (do (%block! p st fr k (int+ (int* mx hk) h) (int+ (int* my vk) v) qt ht c w)
                                     (cols (int+ h 1)))))
                             0)
                            (rows (int+ v 1)))))
                    0))
                 ks)
               (self (int+ m 1)))))
         0)))
    ; The next marker: past the data and any RSTn left in it.
    ((fn (self j)
       (match
         ((not (int< (int+ j 1) len)) j)
         ((match ((int= (%u8 p j) 255) (match ((int= (%u8 p (int+ j 1)) 0) #f) ((int= (%u8 p (int+ j 1)) 255) #f) ((match ((int< 207 (%u8 p (int+ j 1))) (int< (%u8 p (int+ j 1)) 216)) (#t #f)) #f) (#t #t))) (#t #f)) j)
         (#t (self (int+ j 1)))))
     (%w st 0))))

; --- Colour ---------------------------------------------------------------

; Component K at full size, X x Y bytes a row of W: its plane upsampled as
; libjpeg's jdsample.c does by default.
(def %full
  (fn (_ fr k)
    (def w (%w fr 0))
    (def h (%w fr 1))
    (def src (int->ptr (%cw fr k 4)))
    (def stride (%cw fr k 5))
    (def dw (%cw fr k 10))
    (def dh (%cw fr k 11))
    (def fh (int/ (%w fr 3) (%cw fr k 1)))
    (def fv (int/ (%w fr 4) (%cw fr k 2)))
    (when (match ((not (int= (%w fr 3) (int* fh (%cw fr k 1)))) #t) ((not (int= (%w fr 4) (int* fv (%cw fr k 2)))) #t) (#t #f))
      (%fail "sampling factors that do not divide the largest"))
    (if (match ((int= fh 1) (int= fv 1)) (#t #f)) (list src stride)
      (do
        (def ow (int* dw fh))
        (def out-buf (%buf (int* ow (int* dh fv))))
        (def out (str->ptr out-buf))
        (def in (fn (_ r c) (%u8 src (int+ (int* (match ((int< r 0) 0) ((int< r dh) r) (#t (int- dh 1))) stride) c))))
        (def put! (fn (_ r c v) (ptr-set! out (int+ (int* r ow) c) v 1)))
        (match
          ((match ((int= fh 2) (match ((int= fv 1) (int< 2 dw)) (#t #f))) (#t #f))
            ((fn (rows r)
               (when (int< r dh)
                 (do
                   (put! r 0 (in r 0))
                   (put! r 1 (int>> (int+ (int+ (int* (in r 0) 3) (in r 1)) 2) 2))
                   ((fn (cols c)
                      (when (int< c (int- dw 1))
                        (do (put! r (int<< c 1) (int>> (int+ (int+ (int* (in r c) 3) (in r (int- c 1))) 1) 2))
                            (put! r (int+ (int<< c 1) 1) (int>> (int+ (int+ (int* (in r c) 3) (in r (int+ c 1))) 2) 2))
                            (cols (int+ c 1)))))
                    1)
                   (put! r (int- (int<< dw 1) 2) (int>> (int+ (int+ (int* (in r (int- dw 1)) 3) (in r (int- dw 2))) 1) 2))
                   (put! r (int- (int<< dw 1) 1) (in r (int- dw 1)))
                   (do (%tidy r) (rows (int+ r 1))))))
             0))
          ((match ((int= fh 2) (match ((int= fv 2) (int< 2 dw)) (#t #f))) (#t #f))
            ((fn (rows o)
               (when (int< o (int<< dh 1))
                 (do
                   (def r (int>> o 1))
                   (def r1 (if (int= (int& o 1) 0) (int- r 1) (int+ r 1)))
                   (def sum (fn (_ c) (int+ (int* (in r c) 3) (in r1 c))))
                   (put! o 0 (int>> (int+ (int* (sum 0) 4) 8) 4))
                   (put! o 1 (int>> (int+ (int+ (int* (sum 0) 3) (sum 1)) 7) 4))
                   ((fn (cols c)
                      (when (int< c (int- dw 1))
                        (do (put! o (int<< c 1) (int>> (int+ (int+ (int* (sum c) 3) (sum (int- c 1))) 8) 4))
                            (put! o (int+ (int<< c 1) 1) (int>> (int+ (int+ (int* (sum c) 3) (sum (int+ c 1))) 7) 4))
                            (cols (int+ c 1)))))
                    1)
                   (put! o (int- (int<< dw 1) 2) (int>> (int+ (int+ (int* (sum (int- dw 1)) 3) (sum (int- dw 2))) 8) 4))
                   (put! o (int- (int<< dw 1) 1) (int>> (int+ (int* (sum (int- dw 1)) 4) 7) 4))
                   (do (%tidy o) (rows (int+ o 1))))))
             0))
          ((match ((int= fh 1) (int= fv 2)) (#t #f))
            ((fn (rows o)
               (when (int< o (int<< dh 1))
                 (do
                   (def r (int>> o 1))
                   (def up (int= (int& o 1) 0))
                   (def r1 (if up (int- r 1) (int+ r 1)))
                   ((fn (cols c)
                      (when (int< c dw)
                        (do (put! o c (int>> (int+ (int+ (int* (in r c) 3) (in r1 c)) (if up 1 2)) 2))
                            (cols (int+ c 1)))))
                    0)
                   (do (%tidy o) (rows (int+ o 1))))))
             0))
          (#t
            ((fn (rows o)
               (when (int< o (int* dh fv))
                 (do
                   ((fn (cols c)
                      (when (int< c ow)
                        (do (put! o c (in (int/ o fv) (int/ c fh))) (cols (int+ c 1)))))
                    0)
                   (do (%tidy o) (rows (int+ o 1))))))
             0)))
        (list out ow out-buf)))))

; jdcolor.c's tables, as the sums they make: FIX(1.402), FIX(1.772),
; FIX(0.71414) and FIX(0.34414) at 16 bits.
(def %ycc
  (fn (_ y cb cr)
    (def b (int- cb 128))
    (def r (int- cr 128))
    (list (%clamp (int+ y (int>> (int+ (int* 91881 r) 32768) 16)))
          (%clamp (int+ y (int>> (int+ (int* -22554 b) (int+ (int* -46802 r) 32768)) 16)))
          (%clamp (int+ y (int>> (int+ (int* 116130 b) 32768) 16))))))

(def %pixels
  (fn (_ fr)
    (def w (%w fr 0))
    (def h (%w fr 1))
    (def n (%w fr 2))
    (def out (first (Bytes zeros (int* (int* w h) 4))))
    (def o (str->ptr out))
    (def planes ((fn (self k) (if (int< k n) (pair (%full fr k) (self (int+ k 1))) ())) 0))
    (def at (fn (_ pl x y) (%u8 (first pl) (int+ (int* y (List ref 1 pl)) x))))
    (def rgb?
      (match ((int= n 1) #f)
             ((int= (%w fr 9) 1) #f)
             ((int= (%w fr 10) 0) #t)
             ((int< -1 (%w fr 10)) #f)
             (#t (match ((int= (%cw fr 0 0) 82) (match ((int= (%cw fr 1 0) 71) (int= (%cw fr 2 0) 66)) (#t #f))) (#t #f)))))
    ((fn (rows y)
       (when (int< y h)
         (do
           ((fn (cols x)
              (when (int< x w)
                (do
                  (def d (int<< (int+ (int* y w) x) 2))
                  (def px
                    (match ((int= n 1) (do (def g (at (first planes) x y)) (list g g g)))
                           (rgb? (list (at (first planes) x y) (at (List ref 1 planes) x y) (at (List ref 2 planes) x y)))
                           (#t (%ycc (at (first planes) x y) (at (List ref 1 planes) x y) (at (List ref 2 planes) x y)))))
                  (ptr-set! o d (first px) 1)
                  (ptr-set! o (int+ d 1) (List ref 1 px) 1)
                  (ptr-set! o (int+ d 2) (List ref 2 px) 1)
                  (ptr-set! o (int+ d 3) 255 1)
                  (cols (int+ x 1)))))
            0)
           (do (%tidy y) (rows (int+ y 1))))))
     0)
    (list w h out)))

; --- Markers --------------------------------------------------------------

; Whether the bytes at I are CODES: an APP marker's name.
(def %tag? (fn (_ p i codes) ((fn (self i cs) (match ((null? cs) #t) ((int= (%u8 p i) (first cs)) (self (int+ i 1) (rest cs))) (#t #f))) i codes)))

(def %signed? (fn (_ p len) (match ((int< len 4) #f) ((int= (%u8 p 0) 255) (int= (%u8 p 1) 216)) (#t #f))))

(def %unsupported
  (fn (_ m)
    (match ((int= m 194) "a progressive JPEG is not decoded yet")
           ((int= m 195) "a lossless JPEG is not decoded")
           ((int< 200 m) "an arithmetic-coded JPEG is not decoded")
           ((int= m 200) "a JPEG extension frame is not decoded")
           (#t "a hierarchical JPEG is not decoded"))))

(def %tables!
  (fn (_ p i end qt ht m)
    ((fn (self i)
       (when (int< i end)
         (match
           ((int= m 219)
             (do
               (def pq (int>> (%u8 p i) 4))
               (def tq (int& (%u8 p i) 15))
               (when (int< 3 tq) (%fail "a quantization table number past 3"))
               (when (int< 1 pq) (%fail "a quantization table precision past 16 bits"))
               (%need (int+ i 1) (int<< 64 pq) end)
               (def q (%at qt (int<< tq 9)))
               ((fn (fill k)
                  (when (int< k 64)
                    (do (%w! q (%natural k)
                             (if (int= pq 0) (%u8 p (int+ (int+ i 1) k)) (%u16 p (int+ (int+ i 1) (int<< k 1)))))
                        (fill (int+ k 1)))))
                0)
               (self (int+ (int+ i 1) (int<< 64 pq)))))
           (#t
             (do
               (%need i 17 end)
               (def tc (int>> (%u8 p i) 4))
               (def th (int& (%u8 p i) 15))
               (when (match ((int< 1 tc) #t) ((int< 3 th) #t) (#t #f)) (%fail "a Huffman table class or number out of range"))
               (def total ((fn (sum l acc) (if (int< l 16) (sum (int+ l 1) (int+ acc (%u8 p (int+ (int+ i 1) l)))) acc)) 0 0))
               (when (int< 256 total) (%fail "a Huffman table of more than 256 values"))
               (%need (int+ i 17) total end)
               (%huff-build! (%at ht (int* (int+ (int<< tc 2) th) %table-size)) (%at p (int+ i 1)) p (int+ i 17) total)
               (self (int+ (int+ i 17) total)))))))
     i)))

(def %decode
  (fn (_ s start len)
    (def p (%at (str->ptr s) start))
    (unless (%signed? p len) (%fail "not a JPEG: no SOI marker"))
    (def fr-buf (%buf (int<< (%comp 4) 3)))
    (def fr (str->ptr fr-buf))
    (%w! fr 10 -1)
    (def qt-buf (%buf (int<< 4 9)))
    (def qt (str->ptr qt-buf))
    (def ht-buf (%buf (int* 8 %table-size)))
    (def ht (str->ptr ht-buf))
    ((fn (self i planes)
       (%need i 2 len)
       (unless (int= (%u8 p i) 255) (%fail "a marker was expected"))
       (def m (%u8 p (int+ i 1)))
       (match
         ((int= m 255) (self (int+ i 1) planes))
         ((int= m 217) (if (int= (%w fr 8) 1) (%pixels fr) (%fail "no frame before EOI")))
         ((match ((int< 207 m) (int< m 216)) (#t #f)) (self (int+ i 2) planes))
         (#t
           (do
             (%need i 4 len)
             (def l (%u16 p (int+ i 2)))
             (when (int< l 2) (%fail "a segment length under 2"))
             (def body (int+ i 4))
             (def next (int+ (int+ i 2) l))
             (%need (int+ i 2) l len)
             (match
               ((match ((int= m 192) #t) ((int= m 193) #t) (#t #f)) (self next (%frame! p body len fr planes)))
               ((match ((int= m 196) #f) ((int= m 204) #f) ((int< 191 m) (int< m 208)) (#t #f)) (%fail (%unsupported m)))
               ((int= m 204) (%fail "an arithmetic-coded JPEG is not decoded"))
               ((match ((int= m 196) #t) ((int= m 219) #t) (#t #f)) (do (%tables! p body next qt ht m) (self next planes)))
               ((int= m 221) (do (%need body 2 len) (%w! fr 7 (%u16 p body)) (self next planes)))
               ((int= m 218) (self (%scan! p body len fr qt ht) planes))
               ((int= m 224)
                 (do (when (match ((int< 15 l) (%tag? p body (list 74 70 73 70 0))) (#t #f)) (%w! fr 9 1))
                     (self next planes)))
               ((int= m 238)
                 (do (when (match ((int< 13 l) (%tag? p body (list 65 100 111 98 101))) (#t #f)) (%w! fr 10 (%u8 p (int+ body 11))))
                     (self next planes)))
               (#t (self next planes)))))))
     2 ())))

; The frame header's size, without decoding.
(def %size
  (fn (_ s start len)
    (def p (%at (str->ptr s) start))
    (unless (%signed? p len) (%fail "not a JPEG: no SOI marker"))
    ((fn (self i)
       (%need i 4 len)
       (unless (int= (%u8 p i) 255) (%fail "a marker was expected"))
       (def m (%u8 p (int+ i 1)))
       (match
         ((int= m 255) (self (int+ i 1)))
         ((match ((int< 207 m) (int< m 219)) (#t #f)) (%fail "no frame header"))
         ((match ((int= m 196) #f) ((int= m 200) #f) ((int= m 204) #f) ((int< 191 m) (int< m 208)) (#t #f))
           (do (%need i 9 len) (list (%u16 p (int+ i 7)) (%u16 p (int+ i 5)))))
         (#t (self (int+ (int+ i 2) (%u16 p (int+ i 2)))))))
     2)))

(def-class Jpeg ()
  (doc "Baseline JPEG images decoded to RGBA in pure x-lang, pixel for pixel as libjpeg decodes them by default: grey, YCbCr or RGB, any sampling, restart intervals."
    (example "(do (import x/codec/bytes) (def r (Bytes of-hex \"ffd8ffe000104a46494600010100000100010000ffdb004300100b0c0e0c0a100e0d0e1211101318281a181616183123251d283a333d3c3933383740485c4e404457453738506d51575f626768673e4d71797064785c656763ffc0000b080008000801011100ffc40014000100000000000000000000000000000005ffc40014100100000000000000000000000000000000ffda0008010100003f003dffd9\")) (Jpeg size (first r) 0 (List ref 2 r)))" "(8 8)")
    (see decode))
  (static
    (method size (self (param s STRING "Bytes holding a JPEG")
                       . (param span INTEGER "START, then LENGTH: which bytes of s; default all of s"))
      (doc "The width and height from the frame header, without decoding; a progressive image's too. Give LENGTH for a JPEG held in a buffer: s's own length is measured to its first NUL. Raises a label 'value when the bytes are not a JPEG."
        (returns LIST "(WIDTH HEIGHT)")
        (example "(do (import x/codec/bytes) (def r (Bytes of-hex \"ffd8ffe000104a46494600010100000100010000ffdb004300100b0c0e0c0a100e0d0e1211101318281a181616183123251d283a333d3c3933383740485c4e404457453738506d51575f626768673e4d71797064785c656763ffc0000b080008000801011100ffc40014000100000000000000000000000000000005ffc40014100100000000000000000000000000000000ffda0008010100003f003dffd9\")) (Jpeg size (first r) 0 (List ref 2 r)))" "(8 8)"))
      (def sp (%span s span))
      (%size s (first sp) (first (rest sp))))
    (method decode (self (param s STRING "Bytes holding a JPEG")
                         . (param span INTEGER "START, then LENGTH, as for size"))
      (doc "Decode a baseline or extended sequential JPEG of 8-bit samples, one component or three, to RGBA at 8 bits a sample, alpha 255. Raises a label 'value naming what is wrong with a malformed image, or which kind of JPEG this does not decode."
        (returns LIST "(WIDTH HEIGHT RGBA): RGBA a buffer of WIDTH x HEIGHT x 4 bytes, rows top to bottom")
        (example "(do (import x/codec/bytes) (def r (Bytes of-hex \"ffd8ffe000104a46494600010100000100010000ffdb004300100b0c0e0c0a100e0d0e1211101318281a181616183123251d283a333d3c3933383740485c4e404457453738506d51575f626768673e4d71797064785c656763ffc0000b080008000801011100ffc40014000100000000000000000000000000000005ffc40014100100000000000000000000000000000000ffda0008010100003f003dffd9\")) (def d (Jpeg decode (first r) 0 (List ref 2 r))) (Bytes hex (list (List ref 2 d) 0 8)))" "\"606060ff606060ff\""))
      (def sp (%span s span))
      (%decode s (first sp) (first (rest sp))))))

(doc (provide x/codec/jpeg Jpeg)
  (example "(do (import x/codec/bytes) (let ((r (Bytes of-hex \"ffd8ffe000104a46494600010100000100010000ffdb004300100b0c0e0c0a100e0d0e1211101318281a181616183123251d283a333d3c3933383740485c4e404457453738506d51575f626768673e4d71797064785c656763ffc0000b080008000801011100ffc40014000100000000000000000000000000000005ffc40014100100000000000000000000000000000000ffda0008010100003f003dffd9\"))) (Jpeg size (first r) 0 (List ref 2 r))))" "(8 8)")
  "Baseline JPEG images decoded to RGBA in pure x-lang: (Jpeg decode s) answers (WIDTH HEIGHT RGBA), (Jpeg size s) the size alone.")

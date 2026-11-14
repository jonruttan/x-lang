; gif.x -- Gif: GIF images (GIF87a, GIF89a) decoded to RGBA in pure x-lang.
;
; A GIF is a header, the logical screen (its width, height and an optional
; global colour table), then blocks: extensions led by 0x21, images led by
; 0x2C, and the trailer 0x3B.  An image is a rectangle of the screen with
; an optional colour table of its own and its pixels as colour indexes,
; LZW-compressed and carried in sub-blocks of up to 255 bytes.  A graphic
; control extension before an image names one index of it transparent.
;
; Out comes the first image as the screen shows it, RGBA at 8 bits a
; sample: its indexes looked up in its colour table (the local one, else
; the global one), placed at its offset, interlaced rows put back in
; order.  The screen outside the image, and a transparent index, are
; alpha 0, as a browser shows them: the background colour index is not
; drawn.  An animation's later frames are passed over.  A malformed image
; raises a label 'value naming what was wrong.
(module x/codec/gif)

(import x/core/doors int& int* int+ int- int->ptr int< int<< int= int>> int| ptr->int ptr-ref ptr-set! str->ptr str-byte-len str-make)

(def %fail (fn (_ what) (Err raise (lit value) (Str8 append "Gif: " what) ())))

(def %at (fn (_ p off) (int->ptr (int+ (ptr->int p) off))))
(def %u8 (fn (_ p i) (int& (ptr-ref p i 1) 255)))
(def %u16 (fn (_ p i) (int| (%u8 p i) (int<< (%u8 p (int+ i 1)) 8))))
; Table entries are 16 bits, kept in the machine's order.
(def %ref16 (fn (_ t i) (int& (ptr-ref t (int<< i 1) 2) 65535)))
(def %set16! (fn (_ t i v) (ptr-set! t (int<< i 1) v 2)))

; A buffer of N bytes, each 0: str-make's bytes are not.
(def %zeros
  (fn (_ n)
    (def s (str-make n))
    (def p (str->ptr s))
    ((fn (self i)
       (match ((int< (int+ i 3) n) (do (ptr-set! p i 0 4) (self (int+ i 4))))
              ((int< i n) (do (ptr-set! p i 0 1) (self (int+ i 1))))
              (#t s)))
     0)))

(def %span
  (fn (_ s span)
    (match
      ((null? span) (list 0 (str-byte-len s)))
      ((null? (rest span)) (list (first span) (int- (str-byte-len s) (first span))))
      (#t (list (first span) (first (rest span)))))))

; N more bytes at I, before END, or the file is short.
(def %need (fn (_ i n end) (when (int< end (int+ i n)) (%fail "the file ends early"))))

(def %signed?
  (fn (_ p len)
    (match ((int< len 13) #f)
           ((not (int= (%u8 p 0) 71)) #f)
           ((not (int= (%u8 p 1) 73)) #f)
           ((not (int= (%u8 p 2) 70)) #f)
           ((not (int= (%u8 p 3) 56)) #f)
           ((not (match ((int= (%u8 p 4) 55) #t) ((int= (%u8 p 4) 57) #t) (#t #f))) #f)
           (#t (int= (%u8 p 5) 97)))))

; --- Blocks ---------------------------------------------------------------

; The offset after the sub-blocks starting at I: each a length byte and
; that many bytes, ended by a length of 0.
(def %skip
  (fn (self p i end)
    (%need i 1 end)
    ((fn (_ n) (if (int= n 0) (int+ i 1) (do (%need (int+ i 1) n end) (self p (int+ i (int+ n 1)) end))))
     (%u8 p i))))

; The sub-blocks starting at I joined into one buffer: (BUF LENGTH).
(def %gather
  (fn (_ p i end)
    (def total
      ((fn (self i acc)
         ((fn (_ n) (if (int= n 0) acc (self (int+ i (int+ n 1)) (int+ acc n)))) (%u8 p i)))
       i 0))
    (def buf (%zeros (int+ total 3)))
    (def b (str->ptr buf))
    ((fn (self i o)
       ((fn (_ n)
          (unless (int= n 0)
            (do ((fn (copy k) (when (int< k n) (do (ptr-set! b (int+ o k) (%u8 p (int+ (int+ i 1) k)) 1) (copy (int+ k 1))))) 0)
                (self (int+ i (int+ n 1)) (int+ o n)))))
        (%u8 p i)))
     i 0)
    (list buf total)))

; --- LZW ------------------------------------------------------------------

; The code of WIDTH bits at bit POS of B, LSB first, bytes past the data 0.
(def %code
  (fn (_ b pos width)
    (def i (int>> pos 3))
    (int& (int>> (int| (%u8 b i) (int| (int<< (%u8 b (int+ i 1)) 8) (int<< (%u8 b (int+ i 2)) 16))) (int& pos 7))
          (int- (int<< 1 width) 1))))

; The data's codes decoded into the indexes O, N of them, the code size
; starting at MIN + 1 bits.  A short stream leaves the rest index 0.
(def %lzw
  (fn (_ b bits min o n)
    (def clear (int<< 1 min))
    (def eoi (int+ clear 1))
    (def prefix (str->ptr (str-make 8192)))
    (def suffix (str->ptr (str-make 4096)))
    (def head (str->ptr (str-make 4096)))
    (def stack (str->ptr (str-make 4097)))
    ((fn (init k) (when (int< k clear) (do (ptr-set! suffix k k 1) (ptr-set! head k k 1) (init (int+ k 1))))) 0)
    ; The string of code C written at OP, as much of it as fits: answers
    ; the offset after it.
    (def emit
      (fn (_ c op)
        (def depth
          ((fn (self c d)
             (if (int< c clear) (do (ptr-set! stack d c 1) (int+ d 1))
               (do (ptr-set! stack d (%u8 suffix c) 1) (self (%ref16 prefix c) (int+ d 1)))))
           c 0))
        ((fn (self d op)
           (if (int= d 0) op
             (do (when (int< op n) (ptr-set! o op (%u8 stack (int- d 1)) 1))
                 (self (int- d 1) (int+ op 1)))))
         depth op)))
    ((fn (self pos width next old op)
       (when (match ((int< op n) (int< (int+ pos width) (int+ bits 1))) (#t #f))
         ((fn (_ c)
            (match
              ((int= c clear) (self (int+ pos width) (int+ min 1) (int+ clear 2) -1 op))
              ((int= c eoi) ())
              ((int< old 0)
                (do (unless (int< c clear) (%fail "the image data starts with a code it has not defined"))
                    (self (int+ pos width) width next c (emit c op))))
              ((int< next c) (%fail "the image data holds a code it has not defined"))
              (#t (do
                (def k (%u8 head (if (int= c next) old c)))
                (when (int< next 4096)
                  (do (%set16! prefix next old)
                      (ptr-set! suffix next k 1)
                      (ptr-set! head next (%u8 head old) 1)))
                (def next2 (if (int< next 4096) (int+ next 1) next))
                (def width2 (match ((int< width 12) (if (int= next2 (int<< 1 width)) (int+ width 1) width)) (#t width)))
                (self (int+ pos width) width2 next2 c (emit c op))))))
          (%code b pos width))))
     0 (int+ min 1) (int+ clear 2) -1 0)))

; --- Pixels ---------------------------------------------------------------

; The row of the image that its J-th row of data is, H rows, interlaced or
; not: interlaced data is rows 0, 8, 16 ..., then 4, 12 ..., 2, 6 ..., 1, 3 ...
(def %row
  (fn (_ j h interlaced)
    (if (not interlaced) j
      (do
        (def c0 (int>> (int+ h 7) 3))
        (def c1 (int>> (int+ h 3) 3))
        (def c2 (int>> (int+ h 1) 2))
        (match ((int< j c0) (int<< j 3))
               ((int< j (int+ c0 c1)) (int+ 4 (int<< (int- j c0) 3)))
               ((int< j (int+ (int+ c0 c1) c2)) (int+ 2 (int<< (int- j (int+ c0 c1)) 2)))
               (#t (int+ 1 (int<< (int- j (int+ (int+ c0 c1) c2)) 1))))))))

; The indexes IX of an image FW x FH at LEFT, TOP drawn into OUT, the
; screen W x H, through the colour table at PAL of COUNT entries; the
; index TRANS, and any past the table, left as they are.
(def %draw
  (fn (_ ix fw fh left top interlaced out w h pal count trans)
    (def put!
      (fn (_ v d)
        (do (ptr-set! out d (%u8 pal (int* v 3)) 1)
            (ptr-set! out (int+ d 1) (%u8 pal (int+ (int* v 3) 1)) 1)
            (ptr-set! out (int+ d 2) (%u8 pal (int+ (int* v 3) 2)) 1)
            (ptr-set! out (int+ d 3) 255 1))))
    ((fn (rows j)
       (when (int< j fh)
         (do
           ((fn (_ y)
              (when (int< y h)
                ((fn (cols x)
                   (when (int< x fw)
                     (do
                       ((fn (_ X v)
                          (when (match ((int< X w) (match ((int< v count) (not (int= v trans))) (#t #f))) (#t #f))
                            (put! v (int<< (int+ (int* y w) X) 2))))
                        (int+ left x) (%u8 ix (int+ (int* j fw) x)))
                       (cols (int+ x 1)))))
                 0)))
            (int+ top (%row j fh interlaced)))
           (rows (int+ j 1)))))
     0)))

; The colour table a packed byte P names at I: (OFFSET COUNT), or nil.
(def %table (fn (_ p i) (if (int= (int& p 128) 0) () (list i (int<< 1 (int+ (int& p 7) 1))))))

(def %decode
  (fn (_ s start len)
    (def p (%at (str->ptr s) start))
    (unless (%signed? p len) (%fail "not a GIF: the signature does not match"))
    (def w (%u16 p 6))
    (def h (%u16 p 8))
    (def global (%table (%u8 p 10) 13))
    (def after (if (null? global) 13 (int+ 13 (int* 3 (List ref 1 global)))))
    (%need after 0 len)
    (def out (%zeros (int* (int* w h) 4)))
    ((fn (self i trans)
       (%need i 1 len)
       ((fn (_ kind)
          (match
            ((int= kind 33)
              (do (%need i 2 len)
                  (if (match ((int= (%u8 p (int+ i 1)) 249) (do (%need i 7 len) (int< 3 (%u8 p (int+ i 2))))) (#t #f))
                    (self (%skip p (int+ i 2) len)
                          (if (int= (int& (%u8 p (int+ i 3)) 1) 0) -1 (%u8 p (int+ i 6))))
                    (self (%skip p (int+ i 2) len) trans))))
            ((int= kind 44)
              (do
                (%need i 11 len)
                (def left (%u16 p (int+ i 1)))
                (def top (%u16 p (int+ i 3)))
                (def fw (%u16 p (int+ i 5)))
                (def fh (%u16 p (int+ i 7)))
                (def packed (%u8 p (int+ i 9)))
                (def local (%table packed (int+ i 10)))
                (def at (if (null? local) (int+ i 10) (int+ (int+ i 10) (int* 3 (List ref 1 local)))))
                (%need at 2 len)
                (def table (if (null? local) global local))
                (when (null? table) (%fail "an image with no colour table"))
                (def min (%u8 p at))
                (when (match ((int< min 2) #t) ((int< 8 min) #t) (#t #f)) (%fail "an LZW code size outside 2 to 8"))
                (%skip p (int+ at 1) len)
                (def data (%gather p (int+ at 1) len))
                (def ix (str->ptr (%zeros (int+ (int* fw fh) 1))))
                (%lzw (str->ptr (first data)) (int<< (List ref 1 data) 3) min ix (int* fw fh))
                (%draw ix fw fh left top (not (int= (int& packed 64) 0)) (str->ptr out) w h
                       (%at p (first table)) (List ref 1 table) trans)))
            ((int= kind 59) (%fail "no image before the trailer"))
            (#t (%fail "a block that is neither an extension nor an image"))))
        (%u8 p i)))
     after -1)
    (list w h out)))

(def-class Gif ()
  (doc "GIF images decoded to RGBA in pure x-lang: the first image of the file, global and local colour tables, transparency, interlacing."
    (example "(do (def r (Bytes of-hex \"47494638396102000100f00100000000ffffff21f90400000000002c0000000002000100000202440a003b\")) (Gif size (first r) 0 (List ref 2 r)))" "(2 1)")
    (see decode))
  (static
    (method size (self (param s STRING "Bytes holding a GIF")
                       . (param span LIST "START, then LENGTH: which bytes of s; default all of s"))
      (doc "The logical screen's width and height, from the header, without decoding. Give LENGTH for a GIF held in a buffer: s's own length is measured to its first NUL. Raises a label 'value when the bytes are not a GIF."
        (returns LIST "(WIDTH HEIGHT)")
        (example "(do (def r (Bytes of-hex \"47494638396102000100f00100000000ffffff21f90400000000002c0000000002000100000202440a003b\")) (Gif size (first r) 0 (List ref 2 r)))" "(2 1)"))
      (def sp (%span s span))
      (def p (%at (str->ptr s) (first sp)))
      (unless (%signed? p (first (rest sp))) (%fail "not a GIF: the signature does not match"))
      (list (%u16 p 6) (%u16 p 8)))
    (method decode (self (param s STRING "Bytes holding a GIF")
                         . (param span LIST "START, then LENGTH, as for size"))
      (doc "Decode the first image to RGBA at 8 bits a sample, the size of the logical screen: the image's indexes looked up in its colour table and placed at its offset, interlaced rows put in order. The screen outside the image and a transparent index are alpha 0; later frames are passed over. Raises a label 'value naming what is wrong with a malformed image."
        (returns LIST "(WIDTH HEIGHT RGBA): RGBA a buffer of WIDTH x HEIGHT x 4 bytes, rows top to bottom")
        (example "(do (def r (Bytes of-hex \"47494638396102000100f00100000000ffffff21f90400000000002c0000000002000100000202440a003b\")) (def d (Gif decode (first r) 0 (List ref 2 r))) (Bytes hex (list (List ref 2 d) 0 8)))" "\"000000ffffffffff\""))
      (def sp (%span s span))
      (%decode s (first sp) (first (rest sp))))))

(doc (provide x/codec/gif Gif)
  (example "(let ((r (Bytes of-hex \"47494638396102000100f00100000000ffffff21f90400000000002c0000000002000100000202440a003b\"))) (Gif size (first r) 0 (List ref 2 r)))" "(2 1)")
  "GIF images decoded to RGBA in pure x-lang: (Gif decode s) answers the first image as (WIDTH HEIGHT RGBA), (Gif size s) the size alone.")

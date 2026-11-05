; png.x -- Png: PNG images (RFC 2083, ISO 15948) decoded to RGBA in pure x-lang.
;
; A PNG is a signature and then chunks, each a length, a type, its data and
; a CRC-32 of the type and data.  IHDR gives the size and how a pixel is
; kept: grey, RGB, a palette index, grey with alpha or RGBA, at 1 to 16
; bits a sample.  The IDAT chunks together are one zlib stream (Inflate
; zlib); what it holds is the image a row at a time, each row led by the
; filter its bytes were written through, and an interlaced image is seven
; such images of the Adam7 passes one after another.  PLTE is the palette,
; tRNS the transparency of a palette entry or of one grey or RGB value.
; Every other chunk is metadata to a decoder that answers pixels: an
; ancillary one is passed over, a critical one this does not know raises.
;
; Out comes RGBA at 8 bits a sample, whatever went in: grey spread to three
; samples, a sample under 8 bits scaled to 0-255, a 16-bit sample cut to
; its high byte, a palette index looked up, alpha 255 where the image has
; none.  The filters are undone in place in the inflated buffer, a row at a
; time against the row above it.  Pure INT on the C bit ops through the int
; doors, as the other codecs are, with a compiled engine for the row loops
; of a large image (x/codec/png-jit).  A malformed image raises a label
; 'value naming what was wrong.
(module x/codec/png)

(import x/codec/inflate Inflate)
(import x/codec/crc32 Crc32)
; The compiled engine is on Compiled's list.
(import x/tool/compiled)

(import x/core/doors int& int* int+ int- int->ptr int/ int< int<< int= int>> int| mem-copy ptr->int ptr-ref ptr-set! str->ptr str-byte-len str-make)

(def %fail (fn (_ what) (Err raise (lit value) (Str8 append "Png: " what) ())))

(def %at (fn (_ p off) (int->ptr (int+ (ptr->int p) off))))
(def %u8 (fn (_ p i) (int& (ptr-ref p i 1) 255)))
(def %u16 (fn (_ p i) (int| (int<< (%u8 p i) 8) (%u8 p (int+ i 1)))))
(def %u32 (fn (_ p i) (int| (int<< (%u16 p i) 16) (%u16 p (int+ i 2)))))

(def %span
  (fn (_ s span)
    (match
      ((null? span) (list 0 (str-byte-len s)))
      ((null? (rest span)) (list (first span) (int- (str-byte-len s) (first span))))
      (#t (list (first span) (first (rest span)))))))

; --- Chunks ---------------------------------------------------------------

; The eight bytes every PNG starts with.
(def %signature (list 137 80 78 71 13 10 26 10))
(def %signed?
  (fn (self p i l)
    (match ((eq? l ()) #t)
           ((int= (%u8 p i) (first l)) (self p (int+ i 1) (rest l)))
           (#t #f))))

; The chunk types, as their four bytes read big-endian.
(def %IHDR 1229472850)
(def %PLTE 1347179589)
(def %IDAT 1229209940)
(def %IEND 1229278788)
(def %tRNS 1951551059)

; The chunks from offset I of S to END, in order, each (TYPE OFF LEN), OFF
; where its data starts; each one's CRC checked.  Stops after IEND.
(def %chunks
  (fn (self s p i end acc)
    (match
      ((int< end (int+ i 12)) (%fail "the file ends inside a chunk, or before IEND"))
      (#t (do
        (def len (%u32 p i))
        (def type (%u32 p (int+ i 4)))
        (def next (int+ i (int+ len 12)))
        (match ((match ((int< len 0) #t) ((int< end next) #t) (#t #f)) (%fail "a chunk runs past the end of the file"))
               ((not (int= (Crc32 of s (int+ i 4) (int+ len 4)) (%u32 p (int+ i (int+ len 8)))))
                 (%fail "a chunk's CRC does not match its data"))
               ((int= type %IEND) (List reverse (pair (list type (int+ i 8) len) acc)))
               (#t (self s p next end (pair (list type (int+ i 8) len) acc)))))))))

(def %find (fn (self type cs) (match ((eq? cs ()) ()) ((int= (first (first cs)) type) (first cs)) (#t (self type (rest cs))))))
(def %all (fn (_ type cs) (List filter (fn (_ c) (int= (first c) type)) cs)))

; --- The header -----------------------------------------------------------

; Samples a pixel per colour type, and the bit depths each allows.
(def %channels (fn (_ ct) (match ((int= ct 0) 1) ((int= ct 2) 3) ((int= ct 3) 1) ((int= ct 4) 2) (#t 4))))
(def %depths
  (fn (_ ct)
    (match ((int= ct 0) (list 1 2 4 8 16)) ((int= ct 3) (list 1 2 4 8))
           ((match ((int= ct 2) #t) ((int= ct 4) #t) ((int= ct 6) #t) (#t #f)) (list 8 16))
           (#t ()))))

; IHDR's fields as (W H DEPTH COLOUR-TYPE INTERLACE), checked.
(def %header
  (fn (_ p cs)
    (def c (first cs))
    (unless (match ((eq? c ()) #f) ((int= (first c) %IHDR) (int= (List ref 2 c) 13)) (#t #f))
      (%fail "the first chunk is not a 13-byte IHDR"))
    (def o (List ref 1 c))
    (def w (%u32 p o))
    (def h (%u32 p (int+ o 4)))
    (def depth (%u8 p (int+ o 8)))
    (def ct (%u8 p (int+ o 9)))
    (def il (%u8 p (int+ o 12)))
    (when (match ((int< w 1) #t) ((int< h 1) #t) (#t #f)) (%fail "a width or height of 0"))
    (when (eq? (%depths ct) ()) (%fail "an unknown colour type"))
    (unless (List includes? depth (%depths ct)) (%fail "a bit depth the colour type does not allow"))
    (unless (match ((int= (%u8 p (int+ o 10)) 0) (int= (%u8 p (int+ o 11)) 0)) (#t #f))
      (%fail "an unknown compression or filter method"))
    (unless (int< il 2) (%fail "an unknown interlace method"))
    (list w h depth ct il)))

; A critical chunk -- its type's first letter upper case -- this does not know.
(def %known (list %IHDR %PLTE %IDAT %IEND))
(def %check-critical
  (fn (_ p cs)
    (List for-each
      (fn (_ c) (when (match ((int= (int& (%u8 p (int- (List ref 1 c) 4)) 32) 0) (not (List includes? (first c) %known)))
                             (#t #f))
                  (%fail "a critical chunk this decoder does not know")))
      cs)))

; --- Passes and filters ---------------------------------------------------

; Each Adam7 pass's first column and row and its steps across and down; an
; image not interlaced is the one pass of every pixel.
(def %adam7 (list (list 0 0 8 8) (list 4 0 8 8) (list 0 4 4 8) (list 2 0 4 4)
                  (list 0 2 2 4) (list 1 0 2 2) (list 0 1 1 2)))
(def %whole (list (list 0 0 1 1)))
(def %extent (fn (_ n at step) (match ((int< at n) (int/ (int+ (int- n at) (int- step 1)) step)) (#t 0))))
; The bytes of a row of N pixels of BITS bits each.
(def %stride (fn (_ n bits) (int/ (int+ (int* n bits) 7) 8)))

; Undo a row's filter in place: the row's N bytes at R, from byte I, against
; the row above's at U -- a row of zeros above a pass's first -- BPP bytes a
; whole pixel (1 under 8 bits).  A byte's left neighbours are 0 for the
; first pixel, so Average and Paeth take the first BPP bytes on their own:
; Average adds half the byte above, Paeth the byte above whole.
(def %sub
  (fn (self r i n bpp)
    (when (int< i n)
      (ptr-set! r i (int+ (ptr-ref r i 1) (ptr-ref r (int- i bpp) 1)) 1)
      (self r (int+ i 1) n bpp))))
(def %up
  (fn (self r u i n)
    (when (int< i n)
      (ptr-set! r i (int+ (ptr-ref r i 1) (ptr-ref u i 1)) 1)
      (self r u (int+ i 1) n))))
(def %avg-head
  (fn (self r u i n)
    (when (int< i n)
      (ptr-set! r i (int+ (ptr-ref r i 1) (int>> (%u8 u i) 1)) 1)
      (self r u (int+ i 1) n))))
(def %avg
  (fn (self r u i n bpp)
    (when (int< i n)
      (ptr-set! r i (int+ (ptr-ref r i 1) (int>> (int+ (%u8 r (int- i bpp)) (%u8 u i)) 1)) 1)
      (self r u (int+ i 1) n bpp))))
(def %abs (fn (_ x) (match ((int< x 0) (int- 0 x)) (#t x))))
(def %paeth
  (fn (self r u i n bpp)
    (when (int< i n)
      (def a (%u8 r (int- i bpp)))
      (def b (%u8 u i))
      (def c (%u8 u (int- i bpp)))
      (def pa (%abs (int- b c)))
      (def pb (%abs (int- a c)))
      (def pc (%abs (int- (int+ a b) (int+ c c))))
      (ptr-set! r i (int+ (ptr-ref r i 1)
                          (match ((int< pb pa) (match ((int< pc pb) c) (#t b)))
                                 ((int< pc pa) c)
                                 (#t a)))
                1)
      (self r u (int+ i 1) n bpp))))

(def %unfilter-pure
  (fn (_ f r u n bpp)
    (def head (match ((int< n bpp) n) (#t bpp)))
    (match ((int= f 1) (%sub r bpp n bpp))
           ((int= f 2) (%up r u 0 n))
           ((int= f 3) (do (%avg-head r u 0 head) (%avg r u bpp n bpp)))
           ((int= f 4) (do (%up r u 0 head) (%paeth r u bpp n bpp)))
           (#t ()))))

; --- Pixels ---------------------------------------------------------------

; The sample K of a row at R, at DEPTH bits, as stored (16 bits whole).
(def %sample
  (fn (_ r k depth)
    (match ((int= depth 8) (%u8 r k))
           ((int= depth 16) (%u16 r (int+ k k)))
           (#t (do (def bit (int* k depth))
                   (int& (int>> (%u8 r (int>> bit 3)) (int- (int- 8 depth) (int& bit 7)))
                         (int- (int<< 1 depth) 1)))))))
; A sample as stored brought to 8 bits.
(def %scale
  (fn (_ v depth)
    (match ((int= depth 8) v) ((int= depth 16) (int>> v 8))
           ((int= depth 4) (int* v 17)) ((int= depth 2) (int* v 85)) (#t (int* v 255)))))

(def %put4!
  (fn (_ o i r g b a)
    (ptr-set! o i r 1) (ptr-set! o (int+ i 1) g 1) (ptr-set! o (int+ i 2) b 1) (ptr-set! o (int+ i 3) a 1)))

; The palette as 256 RGBA entries: PLTE's colours, tRNS's alphas, opaque
; black past the end of either.
(def %palette
  (fn (_ p plte trns)
    (def t (str-make 1024))
    (def tp (str->ptr t))
    (def np (match ((eq? plte ()) 0) (#t (int/ (List ref 2 plte) 3))))
    (def na (match ((eq? trns ()) 0) (#t (List ref 2 trns))))
    ((fn (self k)
       (when (int< k 256)
         (match ((int< k np)
                  (do (def o (int+ (List ref 1 plte) (int* k 3)))
                      (%put4! tp (int* k 4) (%u8 p o) (%u8 p (int+ o 1)) (%u8 p (int+ o 2))
                              (match ((int< k na) (%u8 p (int+ (List ref 1 trns) k))) (#t 255)))))
                (#t (%put4! tp (int* k 4) 0 0 0 255)))
         (self (int+ k 1))))
     0)
    t))

; The function that writes pixel K of a row at R to O at I, for colour type
; CT at DEPTH, with the palette PAL and the transparent value KEY (a list of
; one grey or three RGB samples as stored, nil for none).
(def %pixel-fn
  (fn (_ ct depth palette key)
    (def pal (match ((eq? palette ()) ()) (#t (str->ptr palette))))
    (match
      ((match ((int= ct 6) (int= depth 8)) (#t #f))
        (fn (_ r k o i) (ptr-set! o i (ptr-ref r (int<< k 2) 4) 4)))
      ((match ((int= ct 2) (match ((int= depth 8) (eq? key ())) (#t #f))) (#t #f))
        (fn (_ r k o i) (def j (int* k 3)) (%put4! o i (%u8 r j) (%u8 r (int+ j 1)) (%u8 r (int+ j 2)) 255)))
      ((match ((int= ct 3) (int= depth 8)) (#t #f))
        (fn (_ r k o i) (ptr-set! o i (ptr-ref pal (int<< (%u8 r k) 2) 4) 4)))
      ((int= ct 3)
        (fn (_ r k o i) (ptr-set! o i (ptr-ref pal (int<< (%sample r k depth) 2) 4) 4)))
      ((int= ct 0)
        (fn (_ r k o i)
          (def v (%sample r k depth))
          (def g (%scale v depth))
          (%put4! o i g g g (match ((eq? key ()) 255) ((int= v (first key)) 0) (#t 255)))))
      ((int= ct 4)
        (fn (_ r k o i)
          (def g (%scale (%sample r (int+ k k) depth) depth))
          (%put4! o i g g g (%scale (%sample r (int+ (int+ k k) 1) depth) depth))))
      ((int= ct 2)
        (fn (_ r k o i)
          (def j (int* k 3))
          (def rv (%sample r j depth))
          (def gv (%sample r (int+ j 1) depth))
          (def bv (%sample r (int+ j 2) depth))
          (%put4! o i (%scale rv depth) (%scale gv depth) (%scale bv depth)
                  (match ((eq? key ()) 255)
                         ((match ((int= rv (first key)) (match ((int= gv (List ref 1 key)) (int= bv (List ref 2 key))) (#t #f))) (#t #f)) 0)
                         (#t 255)))))
      (#t
        (fn (_ r k o i)
          (def j (int<< k 2))
          (%put4! o i (%scale (%sample r j depth) depth) (%scale (%sample r (int+ j 1) depth) depth)
                  (%scale (%sample r (int+ j 2) depth) depth) (%scale (%sample r (int+ j 3) depth) depth)))))))

; The transparent value tRNS gives a grey or RGB image, as stored.
(def %key
  (fn (_ p ct trns)
    (match ((eq? trns ()) ())
           ((int= ct 0) (list (%u16 p (List ref 1 trns))))
           ((int= ct 2) ((fn (_ o) (list (%u16 p o) (%u16 p (int+ o 2)) (%u16 p (int+ o 4)))) (List ref 1 trns)))
           (#t ()))))

; Write a row's N pixels at R to O from byte I, STEP bytes apart, through PUT.
; LAYOUT and PAL are the compiled loop's; the pure one has PUT for both.
(def %pixels-pure
  (fn (_ layout put r o i n step pal)
    ((fn (self k i)
       (when (int< k n)
         (put r k o i)
         (self (int+ k 1) (int+ i step))))
     0 i)))

; The layouts of whole bytes the compiled pixel loops take, by name: 8 or 16
; bits a sample, a grey or RGB image's tRNS left out.  Nil for any other,
; which the pure loop writes.
(def %layout
  (fn (_ ct depth key)
    (match ((match ((int= depth 8) #f) ((int= depth 16) #f) (#t #t)) ())
           ((int= ct 3) (lit pal8))
           ((int= ct 6) (match ((int= depth 8) (lit rgba8)) (#t (lit rgba16))))
           ((int= ct 4) (match ((int= depth 8) (lit greya8)) (#t (lit greya16))))
           ((not (eq? key ())) ())
           ((int= ct 2) (match ((int= depth 8) (lit rgb8)) (#t (lit rgb16))))
           (#t (match ((int= depth 8) (lit grey8)) (#t (lit grey16)))))))

; Undo the filters of one pass's PH rows of STRIDE bytes from AT in the
; inflated buffer Z, and write each row's PW pixels to O: pixel K of row Y
; goes to column X0 + K*DX of image row Y0 + Y*DY, W wide.  ENGINE is the
; pair of row loops, (UNFILTER PIXELS).
(def %pass
  (fn (_ engine z at pw ph stride bpp o w pass layout put pal)
    (def x0 (first pass))
    (def y0 (List ref 1 pass))
    (def dx (List ref 2 pass))
    (def dy (List ref 3 pass))
    (def unfilter (first engine))
    (def pixels (match ((eq? layout ()) %pixels-pure) (#t (List ref 1 engine))))
    (def zero (str-make (int+ stride 1)))
    ((fn (self y u)
       (when (int< y ph)
         (def f (%at z (int+ at (int* y (int+ stride 1)))))
         (def r (%at f 1))
         (unless (int< (%u8 f 0) 5) (%fail "an unknown row filter"))
         (unfilter (%u8 f 0) r u stride bpp)
         (pixels layout put r o (int<< (int+ (int* (int+ y0 (int* y dy)) w) x0) 2) pw (int<< dx 2) pal)
         (self (int+ y 1) r)))
     0 (str->ptr zero))))

; The bytes the passes take inflated: per pass a filter byte and a row.
(def %need
  (fn (self passes w h bits acc)
    (match ((eq? passes ()) acc)
           (#t (do (def ps (first passes))
                   (def pw (%extent w (first ps) (List ref 2 ps)))
                   (def ph (%extent h (List ref 1 ps) (List ref 3 ps)))
                   (self (rest passes) w h bits
                         (match ((int= pw 0) acc) (#t (int+ acc (int* ph (int+ (%stride pw bits) 1)))))))))))

; The IDAT chunks' data as one region (BUF START LEN): the file's own bytes
; when there is one chunk, else the chunks copied end to end.
(def %idat
  (fn (_ s p cs)
    (def ds (%all %IDAT cs))
    (match ((eq? ds ()) (%fail "no IDAT chunk"))
           ((eq? (rest ds) ()) (list s (List ref 1 (first ds)) (List ref 2 (first ds))))
           (#t (do (def n (List fold (fn (_ acc d) (int+ acc (List ref 2 d))) 0 ds))
                   (def buf (str-make n))
                   (List fold (fn (_ at d) (mem-copy (%at (str->ptr buf) at) (%at p (List ref 1 d)) (List ref 2 d))
                                (int+ at (List ref 2 d)))
                     0 ds)
                   (list buf 0 n))))))

; --- The compiled engine (JIT), adopted only when it proves out ------
;
; x/codec/png-jit compiles the row loops.  As inflate's engine is, it is an
; entry of Compiled's made on demand, built for an image of %jit-threshold
; inflated bytes or more or on (Png jit!), and adopted only after it undoes
; the check rows' filters and writes the check pixels as the pure loops do.
; Measured on an M-series Mac: the pure loops cost about 30 microseconds an
; inflated byte, the build about 0.7 s once a process; they meet near 22KB.

(def %pure (list %unfilter-pure %pixels-pure))

; Check bytes: a run that is not periodic in any pixel width.
(def %check-bytes
  (fn (_ n seed)
    (def b (str-make n))
    ((fn (self i) (when (int< i n) (ptr-set! (str->ptr b) i (int& (int+ (int* i 37) (int+ (int>> (int* i i) 3) seed)) 255) 1) (self (int+ i 1)))) 0)
    b))
(def %same?
  (fn (self a b i n) (match ((int< i n) (match ((int= (ptr-ref a i 1) (ptr-ref b i 1)) (self a b (int+ i 1) n)) (#t #f))) (#t #t))))

; Every filter at every pixel width, below a row of zeros and below a row;
; then every layout, its pixels packed and four apart.
(def %agrees?
  (fn (_ unfilter pixels)
    (def above (str->ptr (%check-bytes 48 11)))
    (def filters-agree
      (List all?
        (fn (_ case)
          (def a (str->ptr (%check-bytes 48 5)))
          (def b (str->ptr (%check-bytes 48 5)))
          (def u (match ((first (rest (rest case))) above) (#t (str->ptr (str-make 48)))))
          (%unfilter-pure (first case) a u 45 (List ref 1 case))
          (unfilter (first case) b u 45 (List ref 1 case))
          (%same? a b 0 48))
        (List flat-map (fn (_ f) (List flat-map (fn (_ bpp) (list (list f bpp #t) (list f bpp #f))) (list 1 2 3 4 6 8)))
          (list 1 2 3 4))))
    (def palette (%check-bytes 1024 3))
    (def src (str->ptr (%check-bytes 192 7)))
    (def layouts-agree
      (List all?
        (fn (_ case)
          (def put (%pixel-fn (first case) (List ref 1 case) palette ()))
          (def pal (str->ptr palette))
          (List all?
            (fn (_ step)
              (def a (str->ptr (str-make 200)))
              (def b (str->ptr (str-make 200)))
              (%pixels-pure (List ref 2 case) put src a 4 23 step pal)
              (pixels (List ref 2 case) put src b 4 23 step pal)
              (%same? a b 0 200))
            (list 4 8)))
        (list (list 6 8 (lit rgba8)) (list 2 8 (lit rgb8)) (list 0 8 (lit grey8)) (list 4 8 (lit greya8)) (list 3 8 (lit pal8))
              (list 6 16 (lit rgba16)) (list 2 16 (lit rgb16)) (list 0 16 (lit grey16)) (list 4 16 (lit greya16)))))
    (match (filters-agree layouts-agree) (#t #f))))

(def %jit-threshold 22528)
(def %entry ())

(def %jit-try!
  (fn (_)
    (when (null? %entry)
      (set! %entry
        (Compiled make-on-demand (lit png) %pure
          (fn (_)
            (import x/codec/png-jit)
            ((prim-ref (lit png) (lit jit-make)) %agrees?))
          (fn (_ v) ()))))
    ((fn (_ entry)
       (when (eq? (entry state) (lit interpreted)) (entry compile!))
       (eq? (entry state) (lit compiled)))
     %entry)))

; The row loops for an image of N inflated bytes: the engine's when it is
; built, or when N is past the bar and a build succeeds; else the pure ones.
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

(def %decode
  (fn (_ s start len)
    (def p (%at (str->ptr s) start))
    (unless (match ((int< len 8) #f) (#t (%signed? p 0 %signature))) (%fail "not a PNG: the signature does not match"))
    (def cs (%chunks s (str->ptr s) (int+ start 8) (int+ start len) ()))
    (def base (str->ptr s))
    (def hd (%header base cs))
    (%check-critical base cs)
    (def w (first hd))
    (def h (List ref 1 hd))
    (def depth (List ref 2 hd))
    (def ct (List ref 3 hd))
    (def plte (%find %PLTE cs))
    (def trns (%find %tRNS cs))
    (when (match ((int= ct 3) (eq? plte ())) (#t #f)) (%fail "a palette image with no PLTE"))
    (def bits (int* depth (%channels ct)))
    (def bpp (match ((int< bits 8) 1) (#t (int>> bits 3))))
    (def passes (match ((int= (List ref 4 hd) 1) %adam7) (#t %whole)))
    (def need (%need passes w h bits 0))
    (def zr (%idat s base cs))
    (def got (Inflate zlib (first zr) (List ref 1 zr) (List ref 2 zr)))
    (when (int< (List ref 1 got) need) (%fail "the image data is short"))
    (def z (str->ptr (first got)))
    (def out (str-make (int* (int* w h) 4)))
    (def palette (match ((int= ct 3) (%palette base plte trns)) (#t ())))
    (def key (%key base ct trns))
    (def put (%pixel-fn ct depth palette key))
    (def pal (match ((eq? palette ()) ()) (#t (str->ptr palette))))
    (def layout (%layout ct depth key))
    (def engine (%engine-for need))
    (List fold
      (fn (_ at ps)
        (def pw (%extent w (first ps) (List ref 2 ps)))
        (def ph (%extent h (List ref 1 ps) (List ref 3 ps)))
        (def stride (%stride pw bits))
        (match ((int= pw 0) at)
               (#t (do (%pass engine z at pw ph stride bpp (str->ptr out) w ps layout put pal)
                       (int+ at (int* ph (int+ stride 1)))))))
      0 passes)
    (list w h out)))

(def-class Png ()
  (doc "PNG images decoded to RGBA in pure x-lang: every colour type and bit depth, palettes, tRNS transparency and Adam7 interlacing."
    (example "(do (def r (Bytes of-hex \"89504e470d0a1a0a0000000d49484452000000020000000108020000007b40e8dd0000000f4944415408d763f8cfc0c0f09f010007ff01ff09a29f170000000049454e44ae426082\")) (Png size (first r) 0 (List ref 2 r)))" "(2 1)")
    (see decode))
  (static
    (method size (self (param s STRING "Bytes holding a PNG")
                       . (param span LIST "START, then LENGTH: which bytes of s; default all of s"))
      (doc "The image's width and height, from its header, without decoding it. Give LENGTH for a PNG held in a buffer: s's own length is measured to its first NUL. Raises a label 'value when the bytes are not a PNG."
        (returns LIST "(WIDTH HEIGHT)")
        (example "(do (def r (Bytes of-hex \"89504e470d0a1a0a0000000d49484452000000020000000108020000007b40e8dd0000000f4944415408d763f8cfc0c0f09f010007ff01ff09a29f170000000049454e44ae426082\")) (Png size (first r) 0 (List ref 2 r)))" "(2 1)"))
      (def sp (%span s span))
      (def p (%at (str->ptr s) (first sp)))
      (unless (match ((int< (first (rest sp)) 33) #f) (#t (%signed? p 0 %signature)))
        (%fail "not a PNG: the signature does not match"))
      (unless (int= (%u32 p 12) %IHDR) (%fail "the first chunk is not IHDR"))
      (list (%u32 p 16) (%u32 p 20)))
    (method decode (self (param s STRING "Bytes holding a PNG")
                         . (param span LIST "START, then LENGTH, as for size"))
      (doc "Decode the image to RGBA at 8 bits a sample: grey spread to red, green and blue, samples under 8 bits scaled to 0-255, 16-bit samples cut to their high byte, palette indexes looked up, alpha 255 where the image has none. Each chunk's CRC is checked. Raises a label 'value naming what is wrong with a malformed image."
        (returns LIST "(WIDTH HEIGHT RGBA): RGBA a buffer of WIDTH x HEIGHT x 4 bytes, rows top to bottom")
        (example "(do (def r (Bytes of-hex \"89504e470d0a1a0a0000000d49484452000000020000000108020000007b40e8dd0000000f4944415408d763f8cfc0c0f09f010007ff01ff09a29f170000000049454e44ae426082\")) (def d (Png decode (first r) 0 (List ref 2 r))) (Bytes hex (list (List ref 2 d) 0 8)))" "\"ff0000ff00ff00ff\""))
      (def sp (%span s span))
      (%decode s (first sp) (first (rest sp))))
    (method jit! (self)
      (doc "Build and adopt the compiled row loops (JIT; ARM64 and x86-64 backends) now, if they undo the check rows' filters and write the check pixels exactly as the pure-x loops do. Idempotent. Answers #t when the engine is active, #f when unavailable -- the pure-x loops carry on, with the same output. decode builds it on its own for an image of 22KB or more inflated."
        (returns BOOL "#t when the compiled engine is active"))
      (%jit-try!))))

(doc (provide x/codec/png Png)
  "PNG images decoded to RGBA in pure x-lang, with a differentially-verified compiled engine for the row loops: (Png decode s) answers (WIDTH HEIGHT RGBA), (Png size s) the size alone.")

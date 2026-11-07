; canvas.x -- Canvas: an RGBA picture in memory, and what a window's frame is
; drawn with.
;
; A canvas is (WIDTH HEIGHT REGION): REGION is WIDTH x HEIGHT x 4 bytes,
; red, green, blue and alpha a pixel, rows top to bottom with nothing
; between them.  It is the shape (Png decode s) answers, so a decoded PNG
; is a canvas, and REGION is the buffer (Sdl draw! win buf) shows.
;
; A colour is (R G B) or (R G B A), each 0-255; alpha is 255 when not given.
; Every operation clips to the canvas it draws on and to the one it reads,
; so a rectangle hanging off an edge draws the part that is on it.
;
; The pixel loops are six kernels, each written once below as an integer
; function over byte addresses.  The pure-x version is that form with its
; operators bound to the int doors; x/gfx/canvas-jit compiles the same form,
; and the compiled six are adopted only after they write what the pure ones
; write over the check pictures.  They are built once a process when the
; canvases drawn have covered %jit-threshold pixels, or on (Canvas jit!).
(module x/gfx/canvas)

(import x/tool/compiled)

(import x/core/doors int& int* int+ int- int->ptr int/ int< int<< int= int>> mem-copy ptr->int ptr-ref ptr-set! ptr-ref-word ptr-set-word! str->ptr str-byte-len str-byte-ref str-make char->int)

(def %fail (fn (_ what) (Err raise (lit value) (Str8 append "Canvas: " what) ())))

; --- The kernels, as forms -------------------------------------------------
;
; Addresses are integers.  (%mem-byte-ref-at A I) is the byte at A + I;
; (%mem-byte-set-at! A I V) stores V there.  A rectangle's kernel walks I
; across a row of N bytes, then steps both addresses by their strides and
; does the next of H rows.

(def %ref (fn (_ base idx k) (list (lit %mem-byte-ref-at) base (list (lit +) idx k))))
(def %set (fn (_ base idx k v) (list (lit %mem-byte-set-at!) base (list (lit +) idx k) v)))

; T / 255, rounded, for T in 0 .. 255 * 255.
(def %div255
  (fn (_ t)
    (list (lit >>) (list (lit +) (list (lit +) t 128) (list (lit >>) (list (lit +) t 128) 8)) 8)))

; X over Y at coverage A (0-255).
(def %mix
  (fn (_ x y a)
    (%div255 (list (lit +) (list (lit *) x a) (list (lit *) y (list (lit -) 255 a))))))

; The pixel at D + DI made SOURCE over it, the source's channel K read by
; (SRC K), at coverage A (an expression; it is read more than once).
(def %over
  (fn (_ src d di a)
    (list (lit do)
      (%set d di 0 (%mix (src 0) (%ref d di 0) a))
      (%set d di 1 (%mix (src 1) (%ref d di 1) a))
      (%set d di 2 (%mix (src 2) (%ref d di 2) a))
      (%set d di 3 (list (lit +) a (%div255 (list (lit *) (%ref d di 3) (list (lit -) 255 a))))))))

; The next row of a rectangle, or 0 after the last.
(def %next-row
  (fn (_ call)
    (list (lit if) (lit (< 1 h)) call 0)))

; A machine word at a time while a whole one is left in the row, then bytes.
(def %copy-form
  (list (lit fn) (lit (self s d i n h ss ds))
    (list (lit match)
      (list (list (lit <) (list (lit +) (lit i) (int- %word-size 1)) (lit n))
        (list (lit do)
          (lit (%mem-set-at! (+ d i) 0 (%mem-ref-at (+ s i) 0)))
          (list (lit self) (lit s) (lit d) (list (lit +) (lit i) %word-size) (lit n) (lit h) (lit ss) (lit ds))))
      (list (lit (< i n))
        (list (lit do)
          (%set (lit d) (lit i) 0 (%ref (lit s) (lit i) 0))
          (lit (self s d (+ i 1) n h ss ds))))
      (list #t (%next-row (lit (self (+ s ss) (+ d ds) 0 n (- h 1) ss ds)))))))

(def %fill-form
  (list (lit fn) (lit (self d i n h ds c))
    (list (lit if) (lit (< i n))
      (list (lit do)
        (%set (lit d) (lit i) 0 (lit (& c 255)))
        (%set (lit d) (lit i) 1 (lit (& (>> c 8) 255)))
        (%set (lit d) (lit i) 2 (lit (& (>> c 16) 255)))
        (%set (lit d) (lit i) 3 (lit (& (>> c 24) 255)))
        (lit (self d (+ i 4) n h ds c)))
      (%next-row (lit (self (+ d ds) 0 n (- h 1) ds c))))))

; A source pixel at alpha 0 leaves the destination; at 255 it replaces it.
(def %blend-pixel
  (fn (_ s si d di)
    (def a (%ref s si 3))
    (list (lit match)
      (list (list (lit =) a 0) 0)
      (list (list (lit =) a 255)
        (list (lit do)
          (%set d di 0 (%ref s si 0)) (%set d di 1 (%ref s si 1))
          (%set d di 2 (%ref s si 2)) (%set d di 3 255)))
      (list #t (%over (fn (_ k) (%ref s si k)) d di a)))))

(def %blend-form
  (list (lit fn) (lit (self s d i n h ss ds))
    (list (lit if) (lit (< i n))
      (list (lit do)
        (%blend-pixel (lit s) (lit i) (lit d) (lit i))
        (lit (self s d (+ i 4) n h ss ds)))
      (%next-row (lit (self (+ s ss) (+ d ds) 0 n (- h 1) ss ds))))))

; Colour C wherever the source has alpha, at the source's alpha times C's.
(def %stamp-form
  ((fn (_ cov)
     (list (lit fn) (lit (self s d i n h ss ds c))
       (list (lit if) (lit (< i n))
         (list (lit do)
           (list (lit if) (list (lit <) 0 cov)
             (%over (fn (_ k) (list (lit &) (list (lit >>) (lit c) (* 8 k)) 255)) (lit d) (lit i) cov)
             0)
           (lit (self s d (+ i 4) n h ss ds c)))
         (%next-row (lit (self (+ s ss) (+ d ds) 0 n (- h 1) ss ds c))))))
   (%div255 (list (lit *) (%ref (lit s) (lit i) 3) (lit (& (>> c 24) 255))))))

; One row of N bytes blended from a source row stretched to it, nearest:
; the source pixel for the destination's next is at FX >> 16, FX stepping
; by STEP.
(def %stretch-form
  (list (lit fn) (lit (self s d i n fx step))
    (list (lit if) (lit (< i n))
      (list (lit do)
        (%blend-pixel (lit s) (lit (<< (>> fx 16) 2)) (lit d) (lit i))
        (lit (self s d (+ i 4) n (+ fx step) step)))
      0)))

; N bytes at O, each F/256 of the way from A's to B's.  The light reads
; one row of the map made this way for each row of pixels.
(def %lerp-form
  (list (lit fn) (lit (self a b o i n f))
    (list (lit if) (lit (< i n))
      (list (lit do)
        (%set (lit o) (lit i) 0
          (lit (>> (+ (* (%mem-byte-ref-at a i) (- 256 f)) (* (%mem-byte-ref-at b i) f)) 8)))
        (lit (self a b o (+ i 1) n f)))
      0)))

; N pixels at D multiplied by the light of row T, a pixel a cell, read
; between the cells: U is the next pixel's place along T in 256ths of a
; cell, stepping by K.  T's first and last cells are repeated at its ends,
; so the two cells either side of U are always on it.
(def %light-form
  ((fn (_ c fx)
     ((fn (_ chan)
        (list (lit fn) (lit (self d n u k t))
          (list (lit if) (lit (< 0 n))
            (list (lit do)
              (chan 0) (chan 1) (chan 2)
              (lit (self (+ d 4) (- n 1) (+ u k) k t)))
            0)))
      (fn (_ ch)
        ((fn (_ v)
           (%set (lit d) 0 ch
             (list (lit >>) (list (lit *) (%ref (lit d) 0 ch) (list (lit +) v (list (lit >>) v 7))) 8)))
         (list (lit >>)
           (list (lit +) (list (lit *) (%ref (lit t) c ch) (list (lit -) 256 fx))
                         (list (lit *) (%ref (lit t) c (+ ch 4)) fx))
           8)))))
   (lit (<< (>> u 8) 2))
   (lit (& u 255))))

; In the order every engine holds them.
(def %forms (list %copy-form %fill-form %blend-form %stamp-form %stretch-form %lerp-form %light-form))

; --- The pure-x kernels ----------------------------------------------------
;
; Each form with its operators replaced by the doors themselves: the
; function objects stand in the form where the names were, so the form
; means the same thing in whatever environment evaluates it.

(def %ops
  (list (pair (lit +) int+) (pair (lit -) int-) (pair (lit *) int*) (pair (lit <) int<)
        (pair (lit =) int=) (pair (lit >>) int>>) (pair (lit <<) int<<) (pair (lit &) int&)
        (pair (lit %mem-byte-ref-at) (fn (_ a i) (int& (ptr-ref (int->ptr (int+ a i)) 0 1) 255)))
        (pair (lit %mem-byte-set-at!) (fn (_ a i v) (ptr-set! (int->ptr (int+ a i)) 0 v 1)))
        (pair (lit %mem-ref-at) (fn (_ a i) (ptr-ref-word (int->ptr a) (int* i %word-size))))
        (pair (lit %mem-set-at!) (fn (_ a i v) (ptr-set-word! (int->ptr a) (int* i %word-size) v)))))

(def %subst
  (fn (self form)
    (match
      ((pair? form) (pair (self (first form)) (self (rest form))))
      ((symbol? form) ((fn (_ e) (if (null? e) form (rest e))) (Assoc entry form %ops)))
      (#t form))))

(def %pure (List map (fn (_ f) (eval (%subst f))) %forms))

; --- The kernels in use ----------------------------------------------------
;
; Each its own name, so a draw reaches its loop without a send: the pure
; ones until the compiled ones are installed, and the pure ones again
; whenever Compiled installs them (before a state image is written).

(def %k-copy ())
(def %k-fill ())
(def %k-blend ())
(def %k-stamp ())
(def %k-stretch ())
(def %k-lerp ())
(def %k-light ())

(def %install!
  (fn (_ ks)
    (set! %k-copy (first ks))
    (set! %k-fill (first (rest ks)))
    (set! %k-blend (first (rest (rest ks))))
    (set! %k-stamp (first (rest (rest (rest ks)))))
    (set! %k-stretch (first (rest (rest (rest (rest ks))))))
    (set! %k-lerp (first (rest (rest (rest (rest (rest ks)))))))
    (set! %k-light (first (rest (rest (rest (rest (rest (rest ks))))))))))

(%install! %pure)

; --- The compiled kernels, adopted only when they agree --------------------

(def %check-n 192)

; A picture that is no pattern a kernel could get right by accident: every
; alpha from 0 to 255 among its pixels, 0 and 255 included.
(def %check-bytes
  (fn (_ n seed)
    (def b (str-make n))
    ((fn (self i)
       (when (int< i n)
         (do (ptr-set! (str->ptr b) i
               (match ((int= i 3) 0) ((int= i 7) 255)
                      (#t (int& (int+ (int* i 37) (int+ (int>> (int* i i) 3) seed)) 255)))
               1)
             (self (int+ i 1)))))
     0)
    b))

(def %same?
  (fn (self a b i n)
    (match ((int< i n) (match ((int= (ptr-ref a i 1) (ptr-ref b i 1)) (self a b (int+ i 1) n)) (#t #f)))
           (#t #t))))

; Each kernel run pure and by the candidate on copies of one destination,
; the two destinations then compared byte for byte.
(def %agrees?
  (fn (_ engine)
    (def src (ptr->int (str->ptr (%check-bytes %check-n 7))))
    (def row (ptr->int (str->ptr (%check-bytes 64 11))))
    (def runs
      (list (fn (_ k d) (k src d 0 24 3 64 64))
            (fn (_ k d) (k d 0 24 3 64 2164195346))
            (fn (_ k d) (k src d 0 24 3 64 64))
            (fn (_ k d) (k src d 0 24 3 64 64 3426265233))
            (fn (_ k d) (k src d 0 48 4096 21845))
            (fn (_ k d) (k src row d 0 40 77))
            (fn (_ k d) (k d 12 40 64 row))))
    (List all?
      (fn (_ i)
        (def a (%check-bytes %check-n 5))
        (def b (%check-bytes %check-n 5))
        ((List ref i runs) (List ref i %pure) (ptr->int (str->ptr a)))
        ((List ref i runs) (List ref i engine) (ptr->int (str->ptr b)))
        (%same? (str->ptr a) (str->ptr b) 0 %check-n))
      (list 0 1 2 3 4 5 6))))

(def %jit-threshold 65536)
(def %drawn 0)
(def %entry ())

(def %jit-try!
  (fn (_)
    (when (null? %entry)
      (set! %entry
        (Compiled make-on-demand (lit canvas) %pure
          (fn (_)
            (import x/gfx/canvas-jit)
            ((prim-ref (lit canvas) (lit jit-make)) %forms %agrees?))
          %install!)))
    ((fn (_ entry)
       (when (eq? (entry state) (lit interpreted)) (entry compile!))
       (eq? (entry state) (lit compiled)))
     %entry)))

; N more pixels are about to be drawn: until a build has been tried, count
; them, and try one once they pass the bar.
(def %drawing
  (fn (_ n)
    (when (null? %entry)
      (do (set! %drawn (int+ %drawn n))
          (unless (int< %drawn %jit-threshold) (%jit-try!))))))

; --- Pictures --------------------------------------------------------------

(def %w (fn (_ c) (first c)))
(def %h (fn (_ c) (first (rest c))))
(def %buf (fn (_ c) (first (rest (rest c)))))
; The address of pixel X Y.
(def %addr (fn (_ c x y) (int+ (ptr->int (str->ptr (%buf c))) (int<< (int+ x (int* y (%w c))) 2))))

(def %colour
  (fn (_ c)
    (def a (if (null? (rest (rest (rest c)))) 255 (first (rest (rest (rest c))))))
    (int+ (first c) (int+ (int<< (first (rest c)) 8) (int+ (int<< (first (rest (rest c))) 16) (int<< a 24))))))

; N zero bytes: four written, then the zeros doubled by copying.
(def %zeroed
  (fn (_ n)
    (def r (str-make (int+ n 4)))
    (def p (str->ptr r))
    (ptr-set! p 0 0 4)
    ((fn (self k)
       (when (int< k n)
         (do (mem-copy (int->ptr (int+ (ptr->int p) k)) p (if (int< (int* 2 k) n) k (int- n k)))
             (self (int* 2 k)))))
     4)
    r))

(def %make
  (fn (_ w h)
    (when (match ((int< w 1) #t) ((int< h 1) #t) (#t #f)) (%fail "a canvas is at least 1 x 1"))
    (list w h (%zeroed (int* 4 (int* w h))))))

(def %max3 (fn (_ a b c) ((fn (_ m) (if (int< m c) c m)) (if (int< a b) b a))))
(def %min3 (fn (_ a b c) ((fn (_ m) (if (int< c m) c m)) (if (int< b a) b a))))

; The part of a W x H rectangle at X Y of a DW x DH canvas, read from SX SY
; of an SW x SH one, that lies on both: K is called with its X Y SX SY W H
; when there is any.
(def %clip
  (fn (_ dw dh x y sx sy w h sw sh k)
    (match
      ; Wholly on both, the ordinary case: as it is.
      ((match ((int< x 0) #f) ((int< y 0) #f) ((int< sx 0) #f) ((int< sy 0) #f)
              ((int< dw (int+ x w)) #f) ((int< dh (int+ y h)) #f)
              ((int< sw (int+ sx w)) #f) ((int< sh (int+ sy h)) #f)
              ((int< 0 w) (int< 0 h)) (#t #f))
        (k x y sx sy w h))
      (#t ((fn (_ l t)
             ((fn (_ cw ch)
                (when (if (int< 0 cw) (int< 0 ch) #f)
                  (k (int+ x l) (int+ y t) (int+ sx l) (int+ sy t) cw ch)))
              (%min3 (int- w l) (int- dw (int+ x l)) (int- sw (int+ sx l)))
              (%min3 (int- h t) (int- dh (int+ y t)) (int- sh (int+ sy t)))))
           (%max3 0 (int- 0 x) (int- 0 sx))
           (%max3 0 (int- 0 y) (int- 0 sy)))))))

(def %copy!
  (fn (_ dst x y src sx sy w h)
    (%clip (%w dst) (%h dst) x y sx sy w h (%w src) (%h src)
      (fn (_ cx cy csx csy cw ch)
        (%drawing (int* cw ch))
        (%k-copy (%addr src csx csy) (%addr dst cx cy) 0 (int<< cw 2) ch (int<< (%w src) 2) (int<< (%w dst) 2))))
    dst))

(def %blend!
  (fn (_ dst x y src sx sy w h)
    (%clip (%w dst) (%h dst) x y sx sy w h (%w src) (%h src)
      (fn (_ cx cy csx csy cw ch)
        (%drawing (int* cw ch))
        (%k-blend (%addr src csx csy) (%addr dst cx cy) 0 (int<< cw 2) ch (int<< (%w src) 2) (int<< (%w dst) 2))))
    dst))

(def %stamp!
  (fn (_ dst x y src sx sy w h c)
    (%clip (%w dst) (%h dst) x y sx sy w h (%w src) (%h src)
      (fn (_ cx cy csx csy cw ch)
        (%drawing (int* cw ch))
        (%k-stamp (%addr src csx csy) (%addr dst cx cy) 0 (int<< cw 2) ch (int<< (%w src) 2) (int<< (%w dst) 2) c)))
    dst))

(def %fill!
  (fn (_ dst x y w h colour)
    (%clip (%w dst) (%h dst) x y 0 0 w h w h
      (fn (_ cx cy csx csy cw ch)
        (%drawing (int* cw ch))
        (%k-fill (%addr dst cx cy) 0 (int<< cw 2) ch (int<< (%w dst) 2) (%colour colour))))
    dst))

(def %pixel
  (fn (_ c x y)
    (unless (match ((int< x 0) #f) ((int< y 0) #f) ((int< x (%w c)) (int< y (%h c))) (#t #f))
      (%fail "pixel: X Y is off the canvas"))
    (def p (int->ptr (%addr c x y)))
    (List map (fn (_ k) (int& (ptr-ref p k 1) 255)) (list 0 1 2 3))))

; --- Rows of characters ----------------------------------------------------

(def %rows
  (fn (_ lines colours)
    (when (null? lines) (%fail "rows: no rows"))
    (def w (str-byte-len (first lines)))
    (def table (%zeroed 1024))
    (def tp (str->ptr table))
    (List for-each
      (fn (_ c) (ptr-set! tp (int* 4 (int& (char->int (str-byte-ref (first c) 0)) 255)) (%colour (rest c)) 4))
      colours)
    (def c (%make w (List length lines)))
    (def p (str->ptr (%buf c)))
    (List fold
      (fn (_ y row)
        (unless (int= (str-byte-len row) w) (%fail "rows: the rows are not one width"))
        ((fn (self x)
           (when (int< x w)
             (do (ptr-set! p (int* 4 (int+ x (int* y w)))
                   (ptr-ref tp (int* 4 (int& (char->int (str-byte-ref row x)) 255)) 4) 4)
                 (self (int+ x 1)))))
         0)
        (int+ y 1))
      0 lines)
    c))

; --- Light -----------------------------------------------------------------

(def %log2
  (fn (self n acc) (match ((int= n 1) acc) ((int= (int& n 1) 1) -1) (#t (self (int>> n 1) (int+ acc 1))))))

; Each row of pixels is lit from one row of the map read between two of
; its rows, made in T with its end cells repeated (see %light-form).  A
; pixel's place along it starts half a pixel in from the rectangle's edge,
; in 256ths of a cell, plus the repeated cell before the first.
(def %light!
  (fn (_ dst x y w h map cell)
    (def lg (match ((int< cell 1) -1) ((int< 256 cell) -1) (#t (%log2 cell 0))))
    (when (int< lg 0) (%fail "light!: CELL is a power of two from 1 to 256"))
    (def k (int>> 256 lg))
    (def half (int- (int>> k 1) 128))
    (def mw (%w map))
    (when (int< (int<< mw lg) w) (%fail "light!: MAP has fewer columns than the rectangle has cells"))
    (def last-row (int- (%h map) 1))
    (def t (%zeroed (int<< (int+ mw 2) 2)))
    (def tp (ptr->int (str->ptr t)))
    (def row-at (fn (_ v) (%addr map 0 (if (int< v 0) 0 (if (int< last-row v) last-row v)))))
    (%clip (%w dst) (%h dst) x y 0 0 w h w h
      (fn (_ cx cy csx csy cw ch)
        (%drawing (int* cw ch))
        (def u0 (int+ (int* csx k) (int+ half 256)))
        ((fn (self j)
           (when (int< j ch)
             (do (def v (int+ (int* (int+ csy j) k) half))
                 (%k-lerp (row-at (int>> v 8)) (row-at (int+ (int>> v 8) 1)) (int+ tp 4) 0 (int<< mw 2) (int& v 255))
                 (mem-copy (int->ptr tp) (int->ptr (int+ tp 4)) 4)
                 (mem-copy (int->ptr (int+ tp (int<< (int+ mw 1) 2))) (int->ptr (int+ tp (int<< mw 2))) 4)
                 (%k-light (%addr dst cx (int+ cy j)) cw u0 k tp)
                 (self (int+ j 1)))))
         0)))
    dst))

; --- Text ------------------------------------------------------------------

; A font is (GLYPHS INDEX WIDTH): GLYPHS a canvas of every glyph side by
; side, INDEX 256 bytes, a character's glyph number plus one (0 for none),
; WIDTH a glyph's.
(def %font
  (fn (_ glyphs)
    (when (null? glyphs) (%fail "font: no glyphs"))
    (def gw (str-byte-len (first (first (rest (first glyphs))))))
    (def gh (List length (first (rest (first glyphs)))))
    (def all (%make (int* gw (List length glyphs)) gh))
    (def index (%zeroed 256))
    (List fold
      (fn (_ i g)
        (def pic (%rows (first (rest g)) (list (list "#" 255 255 255 255))))
        (unless (if (int= (%w pic) gw) (int= (%h pic) gh) #f) (%fail "font: the glyphs are not one size"))
        (%copy! all (int* i gw) 0 pic 0 0 gw gh)
        (ptr-set! (str->ptr index) (int& (char->int (str-byte-ref (first g) 0)) 255) (int+ i 1) 1)
        (int+ i 1))
      0 glyphs)
    (list all index gw)))

(def %text!
  (fn (_ dst x y s colour f)
    (def all (first f))
    (def ip (str->ptr (first (rest f))))
    (def gw (first (rest (rest f))))
    (def gh (%h all))
    (def c (%colour colour))
    (def n (str-byte-len s))
    ((fn (self i)
       (when (int< i n)
         (do (def g (int& (ptr-ref ip (int& (char->int (str-byte-ref s i)) 255) 1) 255))
             (unless (int= g 0)
               (%stamp! dst (int+ x (int* i gw)) y all (int* (int- g 1) gw) 0 gw gh c))
             (self (int+ i 1)))))
     0)
    dst))

; --- Nine pieces -----------------------------------------------------------

; SRC's rectangle SX SY SW SH stretched, nearest, and blended over the
; rectangle X Y W H of DST, a row at a time.
(def %stretch!
  (fn (_ dst x y w h src sx sy sw sh)
    (unless (match ((int< w 1) #t) ((int< h 1) #t) ((int< sw 1) #t) ((int< sh 1) #t) (#t #f))
      (do (def step (int/ (int<< sw 16) w))
          (def l (if (int< x 0) (int- 0 x) 0))
          (def r (if (int< (%w dst) (int+ x w)) (int- (int+ x w) (%w dst)) 0))
          (%drawing (int* w h))
          ((fn (self j)
             (when (int< j h)
               (do (def ty (int+ y j))
                   (when (match ((int< ty 0) #f) ((int< ty (%h dst)) (int< (int+ l r) w)) (#t #f))
                     (%k-stretch (%addr src sx (int+ sy (int/ (int* j sh) h)))
                                 (%addr dst (int+ x l) ty)
                                 0 (int<< (int- w (int+ l r)) 2) (int* l step) step))
                   (self (int+ j 1)))))
           0)))
    dst))

(def %nine!
  (fn (_ dst x y w h src l t r b)
    (def sw (%w src))
    (def sh (%h src))
    (def mw (int- sw (int+ l r)))
    (def mh (int- sh (int+ t b)))
    (def dw (int- w (int+ l r)))
    (def dh (int- h (int+ t b)))
    (when (match ((int< mw 1) #t) ((int< mh 1) #t) ((int< dw 0) #t) ((int< dh 0) #t) (#t #f))
      (%fail "nine!: the cut leaves no middle, or the rectangle is smaller than its corners"))
    (%stretch! dst x y l t src 0 0 l t)
    (%stretch! dst (int+ x l) y dw t src l 0 mw t)
    (%stretch! dst (int+ x (int+ l dw)) y r t src (int+ l mw) 0 r t)
    (%stretch! dst x (int+ y t) l dh src 0 t l mh)
    (%stretch! dst (int+ x l) (int+ y t) dw dh src l t mw mh)
    (%stretch! dst (int+ x (int+ l dw)) (int+ y t) r dh src (int+ l mw) t r mh)
    (%stretch! dst x (int+ y (int+ t dh)) l b src 0 (int+ t mh) l b)
    (%stretch! dst (int+ x l) (int+ y (int+ t dh)) dw b src l (int+ t mh) mw b)
    (%stretch! dst (int+ x (int+ l dw)) (int+ y (int+ t dh)) r b src (int+ l mw) (int+ t mh) r b)
    dst))

(def-class Canvas ()
  (doc "An RGBA picture in memory, (WIDTH HEIGHT REGION), and the operations a window's frame is drawn with: fill, copy, blend, stamp, nine pieces, text and light. The pixel loops are compiled once a process when the drawing has covered 65,536 pixels, and only after they agree with the pure-x loops."
    (example "(Canvas pixel (Canvas fill! (Canvas make 4 4) 1 1 2 2 (list 9 8 7)) 2 2)" "(9 8 7 255)")
    (see make) (see light!))
  (static
    (method make (self (param w INTEGER "Width in pixels, 1 or more")
                       (param h INTEGER "Height in pixels, 1 or more"))
      (doc "A canvas of transparent black: every byte zero."
        (returns LIST "(WIDTH HEIGHT REGION), REGION WIDTH x HEIGHT x 4 bytes")
        (example "(Canvas pixel (Canvas make 2 2) 1 1)" "(0 0 0 0)"))
      (%make w h))

    (method pixel (self (param c LIST "A canvas")
                        (param x INTEGER "Column, from 0")
                        (param y INTEGER "Row, from 0"))
      (doc "One pixel's four bytes. Raises a label 'value when X Y is off the canvas."
        (returns LIST "(R G B A)")
        (example "(Canvas pixel (Canvas make 2 2) 0 0)" "(0 0 0 0)"))
      (%pixel c x y))

    (method rows (self (param lines LIST "Strings of one width, a character a pixel, top row first")
                       (param colours LIST "Each (\"C\" R G B) or (\"C\" R G B A): the colour of character C"))
      (doc "A canvas drawn from rows of characters. A character with no colour is clear: transparent black."
        (returns LIST "A canvas as wide as a row and as high as the rows are many")
        (example "(Canvas pixel (Canvas rows (list \"ab\") (list (list \"a\" 255 0 0) (list \"b\" 0 0 255 128))) 1 0)" "(0 0 255 128)"))
      (%rows lines colours))

    (method fill! (self (param c LIST "The canvas drawn on")
                        (param x INTEGER "Left") (param y INTEGER "Top")
                        (param w INTEGER "Width") (param h INTEGER "Height")
                        (param colour LIST "(R G B) or (R G B A)"))
      (doc "Set every pixel of the rectangle to COLOUR, alpha included: nothing is blended."
        (returns LIST "The canvas")
        (example "(Canvas pixel (Canvas fill! (Canvas make 4 4) 1 1 2 2 (list 9 8 7)) 2 2)" "(9 8 7 255)"))
      (%fill! c x y w h colour))

    (method copy! (self (param dst LIST "The canvas drawn on")
                        (param x INTEGER "Left on DST") (param y INTEGER "Top on DST")
                        (param src LIST "The canvas read")
                        (param sx INTEGER "Left on SRC") (param sy INTEGER "Top on SRC")
                        (param w INTEGER "Width") (param h INTEGER "Height"))
      (doc "Copy a rectangle of SRC onto DST as it is, alpha included."
        (returns LIST "DST")
        (example "(Canvas pixel (Canvas copy! (Canvas make 2 1) 1 0 (Canvas rows (list \"a\") (list (list \"a\" 1 2 3 4))) 0 0 1 1) 1 0)" "(1 2 3 4)"))
      (%copy! dst x y src sx sy w h))

    (method blend! (self (param dst LIST "The canvas drawn on")
                         (param x INTEGER "Left on DST") (param y INTEGER "Top on DST")
                         (param src LIST "The canvas read")
                         (param sx INTEGER "Left on SRC") (param sy INTEGER "Top on SRC")
                         (param w INTEGER "Width") (param h INTEGER "Height"))
      (doc "Draw a rectangle of SRC over DST by SRC's alpha (source over): alpha 0 leaves DST, 255 replaces it, and between them the colours are mixed as if DST were opaque."
        (returns LIST "DST")
        (example "(do (def d (Canvas fill! (Canvas make 1 1) 0 0 1 1 (list 0 0 255))) (Canvas blend! d 0 0 (Canvas rows (list \"r\") (list (list \"r\" 255 0 0 128))) 0 0 1 1) (Canvas pixel d 0 0))" "(128 0 127 255)"))
      (%blend! dst x y src sx sy w h))

    (method stamp! (self (param dst LIST "The canvas drawn on")
                         (param x INTEGER "Left on DST") (param y INTEGER "Top on DST")
                         (param src LIST "The canvas whose alpha is the shape")
                         (param sx INTEGER "Left on SRC") (param sy INTEGER "Top on SRC")
                         (param w INTEGER "Width") (param h INTEGER "Height")
                         (param colour LIST "(R G B) or (R G B A)"))
      (doc "Draw COLOUR over DST in SRC's shape: wherever SRC has alpha, at SRC's alpha times COLOUR's. SRC's own colours are not read. A glyph and a shadow are drawn this way."
        (returns LIST "DST")
        (example "(Canvas pixel (Canvas stamp! (Canvas make 1 1) 0 0 (Canvas rows (list \"#\") (list (list \"#\" 0 0 0))) 0 0 1 1 (list 10 20 30)) 0 0)" "(10 20 30 255)"))
      (%stamp! dst x y src sx sy w h (%colour colour)))

    (method nine! (self (param dst LIST "The canvas drawn on")
                        (param x INTEGER "Left") (param y INTEGER "Top")
                        (param w INTEGER "Width") (param h INTEGER "Height")
                        (param src LIST "The picture cut in nine")
                        (param l INTEGER "Columns of SRC in the left edge") (param t INTEGER "Rows in the top edge")
                        (param r INTEGER "Columns in the right edge") (param b INTEGER "Rows in the bottom edge"))
      (doc "Blend SRC over the rectangle cut in nine pieces: the corners as they are, the edges stretched along their length and the middle both ways, nearest pixel. Raises a label 'value when the cut leaves SRC no middle or the rectangle is smaller than its corners."
        (returns LIST "DST")
        (example "(do (def p (Canvas rows (list \"aba\" \"bcb\" \"aba\") (list (list \"a\" 1 1 1) (list \"b\" 2 2 2) (list \"c\" 3 3 3)))) (def d (Canvas nine! (Canvas make 5 5) 0 0 5 5 p 1 1 1 1)) (list (Canvas pixel d 0 0) (Canvas pixel d 2 0) (Canvas pixel d 2 2)))" "((1 1 1 255) (2 2 2 255) (3 3 3 255))"))
      (%nine! dst x y w h src l t r b))

    (method font (self (param glyphs LIST "Each (\"C\" ROWS): ROWS strings of one size, \"#\" ink and anything else clear"))
      (doc "A font for text!: every glyph one size, each the shape of its character."
        (returns LIST "(GLYPHS INDEX WIDTH)")
        (example "(first (rest (rest (Canvas font (list (list \"A\" (list \".#.\" \"#.#\" \"###\")))))))" "3"))
      (%font glyphs))

    (method text! (self (param dst LIST "The canvas drawn on")
                        (param x INTEGER "Left") (param y INTEGER "Top")
                        (param s STRING "The text")
                        (param colour LIST "(R G B) or (R G B A)")
                        (param f LIST "A font, from font"))
      (doc "Stamp each character's glyph in COLOUR, left to right a glyph's width apart. A character the font has no glyph for leaves its place empty."
        (returns LIST "DST")
        (example "(Canvas pixel (Canvas text! (Canvas make 3 1) 0 0 \"A A\" (list 1 2 3) (Canvas font (list (list \"A\" (list \"#\"))))) 2 0)" "(1 2 3 255)"))
      (%text! dst x y s colour f))

    (method light! (self (param dst LIST "The canvas lit")
                         (param x INTEGER "Left of the lit rectangle") (param y INTEGER "Top")
                         (param w INTEGER "Width") (param h INTEGER "Height")
                         (param map LIST "A canvas, a pixel a cell: R G B are the cell's light, 255 as it is, 0 black")
                         (param cell INTEGER "A cell's side in pixels: a power of two from 1 to 256"))
      (doc "Multiply each pixel's colour by the light of the map, read between the cells' centres so that it falls off smoothly. MAP's first cell covers the CELL x CELL pixels at X Y. Alpha is left as it is."
        (returns LIST "DST")
        (example "(Canvas pixel (Canvas light! (Canvas fill! (Canvas make 1 1) 0 0 1 1 (list 255 255 255)) 0 0 1 1 (Canvas fill! (Canvas make 1 1) 0 0 1 1 (list 128 255 0)) 1) 0 0)" "(128 255 0 255)"))
      (%light! dst x y w h map cell))

    (method jit! (self)
      (doc "Build and adopt the compiled pixel loops (JIT; ARM64 and x86-64 backends) now, if they draw the check pictures exactly as the pure-x loops do. Idempotent. Answers #t when they are in use, #f when they are not: the pure-x loops carry on, drawing the same pixels."
        (returns BOOL "#t when the compiled loops are in use")
        (sample "(Canvas jit!)" "#t"))
      (%jit-try!))))

(doc (provide x/gfx/canvas Canvas)
  "RGBA pictures in memory and the operations a frame is drawn with, the loops compiled and checked against pure x: (Canvas make w h), fill!, copy!, blend!, stamp!, nine!, text! and light!."
  (example "(Canvas pixel (Canvas make 1 1) 0 0)" "(0 0 0 0)"))

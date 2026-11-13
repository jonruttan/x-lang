; png-jit.x -- the compiled row loops behind (Png jit!).
;
; Loaded lazily by x/codec/png, never on its import: this module pulls the
; JIT toolchain, and the codec stays loadable and correct on a host with no
; JIT.  The pure-x loops in png.x are the reference and the fallback; the
; engine is adopted only after it undoes the filters of the check rows and
; converts the check pixels as the reference does.
;
; Two kinds of loop, each an integer function whose tail self-call is a jump.
; A filter loop undoes one row's filter in place: the row's address, the
; row above's (a row of zeros above the first), the index, the row's length
; and the bytes a pixel.  A pixel loop writes a row's pixels as RGBA for
; one layout of whole bytes: the next source pixel's address, the next destination's,
; the pixels left, the steps between source and between destination pixels,
; and the palette's address.
(module x/codec/png-jit)

(import x/tool/compile compile-asm)

(import x/core/doors int+ int= ptr->int)

; --- the expressions (generation time) ---

; Byte I of the row (R) and of the row above (U); the left neighbours read 0
; for the first pixel.
(def %pj-a '(if (< i bpp) 0 (%mem-byte-ref-at r (- i bpp))))
(def %pj-b '(%mem-byte-ref-at u i))
(def %pj-c '(if (< i bpp) 0 (%mem-byte-ref-at u (- i bpp))))
(def %pj-abs (fn (_ x) (list 'if (list '< x 0) (list '- 0 x) x)))

(def %pj-paeth
  ((fn (_ pa pb pc)
     (list 'if (list '< pb pa)
       (list 'if (list '< pc pb) %pj-c %pj-b)
       (list 'if (list '< pc pa) %pj-c %pj-a)))
   (%pj-abs (list '- %pj-b %pj-c))
   (%pj-abs (list '- %pj-a %pj-c))
   (%pj-abs (list '- (list '+ %pj-a %pj-b) (list '+ %pj-c %pj-c)))))

; The loop adding PREDICTOR to each byte of a row.
(def %pj-filter-expr
  (fn (_ predictor)
    (list 'fn '(self r u i n bpp)
      (list 'if '(< i n)
        (list 'do
          (list '%mem-byte-set-at! 'r 'i (list '& (list '+ '(%mem-byte-ref-at r i) predictor) 255))
          '(self r u (+ i 1) n bpp))
        0))))

; The loop writing a row's pixels, each one's four bytes from BYTES: an
; expression a destination byte, reading the source pixel at s.
(def %pj-pixel-expr
  (fn (_ bytes)
    (list 'fn '(self s d n ss ds p)
      (list 'if '(< 0 n)
        (list 'do
          (list '%mem-byte-set-at! 'd 0 (first bytes))
          (list '%mem-byte-set-at! 'd 1 (List ref 1 bytes))
          (list '%mem-byte-set-at! 'd 2 (List ref 2 bytes))
          (list '%mem-byte-set-at! 'd 3 (List ref 3 bytes))
          '(self (+ s ss) (+ d ds) (- n 1) ss ds p))
        0))))

(def %pj-s (fn (_ k) (list '%mem-byte-ref-at 's k)))
(def %pj-pal (fn (_ k) (list '%mem-byte-ref-at 'p (list '+ (list '<< '(%mem-byte-ref-at s 0) 2) k))))

; Each layout: its name, the source bytes a pixel, the RGBA it gives.  A
; 16-bit sample is its high byte, the first.
(def %pj-layouts
  (list (list (lit rgba8) 4 (list (%pj-s 0) (%pj-s 1) (%pj-s 2) (%pj-s 3)))
        (list (lit rgb8) 3 (list (%pj-s 0) (%pj-s 1) (%pj-s 2) 255))
        (list (lit grey8) 1 (list (%pj-s 0) (%pj-s 0) (%pj-s 0) 255))
        (list (lit greya8) 2 (list (%pj-s 0) (%pj-s 0) (%pj-s 0) (%pj-s 1)))
        (list (lit pal8) 1 (list (%pj-pal 0) (%pj-pal 1) (%pj-pal 2) (%pj-pal 3)))
        (list (lit rgba16) 8 (list (%pj-s 0) (%pj-s 2) (%pj-s 4) (%pj-s 6)))
        (list (lit rgb16) 6 (list (%pj-s 0) (%pj-s 2) (%pj-s 4) 255))
        (list (lit grey16) 2 (list (%pj-s 0) (%pj-s 0) (%pj-s 0) 255))
        (list (lit greya16) 4 (list (%pj-s 0) (%pj-s 0) (%pj-s 0) (%pj-s 2)))))

; --- build: compile, wire the drivers, and PROVE them against the reference ---
;
; check: (fn (_ unfilter pixels) -> #t) -- runs the reference's check rows
;        and pixels through a candidate pair and answers whether every byte
;        agreed with the reference's own.
;
; Answers (UNFILTER PIXELS), drop-ins for png.x's: (UNFILTER f r u n bpp)
; undoes filter f of the row of n bytes at r against the row at u, and
; (PIXELS layout put r o i n step pal) writes the n pixels of the row at r to
; o from byte i, step bytes apart, as RGBA.  Or raises: on a host with no
; assembler backend, a toolchain error, or any disagreement.  The caller
; guards; a raise means "stay pure-x".
(def png-jit-make
  (fn (_ check)
    (def filters
      (list (compile-asm (%pj-filter-expr %pj-a))
            (compile-asm (%pj-filter-expr %pj-b))
            (compile-asm (%pj-filter-expr (list '>> (list '+ %pj-a %pj-b) 1)))
            (compile-asm (%pj-filter-expr %pj-paeth))))
    (def layouts
      (List map (fn (_ l) (pair (first l) (pair (List ref 1 l) (compile-asm (%pj-pixel-expr (List ref 2 l))))))
        %pj-layouts))
    (Heap collect)
    (def unfilter
      (fn (_ f r u n bpp)
        (when (match ((int= f 0) #f) ((< 4 f) #f) (#t #t))
          ((List ref (int+ f -1) filters) (ptr->int r) (ptr->int u) 0 n bpp))))
    (def pixels
      (fn (_ layout put r o i n step pal)
        ((fn (_ l)
           ((rest (rest l)) (ptr->int r) (int+ (ptr->int o) i) n (first (rest l)) step
            (match ((eq? pal ()) 0) (#t (ptr->int pal)))))
         (Assoc entry layout layouts))))
    (unless (check unfilter pixels)
      (Err raise (lit state) "png-jit: engine disagrees with the pure-x loops" ()))
    (list unfilter pixels)))

; The codec reaches the maker through the catalogue: it loads this module
; inside the function that builds the engine, where an import is one the
; linter cannot see.
(prim-reg! (lit png) (lit jit-make) png-jit-make)

(doc (provide x/codec/png-jit png-jit-make)
  (example "(do (import x/codec/png-jit) (procedure? (prim-ref (lit png) (lit jit-make))))" "#t")
  "The compiled row loops (JIT, ARM64 and x86-64 backends) behind (Png jit!): the four PNG filters undone in place, and the 8-bit layouts written as RGBA, adopted only after they agree with the pure-x loops.")

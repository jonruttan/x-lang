; poly1305-jit.x -- the compiled block loop behind (Poly1305 jit!).
;
; Loaded lazily by x/codec/poly1305, as x/codec/chacha20-jit is by its
; cipher: this module pulls the JIT toolchain, and the codec must stay
; loadable and correct on a host with no JIT.  The pure-x %blocks! in
; poly1305.x is the reference and the fallback; this engine replaces only
; that loop -- the key clamp, the padded tail and the final reduction stay
; in x on both paths -- and is adopted only after it agrees with the
; reference on the accumulator it leaves.
;
; One compiled function does a block and calls itself for the next while
; the run and the region allow: the block's sixteen bytes as two 64-bit
; words (unaligned loads, which both backends allow) cut into five 26-bit
; limbs -- every piece masked AFTER its shift, since the lane's shift is
; arithmetic and a word's top bit is any byte's -- added to h, then the
; five-row product with r and the carries, in the shape poly1305-donna's
; 32-bit variant gives them.  A 4-byte word reads the block a byte at a
; time into poly1305.x's thirteen 10-bit limbs instead.  The self-call is a real call that conses its
; arguments, so a run is bounded, as inflate-jit's steps are.  It does not
; collect: the per-call garbage is the caller's to sweep.
(module x/codec/poly1305-jit)

(import x/type/vector)
(import x/tool/jit-group jit-group)

(import x/core/doors obj-ref obj-set! ptr->int ptr-ref-word ptr-set! ptr-set-word! str->ptr str-make)
(def %pj-M 67108863)

; A 4-byte word takes the limbs poly1305.x's narrow path does: thirteen of
; 10 bits, since a product of two 26-bit limbs is past the word.
(def %pj-narrow (< %word-size 8))
(def %pj-K (if %pj-narrow 13 5))

; scratch layout, one 256-byte buffer (words), on an 8-byte word:
;   0..4 h | 5..9 r0..r4 | 10..13 5*r1..5*r4 | 14 src | 15 pos | 16 end
;   17 run | 18 hibit | 19..23 d0..d4
; and on a 4-byte word, rv's twenty-six slots as poly1305.x lays them:
;   0..12 h | 13..25 r0..r12 | 26..38 5*r0..5*r12 | 39 src | 40 pos
;   41 end | 42 run | 43 hibit | 44..56 d0..d12
; src is the bytes' address; pos and end are byte offsets in them; run is
; how many more blocks this entry may do; hibit is the 2^128 bit in the
; top limb, or 0.
(def %pj-R %pj-K)
(def %pj-S (if %pj-narrow 26 10))
(def %pj-SRC (if %pj-narrow 39 14))
(def %pj-POS (+ %pj-SRC 1))
(def %pj-END (+ %pj-SRC 2))
(def %pj-RUN (+ %pj-SRC 3))
(def %pj-HI (+ %pj-SRC 4))
(def %pj-D (+ %pj-SRC 5))
(def %pj-HIBIT (if %pj-narrow 256 16777216))
(def %pj-run 128)

; --- expression builders (generation time) ---
(def %pj-C (fn (_ i) (list '%mem-ref 'a i)))
(def %pj-setC (fn (_ i v) (list '%mem-set! 'a i v)))
(def %pj-m (fn (_ e) (list '& e %pj-M)))
(def %pj-h (fn (_ i) (%pj-C i)))
(def %pj-r (fn (_ i) (%pj-C (+ %pj-R i))))
(def %pj-s (fn (_ i) (%pj-C (+ %pj-S (- i 1)))))
(def %pj-d (fn (_ i) (%pj-C (+ %pj-D i))))
(def %pj-word (fn (_ k) (list '%mem-ref-at (%pj-C %pj-SRC) (list '+ (list '>> (%pj-C %pj-POS) 3) k))))

; h += the block's limbs: t0 is bytes 0..7, t1 bytes 8..15; limb 2
; straddles them.
(def %pj-add-block
  (list 'do
    (%pj-setC 0 (list '+ (%pj-h 0) (%pj-m (%pj-word 0))))
    (%pj-setC 1 (list '+ (%pj-h 1) (%pj-m (list '>> (%pj-word 0) 26))))
    (%pj-setC 2 (list '+ (%pj-h 2)
                  (list '| (list '& (list '>> (%pj-word 0) 52) 4095)
                           (list '& (list '<< (%pj-word 1) 12) 67104768))))
    (%pj-setC 3 (list '+ (%pj-h 3) (%pj-m (list '>> (%pj-word 1) 14))))
    (%pj-setC 4 (list '+ (%pj-h 4)
                  (list '| (list '& (list '>> (%pj-word 1) 40) 16777215) (%pj-C %pj-HI))))))

; d_i = sum over j of h_j times the factor the row wants: r_(i-j) for
; j <= i, else 5*r_(5+i-j).
(def %pj-row
  (fn (_ i)
    (def term
      (fn (_ j)
        (list '* (%pj-h j) (if (<= j i) (%pj-r (- i j)) (%pj-s (- (+ 5 i) j))))))
    (%pj-setC (+ %pj-D i)
      (list '+ (list '+ (term 0) (term 1))
               (list '+ (list '+ (term 2) (term 3)) (term 4))))))

(def %pj-multiply (list 'do (%pj-row 0) (%pj-row 1) (%pj-row 2) (%pj-row 3) (%pj-row 4)))

; the carries, in place: each d gets the one below's overflow, the top's
; folds into h0 times five, and h1 takes h0's
(def %pj-carry
  (list 'do
    (%pj-setC (+ %pj-D 1) (list '+ (%pj-d 1) (list '>> (%pj-d 0) 26)))
    (%pj-setC (+ %pj-D 2) (list '+ (%pj-d 2) (list '>> (%pj-d 1) 26)))
    (%pj-setC (+ %pj-D 3) (list '+ (%pj-d 3) (list '>> (%pj-d 2) 26)))
    (%pj-setC (+ %pj-D 4) (list '+ (%pj-d 4) (list '>> (%pj-d 3) 26)))
    (%pj-setC 0 (list '+ (%pj-m (%pj-d 0)) (list '* (list '>> (%pj-d 4) 26) 5)))
    (%pj-setC 1 (list '+ (%pj-m (%pj-d 1)) (list '>> (%pj-h 0) 26)))
    (%pj-setC 0 (%pj-m (%pj-h 0)))
    (%pj-setC 2 (%pj-m (%pj-d 2)))
    (%pj-setC 3 (%pj-m (%pj-d 3)))
    (%pj-setC 4 (%pj-m (%pj-d 4)))))

; --- the same block on thirteen 10-bit limbs (a 4-byte word) ---
(def %pj-seq
  (fn (_ n f) (pair 'do ((fn (self i) (if (= i n) () (pair (f i) (self (+ i 1))))) 0))))
(def %pj-sum
  (fn (self terms) (if (null? (rest terms)) (first terms) (list '+ (first terms) (self (rest terms))))))

; byte k of the block, zero past its sixteen
(def %pj-byte
  (fn (_ k)
    (if (< k 16) (list '%mem-byte-ref-at (%pj-C %pj-SRC) (list '+ (%pj-C %pj-POS) k)) 0)))

; limb j is bits [10j, 10j + 10) of the block, which three bytes cover
(def %pj-limb10
  (fn (_ j)
    (def at (* j 10))
    (def k (>> at 3))
    (list '& (list '>> (list '| (%pj-byte k)
                              (list '| (list '<< (%pj-byte (+ k 1)) 8) (list '<< (%pj-byte (+ k 2)) 16)))
                       (& at 7))
             1023)))

(def %pj-add-block-10
  (%pj-seq 13
    (fn (_ j)
      (%pj-setC j (if (= j 12)
                    (list '+ (list '+ (%pj-h j) (%pj-limb10 j)) (%pj-C %pj-HI))
                    (list '+ (%pj-h j) (%pj-limb10 j)))))))

; d_i = sum over j of h_j times r_(i-j) for j <= i, else 5*r_(13+i-j)
(def %pj-multiply-10
  (%pj-seq 13
    (fn (_ i)
      (%pj-setC (+ %pj-D i)
        (%pj-sum ((fn (self j)
                    (if (= j 13) ()
                      (pair (list '* (%pj-h j) (if (<= j i) (%pj-r (- i j)) (%pj-C (+ %pj-S (- (+ 13 i) j)))))
                            (self (+ j 1)))))
                  0))))))

; each d takes the one below's carry and leaves its low 10 bits in h; the
; top's carry folds into h0 times five, and h1 takes h0's
(def %pj-carry-10
  (list 'do
    (%pj-setC 0 (list '& (%pj-d 0) 1023))
    (%pj-seq 12
      (fn (_ i)
        (list 'do
          (%pj-setC (+ %pj-D (+ i 1)) (list '+ (%pj-d (+ i 1)) (list '>> (%pj-d i) 10)))
          (%pj-setC (+ i 1) (list '& (%pj-d (+ i 1)) 1023)))))
    (%pj-setC 0 (list '+ (%pj-h 0) (list '* (list '>> (%pj-d 12) 10) 5)))
    (%pj-setC 1 (list '+ (%pj-h 1) (list '>> (%pj-h 0) 10)))
    (%pj-setC 0 (list '& (%pj-h 0) 1023))))

(def %pj-parts
  (if %pj-narrow
    (list %pj-add-block-10 %pj-multiply-10 %pj-carry-10)
    (list %pj-add-block %pj-multiply %pj-carry)))

(def %pj-step-expr
  (list 'fn '(self a r)
    (list 'do (first %pj-parts) (first (rest %pj-parts))
      (first (rest (rest %pj-parts)))
      (%pj-setC %pj-POS (list '+ (%pj-C %pj-POS) 16))
      (%pj-setC %pj-RUN (list '- (%pj-C %pj-RUN) 1))
      (list 'if (list '< (%pj-C %pj-RUN) 1) 0
        (list 'if (list '< (%pj-C %pj-POS) (%pj-C %pj-END)) (list 'self 'a 0) 0)))))

; --- build: compile, wire a driver, and PROVE it against the reference ---
;
; ref: the pure-x block loop, (fn (_ h rv s i end hibit)) -- the oracle.
; rv:  an r vector as the codec builds one, for the check.
;
; Returns a function of the same shape driving the compiled step, or
; raises -- on a host whose architecture has no assembler backend, on any
; toolchain error, or on DISAGREEMENT with the reference.
(def poly1305-jit-make
  (fn (_ ref rv)
    (jit-group "poly1305-jit" (fn (_) (list %pj-step-expr))
      (fn (_ fns replayed?) (%pj-wire ref rv (first fns) replayed?)))))

; The engine over the compiled step, proven against ref unless the step
; was replayed from the cache group, where it was proven when stored.
(def %pj-wire
  (fn (_ ref rv %step replayed?)
    ; the build's garbage goes before the engine runs; a collect here has
    ; nothing of the caller's live (the maker is called once, to build) --
    ; and a replay compiled nothing, so it has no garbage to drop and skips
    ; the collect, which marks the whole live heap
    (unless replayed? (Heap collect))
    (def %buf (str-make 256))
    (def %ptr (str->ptr %buf))
    (def %addr (ptr->int %ptr))
    (def %poke (fn (_ i v) (ptr-set-word! %ptr (* i %word-size) v)))
    (def %peek (fn (_ i) (ptr-ref-word %ptr (* i %word-size))))
    (def %engine
      (fn (_ h rv s i end hibit)
        ((fn (self k)
           (unless (= k %pj-K) (do (%poke k (obj-ref h (+ k 1))) (self (+ k 1))))) 0)
        ((fn (self k)
           (unless (= k (- %pj-SRC %pj-R)) (do (%poke (+ %pj-R k) (obj-ref rv (+ k 1))) (self (+ k 1))))) 0)
        (%poke %pj-SRC (ptr->int (str->ptr s)))
        (%poke %pj-END end)
        (%poke %pj-HI hibit)
        ; each entry does up to a run of blocks and leaves pos past them
        ((fn (self pos)
           (when (< pos end)
             (%poke %pj-POS pos)
             (%poke %pj-RUN %pj-run)
             (%step %addr 0)
             (self (%peek %pj-POS)))) i)
        ((fn (self k)
           (unless (= k %pj-K) (do (obj-set! h (+ k 1) (%peek k)) (self (+ k 1))))) 0)))
    ; the differential check: the accumulator after a run of blocks must
    ; match the reference's, over every byte value, with and without the
    ; high bit, and across more blocks than one entry does
    (def %ramp
      (fn (_ n)
        (def r (str-make n))
        (def p (str->ptr r))
        ((fn (self k) (unless (= k n) (do (ptr-set! p k (& (* k 7) 255) 1) (self (+ k 1))))) 0)
        r))
    (def %same
      (fn (self x y k)
        (if (= k (+ %pj-K 1)) #t
          (if (= (obj-ref x k) (obj-ref y k)) (self x y (+ k 1)) #f))))
    (def %check
      (fn (_ s i end hibit)
        (def hx (Vector make %pj-K 0))
        (def hy (Vector make %pj-K 0))
        (%engine hx rv s i end hibit)
        (ref hy rv s i end hibit)
        (unless (%same hx hy 1)
          (Err raise 'state "poly1305-jit: engine disagrees with the pure-x block loop" ()))))
    (unless replayed?
      (do (def %in (%ramp 4096))
          (%check %in 0 16 %pj-HIBIT)
          (%check %in 0 16 0)
          (%check %in 16 272 %pj-HIBIT)
          (%check %in 0 4096 %pj-HIBIT)
          (%check %in 0 0 %pj-HIBIT)))
    %engine))

; The codec reaches the maker through the catalogue: it loads this module
; inside the function that builds its engine, and a name imported there is
; one the linter cannot see.
(prim-reg! (lit poly1305) (lit jit-make) poly1305-jit-make)

(doc (provide x/codec/poly1305-jit poly1305-jit-make)
  "The compiled Poly1305 block loop (JIT, ARM64, x86-64 and 32-bit ARM backends); built and adopted only via (Poly1305 jit!) after proving agreement with the pure-x loop.")

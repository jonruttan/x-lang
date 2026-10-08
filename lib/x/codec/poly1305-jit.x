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
; 32-bit variant gives them.  The self-call is a real call that conses its
; arguments, so a run is bounded, as inflate-jit's steps are.  It does not
; collect: the per-call garbage is the caller's to sweep.
(module x/codec/poly1305-jit)

(import x/type/vector)
(import x/tool/compile compile-asm)

(def %pj-make-str (prim-ref (lit str) (lit make)))
(def %pj-str->ptr (prim-ref (lit str) (lit ->ptr)))
(def %pj-ptr->int (prim-ref (lit ptr) (lit ->int)))
(def %pj-pset (prim-ref (lit ptr) (lit set-word!)))
(def %pj-pref (prim-ref (lit ptr) (lit ref-word)))
(def %pj-pset1 (prim-ref (lit ptr) (lit set!)))
(def %pj-oref (prim-ref (lit obj) (lit ref)))
(def %pj-oset! (prim-ref (lit obj) (lit set!)))
(def %pj-M 67108863)

; scratch layout, one 256-byte buffer (words):
;   0..4 h | 5..9 r0..r4 | 10..13 5*r1..5*r4 | 14 src | 15 pos | 16 end
;   17 run | 18 hibit | 19..23 d0..d4
; src is the bytes' address; pos and end are byte offsets in them; run is
; how many more blocks this entry may do; hibit is 1<<24 or 0.
(def %pj-R 5)
(def %pj-S 10)
(def %pj-SRC 14)
(def %pj-POS 15)
(def %pj-END 16)
(def %pj-RUN 17)
(def %pj-HI 18)
(def %pj-D 19)
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

(def %pj-step-expr
  (list 'fn '(self a r)
    (list 'do %pj-add-block %pj-multiply %pj-carry
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
    (def %step (compile-asm %pj-step-expr))
    ; the build's garbage goes before the engine runs; a collect here has
    ; nothing of the caller's live (the maker is called once, to build)
    (Heap collect)
    (def %buf (%pj-make-str 256))
    (def %ptr (%pj-str->ptr %buf))
    (def %addr (%pj-ptr->int %ptr))
    (def %poke (fn (_ i v) (%pj-pset %ptr (* i 8) v)))
    (def %peek (fn (_ i) (%pj-pref %ptr (* i 8))))
    (def %engine
      (fn (_ h rv s i end hibit)
        ((fn (self k)
           (unless (= k 5) (do (%poke k (%pj-oref h (+ k 1))) (self (+ k 1))))) 0)
        ((fn (self k)
           (unless (= k 9) (do (%poke (+ %pj-R k) (%pj-oref rv (+ k 1))) (self (+ k 1))))) 0)
        (%poke %pj-SRC (%pj-ptr->int (%pj-str->ptr s)))
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
           (unless (= k 5) (do (%pj-oset! h (+ k 1) (%peek k)) (self (+ k 1))))) 0)))
    ; the differential check: the accumulator after a run of blocks must
    ; match the reference's, over every byte value, with and without the
    ; high bit, and across more blocks than one entry does
    (def %ramp
      (fn (_ n)
        (def r (%pj-make-str n))
        (def p (%pj-str->ptr r))
        ((fn (self k) (unless (= k n) (do (%pj-pset1 p k (& (* k 7) 255) 1) (self (+ k 1))))) 0)
        r))
    (def %same
      (fn (self x y k)
        (if (= k 6) #t
          (if (= (%pj-oref x k) (%pj-oref y k)) (self x y (+ k 1)) #f))))
    (def %check
      (fn (_ s i end hibit)
        (def hx (Vector make 5 0))
        (def hy (Vector make 5 0))
        (%engine hx rv s i end hibit)
        (ref hy rv s i end hibit)
        (unless (%same hx hy 1)
          (Err raise 'state "poly1305-jit: engine disagrees with the pure-x block loop" ()))))
    (def %in (%ramp 4096))
    (%check %in 0 16 16777216)
    (%check %in 0 16 0)
    (%check %in 16 272 16777216)
    (%check %in 0 4096 16777216)
    (%check %in 0 0 16777216)
    %engine))

; The codec reaches the maker through the catalogue: it loads this module
; inside the function that builds its engine, and a name imported there is
; one the linter cannot see.
(prim-reg! (lit poly1305) (lit jit-make) poly1305-jit-make)

(doc (provide x/codec/poly1305-jit poly1305-jit-make)
  "The compiled Poly1305 block loop (JIT, ARM64 and x86-64 backends); built and adopted only via (Poly1305 jit!) after proving agreement with the pure-x loop.")

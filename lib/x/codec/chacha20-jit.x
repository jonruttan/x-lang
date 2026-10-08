; chacha20-jit.x -- the compiled block engine behind (ChaCha20 jit!).
;
; Loaded lazily by x/codec/chacha20, as x/codec/sha-jit is by the digests:
; this module pulls the JIT toolchain, and the codec must stay loadable
; and correct on a host with no JIT.  The pure-x cipher in chacha20.x is
; the reference and the fallback; this engine is an accelerator only, and
; chacha20-jit-make adopts it only after it AGREES with the reference on the RFC's
; vectors and on regions that end inside a block -- any disagreement is a
; raise, and the caller's guard turns a raise into "stay pure-x".
;
; One compiled function serves a block, entered through an r=-1 sentinel
; as sha-jit's rounds are: the entry copies the state into the working
; words; each call then is one double round -- eight quarter rounds, the
; whole thing straight-line, no indexing -- and the tenth sums the state
; back in, XORs the block into the output as eight 64-bit words, and
; carries the counter.  A block the region ends inside is walked a byte a
; call instead, each behind the region's bound, so that is the one path
; with a test per byte.  The driver here, in x, runs it once a block.
; It does not collect: a collect with a caller's long list live overruns
; the collector's recursive mark (inflate-jit), and the per-block garbage
; is the caller's to sweep.
(module x/codec/chacha20-jit)

(import x/tool/compile compile-asm)

(def %cj-make-str (prim-ref (lit str) (lit make)))
(def %cj-str->ptr (prim-ref (lit str) (lit ->ptr)))
(def %cj-ptr->int (prim-ref (lit ptr) (lit ->int)))
(def %cj-pset (prim-ref (lit ptr) (lit set-word!)))
(def %cj-pref (prim-ref (lit ptr) (lit ref-word)))
(def %cj-pset1 (prim-ref (lit ptr) (lit set!)))
(def %cj-byte-ref (prim-ref (lit str) (lit byte-ref)))
(def %cj-char->int (prim-ref (lit char) (lit ->int)))
(def %cj-M 4294967295)

; scratch layout, one 512-byte buffer (words):
;   0..15 state | 16..31 working words | 32 in | 33 out | 34 pos | 35 len
;   36 run
; in and out are addresses; pos is the block's offset in the region, and
; run how many more whole blocks this entry may do before returning.
(def %cj-W 16)
(def %cj-IN 32)
(def %cj-OUT 33)
(def %cj-POS 34)
(def %cj-LEN 35)
(def %cj-RUN 36)

; Whole blocks an entry does before returning to the driver: the self-call
; is a real call that conses its arguments, so a run is bounded, as
; inflate-jit's steps are; sixteen blocks is 192 frames.
(def %cj-run 16)

; --- expression builders (generation time) ---
(def %cj-C (fn (_ i) (list '%mem-ref 'a i)))
(def %cj-setC (fn (_ i v) (list '%mem-set! 'a i v)))
(def %cj-m32 (fn (_ e) (list '& e %cj-M)))
(def %cj-rotl (fn (_ x n) (list '& (list '| (list '<< x n) (list '>> x (- 32 n))) %cj-M)))
(def %cj-seq
  (fn (_ n f) (pair 'do ((fn (self i) (if (= i n) () (pair (f i) (self (+ i 1))))) 0))))

; The quarter round (RFC 8439 2.1) on working words a b c d.
(def %cj-qr
  (fn (_ a b c d)
    (def A (%cj-C (+ %cj-W a))) (def B (%cj-C (+ %cj-W b)))
    (def Cc (%cj-C (+ %cj-W c))) (def D (%cj-C (+ %cj-W d)))
    (list 'do
      (%cj-setC (+ %cj-W a) (%cj-m32 (list '+ A B)))
      (%cj-setC (+ %cj-W d) (%cj-rotl (list '^ D A) 16))
      (%cj-setC (+ %cj-W c) (%cj-m32 (list '+ Cc D)))
      (%cj-setC (+ %cj-W b) (%cj-rotl (list '^ B Cc) 12))
      (%cj-setC (+ %cj-W a) (%cj-m32 (list '+ A B)))
      (%cj-setC (+ %cj-W d) (%cj-rotl (list '^ D A) 8))
      (%cj-setC (+ %cj-W c) (%cj-m32 (list '+ Cc D)))
      (%cj-setC (+ %cj-W b) (%cj-rotl (list '^ B Cc) 7)))))

; A column round then a diagonal round (2.3).
(def %cj-double-round
  (list 'do
    (%cj-qr 0 4 8 12) (%cj-qr 1 5 9 13) (%cj-qr 2 6 10 14) (%cj-qr 3 7 11 15)
    (%cj-qr 0 5 10 15) (%cj-qr 1 6 11 12) (%cj-qr 2 7 8 13) (%cj-qr 3 4 9 14)))

(def %cj-load (%cj-seq 16 (fn (_ i) (%cj-setC (+ %cj-W i) (%cj-C i)))))

(def %cj-sum
  (%cj-seq 16 (fn (_ i) (%cj-setC (+ %cj-W i) (%cj-m32 (list '+ (%cj-C (+ %cj-W i)) (%cj-C i)))))))

; A whole block's XOR, eight 64-bit words: input and output words k of
; the block (unaligned loads and stores, which both backends allow),
; against working words 2k and 2k+1 side by side.  pos is a multiple of
; 64, so pos>>3 is the block's first word.
(def %cj-xor-word
  (fn (_ k)
    (def at (list '+ (list '>> (%cj-C %cj-POS) 3) k))
    (list '%mem-set-at! (%cj-C %cj-OUT) at
      (list '^ (list '%mem-ref-at (%cj-C %cj-IN) at)
               (list '| (%cj-C (+ %cj-W (* 2 k)))
                        (list '<< (%cj-C (+ %cj-W (+ (* 2 k) 1))) 32))))))

; The counter: word 12, carried into word 13.
(def %cj-bump
  (list 'do
    (%cj-setC 12 (%cj-m32 (list '+ (%cj-C 12) 1)))
    (list 'if (list '= (%cj-C 12) 0)
      (%cj-setC 13 (%cj-m32 (list '+ (%cj-C 13) 1)))
      0)))

; A short last block, one byte a call: r counts from 11, so byte i of the
; block is r-11 -- byte i&3 of working word i>>2, little-endian -- and
; the walk ends at the region's end, with the counter carried.
(def %cj-tail-byte
  ((fn (_ i)
     (def at (list '+ (%cj-C %cj-POS) i))
     (list 'if (list '< at (%cj-C %cj-LEN))
       (list 'do
         (list '%mem-byte-set-at! (%cj-C %cj-OUT) at
           (list '^ (list '%mem-byte-ref-at (%cj-C %cj-IN) at)
                    (list '& (list '>> (list '%mem-ref-at 'a (list '+ %cj-W (list '>> i 2)))
                                   (list '<< (list '& i 3) 3))
                             255)))
         (list 'self 'a (list '+ 'r 1)))
       (list 'do %cj-bump (%cj-setC %cj-POS (list '+ (%cj-C %cj-POS) 64)))))
   (list '- 'r 11)))

; The tenth round done: the state summed in, then a whole block's words
; and straight on to the next block while the run and the region allow,
; or the byte walk for a block the region ends inside.  Either way pos
; has moved past the block when the entry returns.
(def %cj-finish
  (list 'do %cj-sum
    (list 'if (list '< (list '+ (%cj-C %cj-POS) 64) (list '+ (%cj-C %cj-LEN) 1))
      (list 'do (%cj-seq 8 %cj-xor-word) %cj-bump
        (%cj-setC %cj-POS (list '+ (%cj-C %cj-POS) 64))
        (%cj-setC %cj-RUN (list '- (%cj-C %cj-RUN) 1))
        (list 'if (list '< (%cj-C %cj-RUN) 1) 0
          (list 'if (list '< (%cj-C %cj-POS) (%cj-C %cj-LEN)) (list 'self 'a -1) 0)))
      (list 'self 'a 11))))

(def %cj-block-expr
  (list 'fn '(self a r)
    (list 'if (list '< 'r 0)
      (list 'do %cj-load (list 'self 'a 0))
      (list 'if (list '< 'r 10)
        (list 'do %cj-double-round (list 'self 'a (list '+ 'r 1)))
        (list 'if (list '= 'r 10) %cj-finish %cj-tail-byte)))))

; --- build: compile, wire a driver, and PROVE it against the reference ---
;
; ref: the pure-x cipher, (fn (_ st s start len) -> out) -- the oracle.
;
; Returns a function of the same shape driving the compiled block, or
; raises -- on a host whose architecture has no assembler backend, on any
; toolchain error, or on DISAGREEMENT with the reference.
(def chacha20-jit-make
  (fn (_ ref)
    (def %block (compile-asm %cj-block-expr))
    ; the build's garbage goes before the engine runs; a collect here has
    ; nothing of the caller's live (the maker is called once, to build)
    (Heap collect)
    (def %buf (%cj-make-str 512))
    (def %ptr (%cj-str->ptr %buf))
    (def %addr (%cj-ptr->int %ptr))
    (def %poke (fn (_ i v) (%cj-pset %ptr (* i 8) v)))
    (def %peek (fn (_ i) (%cj-pref %ptr (* i 8))))
    (def %engine
      (fn (_ st s start len)
        (def out (%cj-make-str len))
        ((fn (self i ws)
           (unless (null? ws) (do (%poke i (first ws)) (self (+ i 1) (rest ws))))) 0 st)
        (%poke %cj-IN (+ (%cj-ptr->int (%cj-str->ptr s)) start))
        (%poke %cj-OUT (%cj-ptr->int (%cj-str->ptr out)))
        (%poke %cj-LEN len)
        ; each entry does up to a run of blocks and leaves pos past them
        ((fn (self pos)
           (when (< pos len)
             (%poke %cj-POS pos)
             (%poke %cj-RUN %cj-run)
             (%block %addr -1)
             (self (%peek %cj-POS)))) 0)
        out))
    ; the differential check: the RFC's block and encryption vectors, and
    ; regions ending inside a block, so the bound on every byte is proven
    (def %same
      (fn (self x y i n)
        (if (= i n) #t
          (if (= (%cj-char->int (%cj-byte-ref x i)) (%cj-char->int (%cj-byte-ref y i)))
            (self x y (+ i 1) n)
            #f))))
    (def %check
      (fn (_ st s start len)
        (unless (%same (%engine st s start len) (ref st s start len) 0 len)
          (Err raise 'state "chacha20-jit: engine disagrees with the pure-x cipher" ()))))
    ; bytes 0..n-1 of a region, so NULs and every byte value are in play
    (def %ramp
      (fn (_ n)
        (def r (%cj-make-str n))
        (def p (%cj-str->ptr r))
        ((fn (self i) (unless (= i n) (do (%cj-pset1 p i (& i 255) 1) (self (+ i 1))))) 0)
        r))
    (def %st (fn (_ counter) (List append (list 1634760805 857760878 2036477234 1797285236
                                                 50462976 117835012 185207048 252579084
                                                 319951120 387323156 454695192 522067228)
                                           (list counter 150994944 1241513984 0))))
    (def %in (%ramp 200))
    (%check (%st 1) %in 0 64)
    (%check (%st 1) %in 0 1)
    (%check (%st 1) %in 0 63)
    (%check (%st 1) %in 0 65)
    (%check (%st 4294967295) %in 7 150)
    (%check (%st 0) %in 0 0)
    %engine))

; The codec reaches the maker through the catalogue: it loads this module
; inside the function that builds its engine, and a name imported there is
; one the linter cannot see.
(prim-reg! (lit chacha20) (lit jit-make) chacha20-jit-make)

(doc (provide x/codec/chacha20-jit chacha20-jit-make)
  "The compiled ChaCha20 block engine (JIT, ARM64 and x86-64 backends); built and adopted only via (ChaCha20 jit!) after proving agreement with the pure-x cipher.")

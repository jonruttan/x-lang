; sha512-jit.x -- the compiled SHA-512 engine behind (Sha512 jit!).
;
; Loaded lazily by x/codec/sha512, as x/codec/sha-jit is by the 32-bit
; digests: this module pulls the JIT toolchain, and the codec must stay
; loadable -- and correct -- on a host with no JIT.  The pure-x digest
; in sha512.x, on halves, is the reference and the fallback; this engine
; is an accelerator only, and is adopted only after it AGREES with that
; digest on the standard's vectors plus multi-block padding cases.
;
; The shape is sha-jit's fold+fill: the rounds, with the working-state
; load and the H accumulate folded in, are one compiled function entered
; through a t=-1 sentinel, and the fill -- sixteen words from eight padded
; byte reads each -- another, driven per block from x.  What the width
; changes: the lane HAS 64-bit words, so a word is one scratch slot and
; an addition needs no mask; but the lane's right shift is arithmetic, so
; every logical shift here is masked after, and a rotation is the masked
; shift or'd with the left shift.  The scratch holds K and H as 64-bit
; words poked and read as two 4-byte halves, which keeps the x side of
; the driver on 32-bit values the way the codec is.
(module x/codec/sha512-jit)

(import x/tool/compile compile-asm)

(def %s5-make-str (prim-ref (lit str) (lit make)))
(def %s5-str->ptr (prim-ref (lit str) (lit ->ptr)))
(def %s5-ptr->int (prim-ref (lit ptr) (lit ->int)))
(def %s5-pset (prim-ref (lit ptr) (lit set!)))
(def %s5-pref (prim-ref (lit ptr) (lit ref)))
(def %s5-oref (prim-ref (lit obj) (lit ref)))
(def %s5-byte-ref (prim-ref (lit str) (lit byte-ref)))
(def %s5-char->int (prim-ref (lit char) (lit ->int)))

; scratch layout, one 1024-byte buffer (64-bit words):
;   0..15 W ring | 16..23 working state | 24 t1 25 t2 | 26 base 27 len
;   28 total | 32..111 K | 112..119 H
(def %s5-KB 32)
(def %s5-HB 112)

; --- expression builders (generation time) ---
(def %s5-C  (fn (_ i) (list '%mem-ref 'a i)))
(def %s5-AT (fn (_ e) (list '%mem-ref-at 'a e)))
(def %s5-setC (fn (_ i v) (list '%mem-set! 'a i v)))
(def %s5-setAT (fn (_ e v) (list '%mem-set-at! 'a e v)))
; the mask that makes an arithmetic shift right by n logical: 64-n ones
(def %s5-lmask (fn (_ n) (if (= n 1) 9223372036854775807 (- (<< 1 (- 64 n)) 1))))
(def %s5-shr (fn (_ x n) (list '& (list '>> x n) (%s5-lmask n))))
(def %s5-rotr (fn (_ x n) (list '| (%s5-shr x n) (list '<< x (- 64 n)))))
(def %s5-bs0 (fn (_ x) (list '^ (%s5-rotr x 28) (list '^ (%s5-rotr x 34) (%s5-rotr x 39)))))
(def %s5-bs1 (fn (_ x) (list '^ (%s5-rotr x 14) (list '^ (%s5-rotr x 18) (%s5-rotr x 41)))))
(def %s5-ss0 (fn (_ x) (list '^ (%s5-rotr x 1)  (list '^ (%s5-rotr x 8)  (%s5-shr x 7)))))
(def %s5-ss1 (fn (_ x) (list '^ (%s5-rotr x 19) (list '^ (%s5-rotr x 61) (%s5-shr x 6)))))
(def %s5-ch  (fn (_ x y z) (list '^ (list '& x y) (list '& (list '~ x) z))))
(def %s5-maj (fn (_ x y z) (list '^ (list '& x y) (list '^ (list '& x z) (list '& y z)))))
(def %s5-A (%s5-C 16)) (def %s5-B (%s5-C 17)) (def %s5-Cc (%s5-C 18)) (def %s5-D (%s5-C 19))
(def %s5-E (%s5-C 20)) (def %s5-F (%s5-C 21)) (def %s5-G (%s5-C 22)) (def %s5-H (%s5-C 23))
(def %s5-w (fn (_ off) (%s5-AT (list '& (list '- 't off) 15))))

(def %s5-extend
  (%s5-setAT (list '& 't 15)
    (list '+ (list '+ (%s5-ss1 (%s5-w 2)) (%s5-w 7))
             (list '+ (%s5-ss0 (%s5-w 15)) (%s5-w 16)))))

(def %s5-round-body
  (list 'do
    (list 'if (list '< 't 16) 0 %s5-extend)
    (%s5-setC 24 (list '+ (list '+ %s5-H (%s5-bs1 %s5-E))
                       (list '+ (%s5-ch %s5-E %s5-F %s5-G)
                             (list '+ (%s5-AT (list '+ %s5-KB 't))
                                   (%s5-AT (list '& 't 15))))))
    (%s5-setC 25 (list '+ (%s5-bs0 %s5-A) (%s5-maj %s5-A %s5-B %s5-Cc)))
    (%s5-setC 23 %s5-G) (%s5-setC 22 %s5-F) (%s5-setC 21 %s5-E)
    (%s5-setC 20 (list '+ %s5-D (%s5-C 24)))
    (%s5-setC 19 %s5-Cc) (%s5-setC 18 %s5-B) (%s5-setC 17 %s5-A)
    (%s5-setC 16 (list '+ (%s5-C 24) (%s5-C 25)))
    (list 'self 'a (list '+ 't 1))))

(def %s5-seq
  (fn (_ n f) (pair 'do ((fn (self i) (if (= i n) () (pair (f i) (self (+ i 1))))) 0))))
(def %s5-load-h (%s5-seq 8 (fn (_ i) (%s5-setC (+ 16 i) (%s5-C (+ %s5-HB i))))))
(def %s5-store-h
  (%s5-seq 8 (fn (_ i) (%s5-setC (+ %s5-HB i) (list '+ (%s5-C (+ %s5-HB i)) (%s5-C (+ 16 i)))))))
(def %s5-rounds-expr
  (list 'fn '(self a t)
    (list 'if (list '< 't 0)
      (list 'do %s5-load-h (list 'self 'a 0))
      (list 'if (list '= 't 80) %s5-store-h %s5-round-body))))

; the W fill: sixteen words from eight padded byte reads each, against
; the message's raw address; the FIPS padding is compiled arithmetic on
; len/total in slots 27/28, block base in 26: the message, 0x80, zeros,
; and the bit length in the last eight bytes (the eight before them are
; zeros too, as the length's top half).
(def %s5-pad-byte
  (fn (_ k)
    (def i (if (= k 0) (%s5-C 26) (list '+ (%s5-C 26) k)))
    (def L (%s5-C 27))
    (def T (%s5-C 28))
    (list 'if (list '< i L)
      (list '%mem-byte-ref-at 'm i)
      (list 'if (list '= i L) 128
        (list 'if (list '< i (list '- T 8)) 0
          (list '& (list '>> (list '<< L 3)
                         (list '<< (list '- (list '- T 1) i) 3)) 255))))))
; One word a call, t being the word: eight padded reads at byte 8t+k of
; the block -- sha-jit unrolls all sixteen words, but at eight reads of
; twenty-odd nodes each a word, sixteen in one function is past what the
; assembler's buffer takes, so the fill steps.
(def %s5-fill-word
  ((fn (self k acc)
     (if (< k 0) acc
       (self (- k 1) (list '| (list '<< (%s5-pad-byte (list '+ (list '<< 't 3) k)) (* 8 (- 7 k))) acc))))
   6 (%s5-pad-byte (list '+ (list '<< 't 3) 7))))
(def %s5-fill-expr
  (list 'fn '(self a m t)
    (list 'if (list '= 't 16) 0
      (list 'do (%s5-setAT 't %s5-fill-word)
                (list 'self 'a 'm (list '+ 't 1))))))

; --- build: compile, wire a driver, and PROVE it against the reference ---
;
; k:   the codec's K vector, 160 halves, hi then lo (slots 2t+1, 2t+2).
; ih:  the initial H as sixteen halves, hi then lo.
; ref: the pure-x digest, (fn (_ s [n]) -> sixteen halves) -- the oracle.
;
; Returns (fn (_ s [n]) -> sixteen halves) driving the compiled pair, or
; raises -- on a host whose architecture has no assembler backend, on any
; toolchain error, or on DISAGREEMENT with the reference.  The caller
; guards; a raise means "stay pure-x", never a wrong digest.
(def sha512-jit-make
  (fn (_ k ih ref)
    (def %rounds (compile-asm %s5-rounds-expr))
    (def %fill (compile-asm %s5-fill-expr))
    ; drop the whole build's remaining garbage before the digest phase
    (Heap collect)
    (def %buf (%s5-make-str 1024))
    (def %ptr (%s5-str->ptr %buf))
    (def %addr (%s5-ptr->int %ptr))
    ; a 64-bit slot as its two halves: lo at the slot's first four bytes
    (def %poke-halves (fn (_ i hi lo) (%s5-pset %ptr (* i 8) lo 4) (%s5-pset %ptr (+ (* i 8) 4) hi 4)))
    (def %poke (fn (_ i v) (%s5-pset %ptr (* i 8) v 8)))
    (def %peek-hi (fn (_ i) (%s5-pref %ptr (+ (* i 8) 4) 4)))
    (def %peek-lo (fn (_ i) (%s5-pref %ptr (* i 8) 4)))
    ((fn (self t)
       (unless (= t 80)
         (do (%poke-halves (+ %s5-KB t) (%s5-oref k (+ (* t 2) 1)) (%s5-oref k (+ (* t 2) 2)))
             (self (+ t 1))))) 0)
    (def %disagrees "sha512-jit: engine disagrees with the pure-x digest")
    (def %digest
      (fn (_ s . n)
        (def len (match ((null? n) (Str8 length s)) (#t (first n))))
        (def total (<< (+ (>> (+ len 16) 7) 1) 7))
        (def maddr (%s5-ptr->int (%s5-str->ptr s)))
        (%poke 27 len)
        (%poke 28 total)
        ((fn (self i hs)
           (unless (null? hs)
             (do (%poke-halves (+ %s5-HB i) (first hs) (first (rest hs)))
                 (self (+ i 1) (rest (rest hs)))))) 0 ih)
        ; one native call pair a block; the per-block garbage is the
        ; caller's to sweep (a collect here could overrun the collector's
        ; mark with a caller's long list live)
        ((fn (self b)
           (unless (= b total)
             (do (%poke 26 b)
                 (%fill %addr maddr 0)
                 (%rounds %addr -1)
                 (self (+ b 128))))) 0)
        ((fn (self i acc)
           (if (< i 0) acc
             (self (- i 1) (pair (%peek-hi (+ %s5-HB i)) (pair (%peek-lo (+ %s5-HB i)) acc)))))
         7 ())))
    ; the differential check: FIPS vectors, a two-block input, and an
    ; input that lands the padding in a block of its own
    (def %same
      (fn (self xs ys)
        (match ((null? xs) (null? ys))
               ((null? ys) #f)
               ((= (first xs) (first ys)) (self (rest xs) (rest ys)))
               (#t #f))))
    (def %check
      (fn (_ s)
        (unless (%same (%digest s) (ref s))
          (Err raise 'state %disagrees ()))))
    (def %check-n
      (fn (_ s n)
        (unless (%same (%digest s n) (ref s n))
          (Err raise 'state (Str8 append %disagrees " (explicit length)") ()))))
    (%check "")
    (%check "abc")
    (%check "abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu")
    (%check (Str8 pad-right 300 #\y "x"))
    ; "A\0B\0C" through the pointer door, and a binary block that crosses
    ; the 128-byte boundary, so the fill and the padding path see NULs too
    (def %s5-bin
      (let ((r (%s5-make-str 5)))
        (let ((p (%s5-str->ptr r)))
          (do (%s5-pset p 0 65 1) (%s5-pset p 1 0 1) (%s5-pset p 2 66 1)
              (%s5-pset p 3 0 1)  (%s5-pset p 4 67 1)
              r))))
    (%check-n %s5-bin 5)
    (def %s5-bin2
      (let ((r (%s5-make-str 300)))
        (let ((p (%s5-str->ptr r)))
          (do ((fn (self i)
                 (unless (= i 300)
                   (do (%s5-pset p i (& i 255) 1) (self (+ i 1))))) 0)
              r))))
    (%check-n %s5-bin2 300)
    %digest))

; The codec reaches the maker through the catalogue: it loads this module
; inside the function that builds its engine, and a name imported there is
; one the linter cannot see.
(prim-reg! (lit sha512) (lit jit-make) sha512-jit-make)

(doc (provide x/codec/sha512-jit sha512-jit-make)
  "The compiled SHA-512 engine (JIT, ARM64 and x86-64 backends); built and adopted only via (Sha512 jit!) after proving agreement with the pure-x digest.")

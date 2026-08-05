; sha256-jit.x -- the compiled SHA-256 engine behind (Sha256 jit!).
;
; Loaded LAZILY by x/codec/sha256 (never at boot, never on import of the
; codec): this module pulls the JIT assembler toolchain, and the codec
; must stay loadable -- and correct -- on hosts with no JIT at all.  The
; pure-x digest in sha256.x remains the reference implementation and the
; fallback; this engine is only ever an accelerator, and it is adopted
; only after it AGREES with the pure-x digest on the FIPS vectors plus a
; multi-block padding case (%sha-jit-make runs that differential check
; itself and raises on any disagreement -- the caller's guard turns any
; raise, including "wrong architecture", into "stay pure-x").
;
; The engine is the measured fold+fill configuration from
; tools/dev/bench-sha256.x (#198/#199): the 64 rounds, the working-state
; load and H-accumulate shuffles, AND the message-word fill -- padding
; included -- are ONE compiled function pair driven per block, entered
; through a t=-1 sentinel.  25KB in ~71ms against ~10.9s pure-x on the
; measuring machine; compiling costs seconds ONCE, which is why adoption
; is explicit (jit!) or cumulative-threshold, never per-call.
;
; x/tool/compile, not x/tool/asm-compile: the assembler backend is not
; standalone (its fvar plumbing lives in compile/emit.x), and compile.x
; is the module that loads the toolchain in the right order -- its
; compile-asm stub pulls the assembler lazily on first use.
(import x/tool/compile)

(def %sj-make-str (prim-ref (lit str) (lit make)))
(def %sj-str->ptr (prim-ref (lit str) (lit ->ptr)))
(def %sj-ptr->int (prim-ref (lit ptr) (lit ->int)))
(def %sj-pset (prim-ref (lit ptr) (lit set-word!)))
(def %sj-pref (prim-ref (lit ptr) (lit ref-word)))
(def %sj-oref (prim-ref (lit obj) (lit ref)))
(def %sj-M 4294967295)

; scratch layout, one 1024-byte buffer (words):
;   0..15 W | 16..23 a..h | 24 t1 25 t2 | 26 base 27 len 28 total
;   | 32..95 K | 96..103 H
(def %sj-KB 32)
(def %sj-HB 96)

; --- expression builders (generation time) ---
(def %sj-C  (fn (_ i) (list '%mem-ref 'a i)))
(def %sj-AT (fn (_ e) (list '%mem-ref-at 'a e)))
(def %sj-setC (fn (_ i v) (list '%mem-set! 'a i v)))
(def %sj-setAT (fn (_ e v) (list '%mem-set-at! 'a e v)))
(def %sj-rotr (fn (_ x n) (list '& (list '| (list '>> x n) (list '<< x (- 32 n))) %sj-M)))
(def %sj-bs0 (fn (_ x) (list '^ (%sj-rotr x 2)  (list '^ (%sj-rotr x 13) (%sj-rotr x 22)))))
(def %sj-bs1 (fn (_ x) (list '^ (%sj-rotr x 6)  (list '^ (%sj-rotr x 11) (%sj-rotr x 25)))))
(def %sj-ss0 (fn (_ x) (list '^ (%sj-rotr x 7)  (list '^ (%sj-rotr x 18) (list '>> x 3)))))
(def %sj-ss1 (fn (_ x) (list '^ (%sj-rotr x 17) (list '^ (%sj-rotr x 19) (list '>> x 10)))))
(def %sj-ch  (fn (_ x y z) (list '^ (list '& x y) (list '& (list '& (list '~ x) %sj-M) z))))
(def %sj-maj (fn (_ x y z) (list '^ (list '& x y) (list '^ (list '& x z) (list '& y z)))))
(def %sj-m32 (fn (_ e) (list '& e %sj-M)))
(def %sj-A (%sj-C 16)) (def %sj-B (%sj-C 17)) (def %sj-Cc (%sj-C 18)) (def %sj-D (%sj-C 19))
(def %sj-E (%sj-C 20)) (def %sj-F (%sj-C 21)) (def %sj-G (%sj-C 22)) (def %sj-H (%sj-C 23))
(def %sj-w (fn (_ off) (%sj-AT (list '& (list '- 't off) 15))))

(def %sj-extend
  (%sj-setAT (list '& 't 15)
    (%sj-m32 (list '+ (list '+ (%sj-ss1 (%sj-w 2)) (%sj-w 7))
                   (list '+ (%sj-ss0 (%sj-w 15)) (%sj-w 16))))))

(def %sj-round-body
  (list 'do
    (list 'if (list '< 't 16) 0 %sj-extend)
    (%sj-setC 24 (%sj-m32 (list '+ (list '+ %sj-H (%sj-bs1 %sj-E))
                              (list '+ (%sj-ch %sj-E %sj-F %sj-G)
                                    (list '+ (%sj-AT (list '+ %sj-KB 't))
                                          (%sj-AT (list '& 't 15)))))))
    (%sj-setC 25 (%sj-m32 (list '+ (%sj-bs0 %sj-A) (%sj-maj %sj-A %sj-B %sj-Cc))))
    (%sj-setC 23 %sj-G) (%sj-setC 22 %sj-F) (%sj-setC 21 %sj-E)
    (%sj-setC 20 (%sj-m32 (list '+ %sj-D (%sj-C 24))))
    (%sj-setC 19 %sj-Cc) (%sj-setC 18 %sj-B) (%sj-setC 17 %sj-A)
    (%sj-setC 16 (%sj-m32 (list '+ (%sj-C 24) (%sj-C 25))))
    (list 'self 'a (list '+ 't 1))))

; the H shuffles, folded (#198): load a..h from H on the t=-1 entry,
; masked H accumulate on the t=64 exit -- one native call per block.
(def %sj-seq8
  (fn (_ f) (pair 'do ((fn (self i) (if (= i 8) () (pair (f i) (self (+ i 1))))) 0))))
(def %sj-load-h (%sj-seq8 (fn (_ i) (%sj-setC (+ 16 i) (%sj-C (+ %sj-HB i))))))
(def %sj-store-h
  (%sj-seq8 (fn (_ i) (%sj-setC (+ %sj-HB i)
                        (%sj-m32 (list '+ (%sj-C (+ %sj-HB i)) (%sj-C (+ 16 i))))))))
(def %sj-rounds-expr
  (list 'fn '(self a t)
    (list 'if (list '< 't 0)
      (list 'do %sj-load-h (list 'self 'a 0))
      (list 'if (list '= 't 64) %sj-store-h %sj-round-body))))

; the W fill, compiled (#199): sixteen words from four padded byte reads
; each, against the message's raw address; the FIPS padding is compiled
; arithmetic on len/total in slots 27/28, block base in 26, so this one
; function serves every block including the padded tail.
(def %sj-pad-byte
  (fn (_ k)
    (def i (if (= k 0) (%sj-C 26) (list '+ (%sj-C 26) k)))
    (def L (%sj-C 27))
    (def T (%sj-C 28))
    (list 'if (list '< i L)
      (list '%mem-byte-ref-at 'm i)
      (list 'if (list '= i L) 128
        (list 'if (list '< i (list '- T 8)) 0
          (list '& (list '>> (list '<< L 3)
                         (list '<< (list '- (list '- T 1) i) 3)) 255))))))
(def %sj-fill-word
  (fn (_ t)
    (%sj-setC t
      (list '| (list '<< (%sj-pad-byte (* t 4)) 24)
        (list '| (list '<< (%sj-pad-byte (+ (* t 4) 1)) 16)
          (list '| (list '<< (%sj-pad-byte (+ (* t 4) 2)) 8)
            (%sj-pad-byte (+ (* t 4) 3))))))))
(def %sj-fill-expr
  (list 'fn '(_ a m)
    (pair 'do ((fn (self t) (if (= t 16) () (pair (%sj-fill-word t) (self (+ t 1))))) 0))))

; --- build: compile, wire a driver, and PROVE it against the reference ---
;
; k-vec: the FIPS K vector (slot t+1 = K[t], sha256.x's layout).
; ih:    the eight initial-H words as a list.
; ref:   the pure-x digest, (fn (_ s) -> 8-word list) -- the oracle.
;
; Returns (fn (_ s) -> 8-word list) driving the compiled pair, or raises
; -- on a non-arm64 host (unknown mnemonic), on any toolchain error, or
; on DISAGREEMENT with the reference.  The caller guards; a raise means
; "stay pure-x", never a wrong digest.
(def %sha-jit-make
  (fn (_ k-vec ih ref)
    (def %rounds (compile-asm %sj-rounds-expr))
    (def %fill (compile-asm %sj-fill-expr))
    (def %buf (%sj-make-str 1024))
    (def %ptr (%sj-str->ptr %buf))
    (def %addr (%sj-ptr->int %ptr))
    (def %poke (fn (_ i v) (%sj-pset %ptr (* i 8) v)))
    (def %peek (fn (_ i) (%sj-pref %ptr (* i 8))))
    ; K into slots 32..95, once
    ((fn (self i)
       (unless (= i 64)
         (do (%poke (+ %sj-KB i) (%sj-oref k-vec (+ i 1))) (self (+ i 1))))) 0)
    (def %digest
      (fn (_ s)
        (def len (Str8 length s))
        (def total (<< (+ (>> (+ len 8) 6) 1) 6))
        (def maddr (%sj-ptr->int (%sj-str->ptr s)))
        (%poke 27 len)
        (%poke 28 total)
        ((fn (self i hs)
           (unless (null? hs)
             (do (%poke (+ %sj-HB i) (first hs)) (self (+ i 1) (rest hs))))) 0 ih)
        ((fn (self b)
           (unless (= b total)
             (do
               ; explicit-trigger GC, sparingly: a collect MARKS THE
               ; WHOLE LIVE SESSION, not this loop's small garbage --
               ; ~1s in a loaded session -- and at ~100 objects per
               ; block the loop can run half a megabyte between
               ; collects for less than one collect costs.  Every 8192
               ; blocks (512KB) bounds growth on multi-MB inputs
               ; without taxing the amalgam-sized ones.
               (when (and (> b 0) (= 0 (& (>> b 6) 8191))) (Heap collect))
               (%poke 26 b)
               (%fill %addr maddr)
               (%rounds %addr -1)
               (self (+ b 64))))) 0)
        ((fn (self i acc)
           (if (< i 0) acc
             (self (- i 1) (pair (%peek (+ %sj-HB i)) acc)))) 7 ())))
    ; the differential check: FIPS vectors + a 3-block input that lands
    ; padding in a block of its own.  Any disagreement is a raise; an
    ; engine that cannot prove itself is not an engine.
    (def %same
      (fn (self xs ys)
        (match ((null? xs) (null? ys))
               ((null? ys) #f)
               ((= (first xs) (first ys)) (self (rest xs) (rest ys)))
               (#t #f))))
    (def %check
      (fn (_ s)
        (unless (%same (%digest s) (ref s))
          (Err raise 'state "sha256-jit: engine disagrees with the pure-x digest" ()))))
    (%check "")
    (%check "abc")
    (%check "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")
    (%check (Str8 pad-right 150 #\y "x"))
    %digest))

(doc (provide x/codec/sha256-jit %sha-jit-make)
  "The compiled SHA-256 engine (arm64 JIT); built and adopted only via (Sha256 jit!) after proving agreement with the pure-x digest.")

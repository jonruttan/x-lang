; ghash-jit.x -- the compiled GHASH engine behind (Ghash jit!).
;
; Loaded lazily by x/codec/ghash, as x/codec/aes-jit is by its codec: the
; pure-x hash in ghash.x is the reference and the fallback, and this
; engine is adopted only after it AGREES with it -- any disagreement is a
; raise, and the caller's guard turns a raise into "stay pure-x".
;
; The multiply is the 4-bit table one (Shoup's; OpenSSL's gcm_gmult_4bit):
; the sixteen multiples of H by a nibble, made here in x for each H, and
; a block taken a nibble at a time from its last byte to its first, low
; nibble then high -- Z moved right four bits, the bits that fall off
; folded back by a sixteen-entry table, then the nibble's multiple XORed
; in.  Every value is a 32-bit word, Z and the multiples four of them,
; so nothing leans on how a backend shifts a 64-bit one.
;
; One compiled function serves a block a nibble a call, its step in r,
; and goes straight on to the next block while the run and the input
; allow; the driver here, in x, runs it a run of blocks an entry.
(module x/codec/ghash-jit)

(import x/tool/jit-group jit-group)

(def %gj-make-str (prim-ref (lit str) (lit make)))
(def %gj-str->ptr (prim-ref (lit str) (lit ->ptr)))
(def %gj-ptr->int (prim-ref (lit ptr) (lit ->int)))
(def %gj-pset (prim-ref (lit ptr) (lit set-word!)))
(def %gj-pref (prim-ref (lit ptr) (lit ref-word)))
(def %gj-pset1 (prim-ref (lit ptr) (lit set!)))
(def %gj-byte-ref (prim-ref (lit str) (lit byte-ref)))
(def %gj-char->int (prim-ref (lit char) (lit ->int)))

; scratch layout, one buffer (words):
;   0..63 the multiples of H, four words each | 64..79 the fold table |
;   80..83 Y | 84..87 the block XOR Y | 88..91 Z | 92 in | 93 pos |
;   94 len | 95 run | 96 the nibble that falls off | 97 whether the
;   multiples are some H's yet
(def %gj-REM 64)
(def %gj-Y 80)
(def %gj-X 84)
(def %gj-Z 88)
(def %gj-IN 92)
(def %gj-POS 93)
(def %gj-LEN 94)
(def %gj-RUN 95)
(def %gj-T 96)
(def %gj-SET 97)
(def %gj-words 98)

; Blocks an entry does before returning to the driver.
(def %gj-run 4)

; The fold table: OpenSSL's rem_4bit, each at the top of a 32-bit word.
(def %gj-rems
  (list 0 7200 14400 9312 28800 27808 18624 21728 57600 64800 55616 50528 37248 36256 43456 46560))

; --- expression builders (generation time) ---
(def %gj-W (fn (_ i) (list '%mem-ref 'a i)))
(def %gj-setW (fn (_ i v) (list '%mem-set! 'a i v)))
(def %gj-at (fn (_ e) (list '%mem-ref-at 'a e)))
(def %gj-seq
  (fn (_ n f) (pair 'do ((fn (self i) (if (= i n) () (pair (f i) (self (+ i 1))))) 0))))

; Input byte at pos+i.
(def %gj-in-byte (fn (_ i) (list '%mem-byte-ref-at (%gj-W %gj-IN) (list '+ (%gj-W %gj-POS) i))))

; X word k: the block's word k, big-endian, XOR Y's.
(def %gj-load
  (%gj-seq 4
    (fn (_ k)
      (def b (fn (_ j) (%gj-in-byte (+ (* 4 k) j))))
      (%gj-setW (+ %gj-X k)
        (list '^ (%gj-W (+ %gj-Y k))
          (list '| (list '<< (b 0) 24) (list '| (list '<< (b 1) 16) (list '| (list '<< (b 2) 8) (b 3)))))))))

; Z moved right four bits, the nibble that falls off folded back in.
(def %gj-shift
  (list 'do
    (%gj-setW %gj-T (list '& (%gj-W (+ %gj-Z 3)) 15))
    (%gj-setW (+ %gj-Z 3) (list '| (list '>> (%gj-W (+ %gj-Z 3)) 4) (list '<< (list '& (%gj-W (+ %gj-Z 2)) 15) 28)))
    (%gj-setW (+ %gj-Z 2) (list '| (list '>> (%gj-W (+ %gj-Z 2)) 4) (list '<< (list '& (%gj-W (+ %gj-Z 1)) 15) 28)))
    (%gj-setW (+ %gj-Z 1) (list '| (list '>> (%gj-W (+ %gj-Z 1)) 4) (list '<< (list '& (%gj-W %gj-Z) 15) 28)))
    (%gj-setW %gj-Z (list '^ (list '>> (%gj-W %gj-Z) 4) (%gj-at (list '+ %gj-REM (%gj-W %gj-T)))))))

; Z XOR the multiple of H by a nibble.
(def %gj-add
  (fn (_ n)
    (%gj-seq 4 (fn (_ k) (%gj-setW (+ %gj-Z k) (list '^ (%gj-W (+ %gj-Z k)) (%gj-at (list '+ (list '<< n 2) k))))))))


; Nibble r of X, r from 0 to 31: byte 15-(r>>1), its low nibble when r
; is even and its high when odd.
(def %gj-nibble
  ((fn (_ c)
     (list '& (list '>> (list '& (list '>> (%gj-at (list '+ %gj-X (list '>> c 2)))
                                           (list '- 24 (list '<< (list '& c 3) 3)))
                                 255)
                        (list '<< (list '& 'r 1) 2))
           15))
   (list '- 15 (list '>> 'r 1))))

; r -1 starts a block: X loaded, Z zero.  r 0 to 31 is a nibble a call:
; Z moved right four bits, the nibble's multiple added.  r 32 ends it: Y
; is Z, and on to the next block while the run and the input allow.
(def %gj-block-expr
  (list 'fn '(self a r)
    (list 'if (list '< 'r 0)
      (list 'do %gj-load (%gj-seq 4 (fn (_ k) (%gj-setW (+ %gj-Z k) 0))) (list 'self 'a 0))
      (list 'if (list '< 'r 32)
        (list 'do %gj-shift (%gj-add %gj-nibble) (list 'self 'a (list '+ 'r 1)))
        (list 'do
          (%gj-seq 4 (fn (_ k) (%gj-setW (+ %gj-Y k) (%gj-W (+ %gj-Z k)))))
          (%gj-setW %gj-POS (list '+ (%gj-W %gj-POS) 16))
          (%gj-setW %gj-RUN (list '- (%gj-W %gj-RUN) 1))
          (list 'if (list '< (%gj-W %gj-RUN) 1) 0
            (list 'if (list '< (%gj-W %gj-POS) (%gj-W %gj-LEN)) (list 'self 'a -1) 0)))))))

; --- the multiples of H (per H, in x) ---
;
; No int xor in x: a ^ b is (a | b) - (a & b).
(def %gj-xor (fn (_ a b) (- (| a b) (& a b))))

; H's sixteen multiples: 8 is H itself, 4, 2 and 1 H moved right a bit at
; a time with R folded in, the rest their sums.
(def %gj-multiples!
  (fn (_ poke peek h)
    (def b (fn (_ i) (%gj-char->int (%gj-byte-ref h i))))
    (def word (fn (_ k) (| (<< (b (* 4 k)) 24) (| (<< (b (+ (* 4 k) 1)) 16) (| (<< (b (+ (* 4 k) 2)) 8) (b (+ (* 4 k) 3)))))))
    (def put (fn (_ n ws) ((fn (self k ws) (unless (null? ws) (do (poke (+ (* 4 n) k) (first ws)) (self (+ k 1) (rest ws))))) 0 ws)))
    (def get (fn (_ n) (list (peek (* 4 n)) (peek (+ (* 4 n) 1)) (peek (+ (* 4 n) 2)) (peek (+ (* 4 n) 3)))))
    (def half
      (fn (_ v)
        (def v0 (first v)) (def v1 (first (rest v))) (def v2 (first (rest (rest v)))) (def v3 (first (rest (rest (rest v)))))
        (def top (>> v0 1))
        (list (if (= (& v3 1) 1) (%gj-xor top 3774873600) top)
              (| (>> v1 1) (<< (& v0 1) 31))
              (| (>> v2 1) (<< (& v1 1) 31))
              (| (>> v3 1) (<< (& v2 1) 31)))))
    (def sum
      (fn (_ x y)
        ((fn (self x y) (if (null? x) () (pair (%gj-xor (first x) (first y)) (self (rest x) (rest y))))) x y)))
    (put 0 (list 0 0 0 0))
    (put 8 (list (word 0) (word 1) (word 2) (word 3)))
    (put 4 (half (get 8)))
    (put 2 (half (get 4)))
    (put 1 (half (get 2)))
    (put 3 (sum (get 2) (get 1)))
    (put 5 (sum (get 4) (get 1)))
    (put 6 (sum (get 4) (get 2)))
    (put 7 (sum (get 4) (get 3)))
    ((fn (self n) (unless (= n 8) (do (put (+ 8 n) (sum (get 8) (get n))) (self (+ n 1))))) 1)))

; --- build: compile, wire a driver, and PROVE it against the reference ---
;
; ref: the pure-x hash, (fn (_ h s len) -> 16 bytes) -- the oracle.
(def ghash-jit-make
  (fn (_ ref)
    (jit-group "ghash-jit:nibble" (fn (_) (list %gj-block-expr))
      (fn (_ fns replayed?) (%gj-wire ref (first fns) replayed?)))))

(def %gj-wire
  (fn (_ ref %block replayed?)
    (unless replayed? (Heap collect))
    (def %buf (%gj-make-str (* 8 %gj-words)))
    (def %ptr (%gj-str->ptr %buf))
    (def %addr (%gj-ptr->int %ptr))
    (def %poke (fn (_ i v) (%gj-pset %ptr (* i 8) v)))
    (def %peek (fn (_ i) (%gj-pref %ptr (* i 8))))
    ((fn (self i rs) (unless (null? rs) (do (%poke (+ %gj-REM i) (<< (first rs) 16)) (self (+ i 1) (rest rs))))) 0 %gj-rems)
    (def %b (fn (_ s i) (%gj-char->int (%gj-byte-ref s i))))
    (def %same
      (fn (self x y i n)
        (if (= i n) #t
          (if (= (%b x i) (%b y i)) (self x y (+ i 1) n) #f))))
    ; the multiples are kept for the last H, which a connection reuses
    (def %h (%gj-make-str 16))
    (%poke %gj-SET 0)
    (def %engine
      (fn (_ h s len)
        (when (if (= (%peek %gj-SET) 0) #t (not (%same h %h 0 16)))
          (%gj-multiples! %poke %peek h)
          ((fn (self i) (unless (= i 16) (do (%gj-pset1 (%gj-str->ptr %h) i (%b h i) 1) (self (+ i 1))))) 0)
          (%poke %gj-SET 1))
        ((fn (self k) (unless (= k 4) (do (%poke (+ %gj-Y k) 0) (self (+ k 1))))) 0)
        (%poke %gj-IN (%gj-ptr->int (%gj-str->ptr s)))
        (%poke %gj-LEN len)
        ((fn (self pos)
           (when (< pos len)
             (%poke %gj-POS pos)
             (%poke %gj-RUN %gj-run)
             (%block %addr -1)
             (self (%peek %gj-POS)))) 0)
        (def out (%gj-make-str 16))
        (def p (%gj-str->ptr out))
        ((fn (self i)
           (unless (= i 16)
             (do (%gj-pset1 p i (& (>> (%peek (+ %gj-Y (>> i 2))) (- 24 (* 8 (& i 3)))) 255) 1)
                 (self (+ i 1)))))
         0)
        out))
    (def %ramp
      (fn (_ n from step)
        (def r (%gj-make-str n))
        (def p (%gj-str->ptr r))
        ((fn (self i) (unless (= i n) (do (%gj-pset1 p i (& (+ from (* i step)) 255) 1) (self (+ i 1))))) 0)
        r))
    (def %check
      (fn (_ h s len)
        (unless (%same (%engine h s len) (ref h s len) 0 16)
          (Err raise 'state "ghash-jit: engine disagrees with the pure-x hash" ()))))
    (unless replayed?
      (do (%check (%ramp 16 1 37) (%ramp 160 0 1) 16)
          (%check (%ramp 16 255 3) (%ramp 160 9 77) 160)
          (%check (%ramp 16 128 0) (%ramp 160 255 0) 48)
          (%check (%ramp 16 0 0) (%ramp 32 5 5) 32)))
    %engine))

(prim-reg! (lit ghash) (lit jit-make) ghash-jit-make)

(doc (provide x/codec/ghash-jit ghash-jit-make)
  "The compiled GHASH engine (JIT, ARM64 and x86-64 backends); built and adopted only via (Ghash jit!) after proving agreement with the pure-x hash.")

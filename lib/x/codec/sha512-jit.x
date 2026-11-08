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
; the driver on 32-bit values the way the codec is.  A 4-byte word holds a
; slot as those two halves, and its functions are generated from them: see
; the engine on a 4-byte word, below.
(module x/codec/sha512-jit)

(import x/tool/jit-group jit-group)

(import x/core/doors char->int int->ptr mem-copy obj-ref ptr->int ptr-ref ptr-set! str->ptr str-byte-ref str-make)

; scratch layout, one 2048-byte buffer (64-bit words):
;   0..15 W ring | 16..23 working state | 24 t1 25 t2 | 26 base 27 len
;   28 total | 32..111 K | 112..119 H | 128.. each initial hash, eight a hash
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

; the digest written out: H's eight words as sixty-four bytes, each word
; big-endian, at the output's raw address -- a word a call, stepping as the
; fill does
(def %s5-emit-expr
  (list 'fn '(self a o w)
    (list 'if (list '= 'w 8) 0
      (pair 'do
        (List append
          ((fn (self j acc)
             (if (< j 0) acc
               (self (- j 1)
                 (pair (list '%mem-byte-set-at! 'o (list '+ (list '<< 'w 3) j)
                             (list '& (list '>> (%s5-AT (list '+ %s5-HB 'w)) (* 8 (- 7 j))) 255))
                       acc))))
           7 ())
          (list (list 'self 'a 'o (list '+ 'w 1))))))))

; --- the same engine on a 4-byte word (generation time) ---
;
; A 64-bit slot is two words there, lo at word 2i and hi at 2i+1, the
; halves the driver pokes and reads on either word.  A value is
; (READ? LO HI), two expressions for its words, READ? when each is a plain
; read.  The rotations and shifts move bits across the halves; an addition
; adds the halves and carries the low half's carry-out into the high:
; (a & b) | ((a | b) & ~sum), its top bit.  An expression reads each of
; its inputs once a half, so a value fed to anything that reads it twice
; is stored first, in a temporary at word %n5-TMP on: a function is a list
; of stores, written in order.
(def %s5-narrow (< %word-size 8))
(def %n5-TMP 288)

(def %n5-word (fn (_ i) (list '%mem-ref 'a i)))
(def %n5-word-at (fn (_ e) (list '%mem-ref-at 'a e)))
(def %n5-slot (fn (_ i) (list #t (%n5-word (* 2 i)) (%n5-word (+ (* 2 i) 1)))))
; 64-bit slot E, an expression, read at run time
(def %n5-slot-at
  (fn (_ e) (list #t (%n5-word-at (list '<< e 1)) (%n5-word-at (list '+ (list '<< e 1) 1)))))
(def %n5-lo (fn (_ v) (first (rest v))))
(def %n5-hi (fn (_ v) (first (rest (rest v)))))
(def %n5-val (fn (_ lo hi) (list #f lo hi)))

; the function being generated: its stores, newest first, and its next
; temporary
(def %n5-out (pair () %n5-TMP))
(def %n5-begin! (fn (_) (%set-first! %n5-out ()) (%set-rest! %n5-out %n5-TMP)))
(def %n5-emit! (fn (_ s) (%set-first! %n5-out (pair s (first %n5-out)))))
(def %n5-stores
  (fn (_) (pair 'do ((fn (self l acc) (if (null? l) acc (self (rest l) (pair (first l) acc)))) (first %n5-out) ()))))
(def %n5-store!
  (fn (_ i v)
    (%n5-emit! (list '%mem-set! 'a (* 2 i) (%n5-lo v)))
    (%n5-emit! (list '%mem-set! 'a (+ (* 2 i) 1) (%n5-hi v)))))
(def %n5-store-at!
  (fn (_ e v)
    (%n5-emit! (list '%mem-set-at! 'a (list '<< e 1) (%n5-lo v)))
    (%n5-emit! (list '%mem-set-at! 'a (list '+ (list '<< e 1) 1) (%n5-hi v)))))
; V as plain reads: itself, or stored to a fresh temporary
(def %n5-fix
  (fn (_ v)
    (if (first v) v
      (do (def w (rest %n5-out))
          (%set-rest! %n5-out (+ w 2))
          (%n5-emit! (list '%mem-set! 'a w (%n5-lo v)))
          (%n5-emit! (list '%mem-set! 'a (+ w 1) (%n5-hi v)))
          (list #t (%n5-word w) (%n5-word (+ w 1)))))))

; a word shifted right n places logically, 1 <= n <= 31
(def %n5-srl (fn (_ x n) (list '& (list '>> x n) (- (<< 1 (- 32 n)) 1))))
(def %n5-shr
  (fn (_ v n)
    (def x (%n5-fix v))
    (%n5-val (list '| (%n5-srl (%n5-lo x) n) (list '<< (%n5-hi x) (- 32 n)))
             (%n5-srl (%n5-hi x) n))))
; right by n, 1 <= n <= 63: past 32 the halves trade places first
(def %n5-rotr
  (fn (_ v n)
    (def x (%n5-fix v))
    (def lo (if (< n 32) (%n5-lo x) (%n5-hi x)))
    (def hi (if (< n 32) (%n5-hi x) (%n5-lo x)))
    (def m (% n 32))
    (if (= m 0) (list #t lo hi)
      (%n5-val (list '| (%n5-srl lo m) (list '<< hi (- 32 m)))
               (list '| (%n5-srl hi m) (list '<< lo (- 32 m)))))))
(def %n5-op2 (fn (_ op x y) (%n5-val (list op (%n5-lo x) (%n5-lo y)) (list op (%n5-hi x) (%n5-hi y)))))
(def %n5-xor (fn (_ x y) (%n5-op2 '^ x y)))
(def %n5-and (fn (_ x y) (%n5-op2 '& x y)))
(def %n5-not (fn (_ x) (%n5-val (list '~ (%n5-lo x)) (list '~ (%n5-hi x)))))
; The sum is stored whole, in a temporary: its high half reads the inputs'
; low halves again, and a store of the sum over an input would change them.
(def %n5-add
  (fn (_ u v)
    (def x (%n5-fix u))
    (def y (%n5-fix v))
    (def w (rest %n5-out))
    (%set-rest! %n5-out (+ w 2))
    (def a (%n5-lo x))
    (def b (%n5-lo y))
    (def s (%n5-word w))
    (%n5-emit! (list '%mem-set! 'a w (list '+ a b)))
    (%n5-emit! (list '%mem-set! 'a (+ w 1)
                 (list '+ (list '+ (%n5-hi x) (%n5-hi y))
                          (%n5-srl (list '| (list '& a b) (list '& (list '| a b) (list '~ s))) 31))))
    (list #t s (%n5-word (+ w 1)))))

(def %n5-bs0 (fn (_ x) (%n5-xor (%n5-rotr x 28) (%n5-xor (%n5-rotr x 34) (%n5-rotr x 39)))))
(def %n5-bs1 (fn (_ x) (%n5-xor (%n5-rotr x 14) (%n5-xor (%n5-rotr x 18) (%n5-rotr x 41)))))
(def %n5-ss0 (fn (_ x) (%n5-xor (%n5-rotr x 1) (%n5-xor (%n5-rotr x 8) (%n5-shr x 7)))))
(def %n5-ss1 (fn (_ x) (%n5-xor (%n5-rotr x 19) (%n5-xor (%n5-rotr x 61) (%n5-shr x 6)))))
(def %n5-ch (fn (_ x y z) (%n5-xor (%n5-and x y) (%n5-and (%n5-not x) z))))
(def %n5-maj (fn (_ x y z) (%n5-xor (%n5-and x y) (%n5-xor (%n5-and x z) (%n5-and y z)))))
(def %n5-w (fn (_ off) (%n5-slot-at (list '& (list '- 't off) 15))))

(def %n5-extend
  (fn (_)
    (%n5-begin!)
    (%n5-store-at! (list '& 't 15)
      (%n5-add (%n5-add (%n5-ss1 (%n5-w 2)) (%n5-w 7))
               (%n5-add (%n5-ss0 (%n5-w 15)) (%n5-w 16))))
    (%n5-stores)))

; the extension's stores are generated first, and the round's after: the
; two share the store list, and the extension's temporaries are dead before
; the round's are written
(def %n5-round-body
  (fn (_)
    (def ext (%n5-extend))
    (%n5-begin!)
    (def A (%n5-slot 16)) (def B (%n5-slot 17)) (def C (%n5-slot 18)) (def D (%n5-slot 19))
    (def E (%n5-slot 20)) (def F (%n5-slot 21)) (def G (%n5-slot 22)) (def H (%n5-slot 23))
    (%n5-store! 24 (%n5-add (%n5-add H (%n5-bs1 E))
                            (%n5-add (%n5-ch E F G)
                                     (%n5-add (%n5-slot-at (list '+ %s5-KB 't))
                                              (%n5-slot-at (list '& 't 15))))))
    (%n5-store! 25 (%n5-add (%n5-bs0 A) (%n5-maj A B C)))
    (%n5-store! 23 G) (%n5-store! 22 F) (%n5-store! 21 E)
    (%n5-store! 20 (%n5-add D (%n5-slot 24)))
    (%n5-store! 19 C) (%n5-store! 18 B) (%n5-store! 17 A)
    (%n5-store! 16 (%n5-add (%n5-slot 24) (%n5-slot 25)))
    (list 'do (list 'if (list '< 't 16) 0 ext)
              (%n5-stores)
              (list 'self 'a (list '+ 't 1)))))

(def %n5-load-h
  (fn (_)
    (%n5-begin!)
    ((fn (self i) (unless (= i 8) (do (%n5-store! (+ 16 i) (%n5-slot (+ %s5-HB i))) (self (+ i 1))))) 0)
    (%n5-stores)))
(def %n5-store-h
  (fn (_)
    (%n5-begin!)
    ((fn (self i)
       (unless (= i 8)
         (do (%n5-store! (+ %s5-HB i) (%n5-add (%n5-slot (+ %s5-HB i)) (%n5-slot (+ 16 i))))
             (self (+ i 1))))) 0)
    (%n5-stores)))
(def %n5-rounds-expr
  (fn (_)
    (def load (%n5-load-h))
    (def store (%n5-store-h))
    (list 'fn '(self a t)
      (list 'if (list '< 't 0)
        (list 'do load (list 'self 'a 0))
        (list 'if (list '= 't 80) store (%n5-round-body))))))

; the fill: len, total and base are the low words of slots 27, 28 and 26,
; and the bit length's top four bytes are zeros, a 4-byte word's message
; being under 2^29 bytes
(def %n5-pad-byte
  (fn (_ k)
    (def i (if (= k 0) (%n5-word 52) (list '+ (%n5-word 52) k)))
    (def L (%n5-word 54))
    (def T (%n5-word 56))
    (list 'if (list '< i L)
      (list '%mem-byte-ref-at 'm i)
      (list 'if (list '= i L) 128
        (list 'if (list '< i (list '- T 4)) 0
          (list '& (list '>> (list '<< L 3)
                         (list '<< (list '- (list '- T 1) i) 3)) 255))))))
; a word from the four padded bytes at byte 8t+O of the block, big-endian
(def %n5-fill-half
  (fn (_ o)
    ((fn (self k acc)
       (if (< k 0) acc
         (self (- k 1) (list '| (list '<< (%n5-pad-byte (list '+ (list '<< 't 3) (+ o k))) (* 8 (- 3 k))) acc))))
     2 (%n5-pad-byte (list '+ (list '<< 't 3) (+ o 3))))))
(def %n5-fill-expr
  (list 'fn '(self a m t)
    (list 'if (list '= 't 16) 0
      (list 'do (list '%mem-set-at! 'a (list '+ (list '<< 't 1) 1) (%n5-fill-half 0))
                (list '%mem-set-at! 'a (list '<< 't 1) (%n5-fill-half 4))
                (list 'self 'a 'm (list '+ 't 1))))))

; the digest written out, H's words big-endian, hi half first
(def %n5-emit-expr
  (list 'fn '(self a o w)
    (list 'if (list '= 'w 8) 0
      (pair 'do
        (List append
          ((fn (self j acc)
             (if (< j 0) acc
               (self (- j 1)
                 (pair (list '%mem-byte-set-at! 'o (list '+ (list '<< 'w 3) j)
                             (list '& (list '>> (%n5-word-at (list '+ (list '<< (list '+ %s5-HB 'w) 1) (if (< j 4) 1 0)))
                                            (* 8 (- 3 (% j 4)))) 255))
                       acc))))
           7 ())
          (list (list 'self 'a 'o (list '+ 'w 1))))))))

; --- build: compile, wire a driver, and PROVE it against the reference ---
;
; k:   the codec's K vector, 160 halves, hi then lo (slots 2t+1, 2t+2).
; ihs: the initial hashes it will be asked for (SHA-512's, SHA-384's),
;      each sixteen halves, hi then lo; it is proven on every one.
; ref: the pure-x digest, (fn (_ ih s [n]) -> sixteen halves) -- the oracle.
;
; Returns (fn (_ ih s [n]) -> sixteen halves) driving the compiled pair,
; or raises -- on a host whose architecture has no assembler backend, on
; any toolchain error, or on DISAGREEMENT with the reference.  The caller
; guards; a raise means "stay pure-x", never a wrong digest.
(def sha512-jit-make
  (fn (_ k ihs ref)
    (jit-group "sha512-jit:emit"
      (fn (_) (if %s5-narrow (list (%n5-rounds-expr) %n5-fill-expr %n5-emit-expr)
                (list %s5-rounds-expr %s5-fill-expr %s5-emit-expr)))
      (fn (_ fns replayed?)
        (%s5-wire k ihs ref (first fns) (first (rest fns)) (first (rest (rest fns))) replayed?)))))

; The digest over the compiled pair, proven against ref unless the pair
; was replayed from the cache group, where it was proven when stored.
(def %s5-wire
  (fn (_ k ihs ref %rounds %fill %emit replayed?)
    ; drop the whole build's remaining garbage before the digest phase; a
    ; replay compiled nothing and skips the collect, which marks the whole heap
    (unless replayed? (Heap collect))
    (def %buf (str-make 2048))
    (def %ptr (str->ptr %buf))
    (def %addr (ptr->int %ptr))
    ; a 64-bit slot as its two halves: lo at the slot's first four bytes
    (def %poke-halves (fn (_ i hi lo) (ptr-set! %ptr (* i 8) lo 4) (ptr-set! %ptr (+ (* i 8) 4) hi 4)))
    ; a small value in a 64-bit slot: the whole word, or its low half and
    ; a zero high half on a 4-byte word
    (def %poke
      (if %s5-narrow (fn (_ i v) (%poke-halves i 0 v))
        (fn (_ i v) (ptr-set! %ptr (* i 8) v 8))))
    (def %peek-hi (fn (_ i) (ptr-ref %ptr (+ (* i 8) 4) 4)))
    (def %peek-lo (fn (_ i) (ptr-ref %ptr (* i 8) 4)))
    ((fn (self t)
       (unless (= t 80)
         (do (%poke-halves (+ %s5-KB t) (obj-ref k (+ (* t 2) 1)) (obj-ref k (+ (* t 2) 2)))
             (self (+ t 1))))) 0)
    (def %disagrees "sha512-jit: engine disagrees with the pure-x digest")
    ; each initial hash's eight words preset at slot 128 + 8k, so a digest
    ; starts H with one copy of 64 bytes rather than sixteen pokes
    (def %preset
      (fn (self l k acc)
        (if (null? l) acc
          (let ((at (+ 128 (* 8 k))))
            (do ((fn (self i hs)
                   (unless (null? hs)
                     (do (%poke-halves (+ at i) (first hs) (first (rest hs)))
                         (self (+ i 1) (rest (rest hs)))))) 0 (first l))
                (self (rest l) (+ k 1) (pair (pair (first l) at) acc)))))))
    (def %presets (%preset ihs 0 ()))
    (def %h-at (+ %addr (* 8 %s5-HB)))
    ; H from IH: its preset copied in, or poked where it is not one of ihs
    (def %load-h!
      (fn (_ ih)
        (def p ((fn (self ps) (match ((null? ps) ()) ((eq? (first (first ps)) ih) (rest (first ps))) (#t (self (rest ps))))) %presets))
        (if (null? p)
          ((fn (self i hs)
             (unless (null? hs)
               (do (%poke-halves (+ %s5-HB i) (first hs) (first (rest hs)))
                   (self (+ i 1) (rest (rest hs)))))) 0 ih)
          (mem-copy (int->ptr %h-at) (int->ptr (+ %addr (* 8 p))) 64))))
    ; The digest of S's first N bytes (its length where N is not given):
    ; sixteen halves, or, given OUT, its sixty-four bytes written there and
    ; OUT answered -- the second the door the hashes built on a digest use,
    ; with no list made and no byte written from x.
    (def %digest
      (fn (_ ih s . more)
        (def len (match ((null? more) (Str8 length s)) (#t (first more))))
        (def out (match ((null? more) ()) ((null? (rest more)) ()) (#t (first (rest more)))))
        (def total (<< (+ (>> (+ len 16) 7) 1) 7))
        (def maddr (ptr->int (str->ptr s)))
        (%poke 27 len)
        (%poke 28 total)
        (%load-h! ih)
        ; one native call pair a block; the per-block garbage is the
        ; caller's to sweep (a collect here could overrun the collector's
        ; mark with a caller's long list live)
        ((fn (self b)
           (unless (= b total)
             (do (%poke 26 b)
                 (%fill %addr maddr 0)
                 (%rounds %addr -1)
                 (self (+ b 128))))) 0)
        (if (null? out)
          ((fn (self i acc)
             (if (< i 0) acc
               (self (- i 1) (pair (%peek-hi (+ %s5-HB i)) (pair (%peek-lo (+ %s5-HB i)) acc)))))
           7 ())
          (do (%emit %addr (ptr->int (str->ptr out)) 0) out))))
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
        ((fn (self l)
           (unless (null? l)
             (do (unless (%same (%digest (first l) s) (ref (first l) s))
                   (Err raise 'state %disagrees ()))
                 (self (rest l))))) ihs)))
    (def %check-n
      (fn (_ s n)
        ((fn (self l)
           (unless (null? l)
             (do (unless (%same (%digest (first l) s n) (ref (first l) s n))
                   (Err raise 'state (Str8 append %disagrees " (explicit length)") ()))
                 (self (rest l))))) ihs)))
    (unless replayed?
      (do
        (%check "")
        (%check "abc")
        (%check "abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu")
        (%check (Str8 pad-right 300 #\y "x"))
        ; "A\0B\0C" through the pointer door, and a binary block that crosses
        ; the 128-byte boundary, so the fill and the padding path see NULs too
        (def %s5-bin
          (let ((r (str-make 5)))
            (let ((p (str->ptr r)))
              (do (ptr-set! p 0 65 1) (ptr-set! p 1 0 1) (ptr-set! p 2 66 1)
                  (ptr-set! p 3 0 1)  (ptr-set! p 4 67 1)
                  r))))
        (%check-n %s5-bin 5)
        (def %s5-bin2
          (let ((r (str-make 300)))
            (let ((p (str->ptr r)))
              (do ((fn (self i)
                     (unless (= i 300)
                       (do (ptr-set! p i (& i 255) 1) (self (+ i 1))))) 0)
                  r))))
        (%check-n %s5-bin2 300)
        ; the door that writes the bytes: the same digest, byte for byte
        (def %s5-out (str-make 65))
        ((fn (self l)
           (unless (null? l)
             (do (%digest (first l) %s5-bin2 300 %s5-out)
                 ((fn (self i hs)
                    (unless (null? hs)
                      (do (unless (= (ptr-ref (str->ptr %s5-out) i 4)
                                     (| (| (<< (& (first hs) 255) 24) (<< (& (>> (first hs) 8) 255) 16))
                                        (| (<< (& (>> (first hs) 16) 255) 8) (& (>> (first hs) 24) 255))))
                            (Err raise 'state (Str8 append %disagrees " (bytes)") ()))
                          (self (+ i 4) (rest hs)))))
                  0 (%digest (first l) %s5-bin2 300))
                 (self (rest l))))) ihs)))
    %digest))

; The codec reaches the maker through the catalogue: it loads this module
; inside the function that builds its engine, and a name imported there is
; one the linter cannot see.
(prim-reg! (lit sha512) (lit jit-make) sha512-jit-make)

(doc (provide x/codec/sha512-jit sha512-jit-make)
  "The compiled SHA-512 engine (JIT, ARM64 and x86-64 backends); built and adopted only via (Sha512 jit!) after proving agreement with the pure-x digest.")

; aes-jit.x -- the compiled counter-mode engine behind (Aes jit!).
;
; Loaded lazily by x/codec/aes, as x/codec/chacha20-jit is by its codec:
; this module pulls the JIT toolchain, and the codec must stay loadable
; and correct on a host with no JIT.  The pure-x counter mode in aes.x is
; the reference and the fallback; this engine is adopted only after it
; AGREES with the reference for each key size, on regions that end inside
; a block, and across a counter carry -- any disagreement is a raise, and
; the caller's guard turns a raise into "stay pure-x".
;
; The cipher is the 32-bit table one (FIPS 197's own suggestion, 5.2.1 of
; the Rijndael proposal): the state as four big-endian column words, a
; round sixteen lookups in four 256-word tables T0..T3 -- SubBytes,
; ShiftRows and MixColumns together -- XORed with the round key, and the
; last round the S-box alone.  The tables and the S-box sit in the
; engine's buffer, built here from the reference's S-box; the round keys
; are copied in from the reference's schedule.
;
; One compiled function serves a block, entered through an r=-1 sentinel
; as chacha20-jit's is: the entry loads the counter XORed with the first
; round key; each call then is one round; round NR makes the keystream
; words, XORs a whole block into the output as two 64-bit words, and
; carries the counter.  A block the region ends inside is walked a byte a
; call instead, each behind the region's bound.  The driver here, in x,
; runs it a run of blocks an entry.
(module x/codec/aes-jit)

(import x/tool/jit-group jit-group)
(import x/type/vector)

(def %aj-make-str (prim-ref (lit str) (lit make)))
(def %aj-str->ptr (prim-ref (lit str) (lit ->ptr)))
(def %aj-ptr->int (prim-ref (lit ptr) (lit ->int)))
(def %aj-pset (prim-ref (lit ptr) (lit set-word!)))
(def %aj-pref (prim-ref (lit ptr) (lit ref-word)))
(def %aj-pset1 (prim-ref (lit ptr) (lit set!)))
(def %aj-byte-ref (prim-ref (lit str) (lit byte-ref)))
(def %aj-char->int (prim-ref (lit char) (lit ->int)))
(def %aj-oref (prim-ref (lit obj) (lit ref)))
(def %aj-M 4294967295)

; scratch layout, one buffer (words):
;   0..1023 T0 T1 T2 T3 | 1024..1279 the S-box | 1280..1339 round keys |
;   1340 NR | 1344..1347 counter | 1348..1351 state | 1352..1355 the
;   round's new state | 1356..1359 keystream | 1360 in | 1361 out |
;   1362 pos | 1363 len | 1364 run
; in and out are addresses; pos is the block's offset in the region, and
; run how many more whole blocks this entry may do before returning.
(def %aj-S 1024)
(def %aj-RK 1280)
(def %aj-NR 1340)
(def %aj-CTR 1344)
(def %aj-ST 1348)
(def %aj-NEW 1352)
(def %aj-KS 1356)
(def %aj-IN 1360)
(def %aj-OUT 1361)
(def %aj-POS 1362)
(def %aj-LEN 1363)
(def %aj-RUN 1364)
(def %aj-words 1365)

; Whole blocks an entry does before returning to the driver: a run is
; bounded, as chacha20-jit's is; sixteen blocks of up to fifteen calls.
(def %aj-run 16)

; A tail block's byte calls count from here, past any round number.
(def %aj-TAIL 100)

; --- expression builders (generation time) ---
(def %aj-W (fn (_ i) (list '%mem-ref 'a i)))
(def %aj-setW (fn (_ i v) (list '%mem-set! 'a i v)))
(def %aj-at (fn (_ e) (list '%mem-ref-at 'a e)))
(def %aj-seq
  (fn (_ n f) (pair 'do ((fn (self i) (if (= i n) () (pair (f i) (self (+ i 1))))) 0))))
(def %aj-byte (fn (_ e shift) (if (= shift 0) (list '& e 255) (list '& (list '>> e shift) 255))))

; Column i's new word for round r: the four table lookups, row k from
; column i+k, XORed with round key word 4r+i.
(def %aj-round-word
  (fn (_ i)
    (def s (fn (_ k) (%aj-W (+ %aj-ST (& (+ i k) 3)))))
    (list '^
      (list '^ (list '^ (%aj-at (%aj-byte (s 0) 24))
                        (%aj-at (list '+ 256 (%aj-byte (s 1) 16))))
               (list '^ (%aj-at (list '+ 512 (%aj-byte (s 2) 8)))
                        (%aj-at (list '+ 768 (%aj-byte (s 3) 0)))))
      (%aj-at (list '+ %aj-RK (list '+ (list '<< 'r 2) i))))))

(def %aj-round
  (list 'do
    (%aj-seq 4 (fn (_ i) (%aj-setW (+ %aj-NEW i) (%aj-round-word i))))
    (%aj-seq 4 (fn (_ i) (%aj-setW (+ %aj-ST i) (%aj-W (+ %aj-NEW i)))))))

; The last round's word i: the S-box alone, the rows shifted as before.
(def %aj-last-word
  (fn (_ i)
    (def s (fn (_ k) (%aj-W (+ %aj-ST (& (+ i k) 3)))))
    (def sb (fn (_ e) (%aj-at (list '+ %aj-S e))))
    (list '^
      (list '| (list '<< (sb (%aj-byte (s 0) 24)) 24)
        (list '| (list '<< (sb (%aj-byte (s 1) 16)) 16)
          (list '| (list '<< (sb (%aj-byte (s 2) 8)) 8)
                   (sb (%aj-byte (s 3) 0)))))
      (%aj-at (list '+ %aj-RK (list '+ (list '<< 'r 2) i))))))

; A 32-bit word's bytes reversed: a keystream word is big-endian, the
; output words little-endian.
(def %aj-swap
  (fn (_ e)
    (list '| (list '<< (%aj-byte e 0) 24)
      (list '| (list '<< (%aj-byte e 8) 16)
        (list '| (list '<< (%aj-byte e 16) 8) (%aj-byte e 24))))))

; Output word k of a whole block, k 0 or 1: input word k XORed with
; keystream words 2k and 2k+1 side by side.  pos is a multiple of 16, so
; pos>>3 is the block's first word.
(def %aj-xor-word
  (fn (_ k)
    (def at (list '+ (list '>> (%aj-W %aj-POS) 3) k))
    (list '%mem-set-at! (%aj-W %aj-OUT) at
      (list '^ (list '%mem-ref-at (%aj-W %aj-IN) at)
               (list '| (%aj-swap (%aj-W (+ %aj-KS (* 2 k))))
                        (list '<< (%aj-swap (%aj-W (+ %aj-KS (+ (* 2 k) 1)))) 32))))))

; The counter plus one, big-endian across its four words.
(def %aj-bump
  (list 'do
    (%aj-setW (+ %aj-CTR 3) (list '& (list '+ (%aj-W (+ %aj-CTR 3)) 1) %aj-M))
    (list 'if (list '= (%aj-W (+ %aj-CTR 3)) 0)
      (list 'do
        (%aj-setW (+ %aj-CTR 2) (list '& (list '+ (%aj-W (+ %aj-CTR 2)) 1) %aj-M))
        (list 'if (list '= (%aj-W (+ %aj-CTR 2)) 0)
          (list 'do
            (%aj-setW (+ %aj-CTR 1) (list '& (list '+ (%aj-W (+ %aj-CTR 1)) 1) %aj-M))
            (list 'if (list '= (%aj-W (+ %aj-CTR 1)) 0)
              (%aj-setW %aj-CTR (list '& (list '+ (%aj-W %aj-CTR) 1) %aj-M))
              0))
          0))
      0)))

; The counter XORed with round key 0: the state a block starts from.
(def %aj-load
  (%aj-seq 4 (fn (_ i) (%aj-setW (+ %aj-ST i) (list '^ (%aj-W (+ %aj-CTR i)) (%aj-W (+ %aj-RK i)))))))

; A short last block, one byte a call: byte i of the block is r-TAIL,
; byte i&3 of keystream word i>>2, big-endian -- and the walk ends at the
; region's end, with the counter carried.
(def %aj-tail-byte
  ((fn (_ i)
     (def at (list '+ (%aj-W %aj-POS) i))
     (list 'if (list '< at (%aj-W %aj-LEN))
       (list 'do
         (list '%mem-byte-set-at! (%aj-W %aj-OUT) at
           (list '^ (list '%mem-byte-ref-at (%aj-W %aj-IN) at)
                    (list '& (list '>> (%aj-at (list '+ %aj-KS (list '>> i 2)))
                                   (list '- 24 (list '<< (list '& i 3) 3)))
                             255)))
         (list 'self 'a (list '+ 'r 1)))
       (list 'do %aj-bump (%aj-setW %aj-POS (list '+ (%aj-W %aj-POS) 16)))))
   (list '- 'r %aj-TAIL)))

; Round NR done: the keystream words, then a whole block's words and
; straight on to the next block while the run and the region allow, or
; the byte walk for a block the region ends inside.  Either way pos has
; moved past the block when the entry returns.
(def %aj-finish
  (list 'do
    (%aj-seq 4 (fn (_ i) (%aj-setW (+ %aj-KS i) (%aj-last-word i))))
    (list 'if (list '< (list '+ (%aj-W %aj-POS) 16) (list '+ (%aj-W %aj-LEN) 1))
      (list 'do (%aj-xor-word 0) (%aj-xor-word 1) %aj-bump
        (%aj-setW %aj-POS (list '+ (%aj-W %aj-POS) 16))
        (%aj-setW %aj-RUN (list '- (%aj-W %aj-RUN) 1))
        (list 'if (list '< (%aj-W %aj-RUN) 1) 0
          (list 'if (list '< (%aj-W %aj-POS) (%aj-W %aj-LEN)) (list 'self 'a -1) 0)))
      (list 'self 'a %aj-TAIL))))

(def %aj-block-expr
  (list 'fn '(self a r)
    (list 'if (list '< 'r 0)
      (list 'do %aj-load (list 'self 'a 1))
      (list 'if (list '< 'r (%aj-W %aj-NR))
        (list 'do %aj-round (list 'self 'a (list '+ 'r 1)))
        (list 'if (list '= 'r (%aj-W %aj-NR)) %aj-finish %aj-tail-byte)))))

; --- the tables (load time, in x) ---
;
; No int xor in x: a ^ b is (a | b) - (a & b).
(def %aj-xor (fn (_ a b) (- (| a b) (& a b))))
(def %aj-xtime (fn (_ a) (%aj-xor (& (<< a 1) 255) (if (= (& a 128) 0) 0 27))))
(def %aj-rotr8 (fn (_ w) (| (>> w 8) (<< (& w 255) 24))))

; T0[x] is the column (2s, s, s, 3s) for s the S-box's x; T1..T3 are it
; rotated right by 8, 16 and 24.
(def %aj-tables!
  (fn (_ poke sub-byte)
    ((fn (self x)
       (unless (= x 256)
         (do (def s (sub-byte x))
             (def s2 (%aj-xtime s))
             (def t0 (| (<< s2 24) (| (<< s 16) (| (<< s 8) (%aj-xor s2 s)))))
             (def t1 (%aj-rotr8 t0))
             (def t2 (%aj-rotr8 t1))
             (poke x t0) (poke (+ 256 x) t1) (poke (+ 512 x) t2) (poke (+ 768 x) (%aj-rotr8 t2))
             (poke (+ %aj-S x) s)
             (self (+ x 1)))))
     0)))

; --- build: compile, wire a driver, and PROVE it against the reference ---
;
; ref: the pure-x counter mode, (fn (_ ks iv s start len) -> out) -- the
; oracle; schedule: (fn (_ key size) -> ks); sub-byte: the S-box.
;
; Returns a function of ref's shape driving the compiled block, or raises
; -- on a host whose architecture has no assembler backend, on any
; toolchain error, or on DISAGREEMENT with the reference.
(def aes-jit-make
  (fn (_ ref schedule sub-byte)
    (jit-group "aes-jit" (fn (_) (list %aj-block-expr))
      (fn (_ fns replayed?) (%aj-wire ref schedule sub-byte (first fns) replayed?)))))

(def %aj-wire
  (fn (_ ref schedule sub-byte %block replayed?)
    (unless replayed? (Heap collect))
    (def %buf (%aj-make-str (* 8 %aj-words)))
    (def %ptr (%aj-str->ptr %buf))
    (def %addr (%aj-ptr->int %ptr))
    (def %poke (fn (_ i v) (%aj-pset %ptr (* i 8) v)))
    (def %peek (fn (_ i) (%aj-pref %ptr (* i 8))))
    (%aj-tables! %poke sub-byte)
    (def %b (fn (_ s i) (%aj-char->int (%aj-byte-ref s i))))
    (def %engine
      (fn (_ ks iv s start len)
        (def w (first ks))
        (def nr (rest ks))
        ; round key word j: schedule bytes 4j..4j+3, big-endian
        ((fn (self j)
           (unless (= j (* 4 (+ nr 1)))
             (do (def at (* 4 j))
                 (%poke (+ %aj-RK j)
                   (| (<< (%aj-oref w (+ at 1)) 24) (| (<< (%aj-oref w (+ at 2)) 16)
                     (| (<< (%aj-oref w (+ at 3)) 8) (%aj-oref w (+ at 4))))))
                 (self (+ j 1)))))
         0)
        (%poke %aj-NR nr)
        ((fn (self j)
           (unless (= j 4)
             (do (def at (* 4 j))
                 (%poke (+ %aj-CTR j)
                   (| (<< (%b iv at) 24) (| (<< (%b iv (+ at 1)) 16) (| (<< (%b iv (+ at 2)) 8) (%b iv (+ at 3))))))
                 (self (+ j 1)))))
         0)
        (def out (%aj-make-str len))
        (%poke %aj-IN (+ (%aj-ptr->int (%aj-str->ptr s)) start))
        (%poke %aj-OUT (%aj-ptr->int (%aj-str->ptr out)))
        (%poke %aj-LEN len)
        ((fn (self pos)
           (when (< pos len)
             (%poke %aj-POS pos)
             (%poke %aj-RUN %aj-run)
             (%block %addr -1)
             (self (%peek %aj-POS)))) 0)
        out))
    ; the differential check: each key size, regions ending inside a
    ; block, and a counter that carries across words
    (def %same
      (fn (self x y i n)
        (if (= i n) #t
          (if (= (%b x i) (%b y i)) (self x y (+ i 1) n) #f))))
    (def %ramp
      (fn (_ n from)
        (def r (%aj-make-str n))
        (def p (%aj-str->ptr r))
        ((fn (self i) (unless (= i n) (do (%aj-pset1 p i (& (+ i from) 255) 1) (self (+ i 1))))) 0)
        r))
    (def %check
      (fn (_ size iv start len)
        (def ks (schedule (%ramp size 7) size))
        (def s (%ramp 300 0))
        (unless (%same (%engine ks iv s start len) (ref ks iv s start len) 0 len)
          (Err raise 'state "aes-jit: engine disagrees with the pure-x cipher" ()))))
    (unless replayed?
      (do (def iv (%ramp 16 240))
          (def carry ((fn (_ r) (%aj-pset1 (%aj-str->ptr r) 15 255 1) (%aj-pset1 (%aj-str->ptr r) 14 255 1)
                                  (%aj-pset1 (%aj-str->ptr r) 13 255 1) (%aj-pset1 (%aj-str->ptr r) 12 255 1) r)
                      (%ramp 16 0)))
          (%check 16 iv 0 16)
          (%check 24 iv 0 1)
          (%check 32 iv 0 15)
          (%check 32 iv 3 17)
          (%check 16 carry 0 64)
          (%check 32 carry 5 271)
          (%check 24 iv 0 0)))
    %engine))

; The codec reaches the maker through the catalogue: it loads this module
; inside the function that builds its engine, and a name imported there is
; one the linter cannot see.
(prim-reg! (lit aes) (lit jit-make) aes-jit-make)

(doc (provide x/codec/aes-jit aes-jit-make)
  "The compiled AES counter-mode engine (JIT, ARM64 and x86-64 backends); built and adopted only via (Aes jit!) after proving agreement with the pure-x cipher.")

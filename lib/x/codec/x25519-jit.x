; x25519-jit.x -- the compiled field operations behind (X25519 jit!).
;
; Loaded lazily by x/codec/x25519, as x/codec/chacha20-jit is by its
; cipher: this module pulls the JIT toolchain, and the codec must stay
; loadable and correct on a host with no JIT.  The pure-x function in
; x25519.x is the reference and the fallback; this engine replaces its
; field arithmetic -- the multiply, the add and subtract, the times
; 121666 and the swap, each one compiled function over a scratch of
; 64-bit words, a field element ten words at an offset -- and drives
; the RFC's ladder over them from x, the bytes in and out through the
; codec's own loader and packer.  It is adopted only after it answers
; the RFC's exchange, the bytes the reference's spec holds it to: the
; operations are proven against the pure-x field where they are built,
; and running the reference here would cost five seconds a build.
;
; The operations are x/codec/fe25519-jit's, shared with Ed25519's engine;
; the scratch here keeps its elements clear of that module's row area
; and swap slot.  Nothing here collects: the per-call garbage is the
; caller's to sweep.
(module x/codec/x25519-jit)

(import x/type/vector)
(import x/codec/fe25519-jit fe-jit-compile fe-jit-replayed? fe-jit-exprs)
(import x/tool/jit-group jit-group)

(import x/core/doors char->int obj-ref obj-set! ptr->int ptr-ref-word ptr-set! ptr-set-word! str->ptr str-byte-ref str-make)

; scratch layout, one 4096-byte buffer (words), ten a field element:
;   0 x1 | 10 x2 | 20 z2 | 30 x3 | 40 z3 | 50 tmp0 | 60 tmp1
;   70..119 t0..t4, the inverse's | 120 rows | 130 swap temp
;   140..171 the clamped scalar | 176..303 the inverse's step table
(def %X1 0) (def %X2 10) (def %Z2 20) (def %X3 30) (def %Z3 40)
(def %T0 50) (def %T1 60)
(def %I0 70) (def %I1 80) (def %I2 90) (def %I3 100) (def %I4 110)

; --- build: compile, wire the ladder, and PROVE it against the RFC -----------
;
; frombytes: the codec's loader, 32 bytes -> a ten-limb vector.
; tobytes:   the codec's packer, a ten-limb vector -> 32 bytes.
;
; Returns (fn (_ k u) -> 32 bytes) driving the compiled operations, or
; raises -- on a host whose architecture has no assembler backend, on any
; toolchain error, or on DISAGREEMENT with the RFC's bytes.
; --- the ladder compiled whole ------------------------------------------------
;
; A ladder step is twenty field operations; driven from x they were 5,000
; compiled calls a multiplication, each paying x's call glue around a few
; hundred native instructions.  The step is one compiled function instead:
; the field operations' own expressions (x/codec/fe25519-jit) with this
; layout's offsets put in for their parameters, run for each of the 255
; bits by a tail self-call, which the lane makes a jump.  The clamped
; scalar is in the scratch a byte a word from %KB, where the step reads its
; bit.
(def %KB 140)

; e with each symbol env names replaced by its value.
(def %xj-subst
  (fn (self e env)
    (if (pair? e) (pair (self (first e) env) (self (rest e) env))
      ((fn (look l) (if (null? l) e (if (eq? (first (first l)) e) (rest (first l)) (look (rest l))))) env))))

; operation k's body, with its parameters bound as env says
(def %xj-op
  (fn (_ exprs k env) (%xj-subst (List ref 2 (List ref k exprs)) env)))

(def %xj-ladder-expr
  (fn (_ exprs)
    (def bit (list '& (list '>> (list '%mem-ref-at 'a (list '+ %KB (list '>> 'pos 3))) (list '& 'pos 7)) 1))
    (def mul (fn (_ h f g) (%xj-op exprs 0 (list (pair 'h h) (pair 'f f) (pair 'g g)))))
    (def add (fn (_ h f g) (%xj-op exprs 1 (list (pair 'h h) (pair 'f f) (pair 'g g)))))
    (def sub (fn (_ h f g) (%xj-op exprs 2 (list (pair 'h h) (pair 'f f) (pair 'g g)))))
    (def m121666 (fn (_ h f) (%xj-op exprs 3 (list (pair 'h h) (pair 'f f)))))
    (def cswap (fn (_ f g b) (%xj-op exprs 4 (list (pair 'f f) (pair 'g g) (pair 'b b)))))
    (def sw (list '^ 'swap bit))
    (list 'fn '(self a pos swap)
      (list 'do
        (cswap %X2 %X3 sw) (cswap %Z2 %Z3 sw)
        (sub %T0 %X3 %Z3) (sub %T1 %X2 %Z2) (add %X2 %X2 %Z2) (add %Z2 %X3 %Z3)
        (mul %Z3 %T0 %X2) (mul %Z2 %Z2 %T1) (mul %T0 %T1 %T1) (mul %T1 %X2 %X2)
        (add %X3 %Z3 %Z2) (sub %Z2 %Z3 %Z2) (mul %X2 %T1 %T0) (sub %T1 %T1 %T0)
        (mul %Z2 %Z2 %Z2) (m121666 %Z3 %T1) (mul %X3 %X3 %X3) (add %T0 %T0 %Z3)
        (mul %Z3 %X1 %Z2) (mul %Z2 %T1 %T0)
        (list 'if (list '= 'pos 0)
          (list 'do (cswap %X2 %X3 bit) (cswap %Z2 %Z3 bit) 0)
          (list 'self 'a (list '- 'pos 1) bit))))))

; The inverse and the last multiply, ref10's chain: a table of steps from
; %TB, four words each -- h, f, g and how many times -- each step h = f g
; (a square when f is g) that many times, run by one compiled function
; whose state is the step and its count.  The chain's 254 squarings were
; 265 compiled calls from x.
(def %TB 176)
(def %xj-chain
  (list (list %I0 %Z2 %Z2 1) (list %I1 %I0 %I0 1) (list %I1 %I1 %I1 1) (list %I1 %Z2 %I1 1)
        (list %I0 %I0 %I1 1) (list %I2 %I0 %I0 1) (list %I1 %I1 %I2 1)
        (list %I2 %I1 %I1 1) (list %I2 %I2 %I2 4) (list %I1 %I2 %I1 1)
        (list %I2 %I1 %I1 1) (list %I2 %I2 %I2 9) (list %I2 %I2 %I1 1)
        (list %I3 %I2 %I2 1) (list %I3 %I3 %I3 19) (list %I2 %I3 %I2 1)
        (list %I2 %I2 %I2 1) (list %I2 %I2 %I2 9) (list %I1 %I2 %I1 1)
        (list %I2 %I1 %I1 1) (list %I2 %I2 %I2 49) (list %I2 %I2 %I1 1)
        (list %I3 %I2 %I2 1) (list %I3 %I3 %I3 99) (list %I2 %I3 %I2 1)
        (list %I2 %I2 %I2 1) (list %I2 %I2 %I2 49) (list %I1 %I2 %I1 1)
        (list %I1 %I1 %I1 1) (list %I1 %I1 %I1 4) (list %Z2 %I1 %I0 1)
        (list %X2 %X2 %Z2 1)))

(def %xj-chain-expr
  (fn (_ exprs)
    (def last (- (List length %xj-chain) 1))
    (def next (fn (_ k) (list '%mem-ref-at 'a (list '+ %TB (list '+ (list '<< (list '+ 'ph 1) 2) k)))))
    (list 'fn '(self a ph n h f g)
      (list 'do (List ref 2 (List ref 0 exprs))
        (list 'if (list '> 'n 1)
          (list 'self 'a 'ph (list '- 'n 1) 'h 'f 'g)
          (list 'if (list '= 'ph last) 0
            (list 'self 'a (list '+ 'ph 1) (next 3) (next 0) (next 1) (next 2))))))))

(def x25519-jit-make
  (fn (_ frombytes tobytes)
    ; the field operations, built and proven against the pure-x field: the
    ; ladder and the chain compile the same expressions
    (fe-jit-compile)
    (def %ladder
      (jit-group "x25519-ladder:2" (fn (_) (list (%xj-ladder-expr (fe-jit-exprs)) (%xj-chain-expr (fe-jit-exprs))))
        (fn (_ fns _replayed) fns)))
    (def %chain (first (rest %ladder)))
    ; the build's garbage goes before the engine runs; a collect here has
    ; nothing of the caller's live (the maker is called once, to build) --
    ; and replayed operations compiled nothing, so the collect, which marks
    ; the whole live heap, is skipped
    (unless (fe-jit-replayed?) (Heap collect))
    (def %buf (str-make 4096))
    (def %ptr (str->ptr %buf))
    (def %addr (ptr->int %ptr))
    (def %poke (fn (_ i v) (ptr-set-word! %ptr (* i 8) v)))
    (def %peek (fn (_ i) (ptr-ref-word %ptr (* i 8))))
    (def %load!
      (fn (_ off v)
        ((fn (self i) (unless (= i 10) (do (%poke (+ off i) (obj-ref v (+ i 1))) (self (+ i 1))))) 0)))
    (def %store
      (fn (_ off)
        (def v (Vector make 10 0))
        ((fn (self i) (unless (= i 10) (do (obj-set! v (+ i 1) (%peek (+ off i))) (self (+ i 1))))) 0)
        v))
    (def %one (fn (_ off) (%poke off 1) ((fn (self i) (unless (= i 10) (do (%poke (+ off i) 0) (self (+ i 1))))) 1)))
    (def %zero (fn (_ off) ((fn (self i) (unless (= i 10) (do (%poke (+ off i) 0) (self (+ i 1))))) 0)))
    (def %copy (fn (_ to from) ((fn (self i) (unless (= i 10) (do (%poke (+ to i) (%peek (+ from i))) (self (+ i 1))))) 0)))
    ; the inverse's steps, once
    ((fn (self l i) (unless (null? l) (do ((fn (inner s j) (unless (null? s) (do (%poke (+ %TB (+ (* 4 i) j)) (first s)) (inner (rest s) (+ j 1))))) (first l) 0) (self (rest l) (+ i 1))))) %xj-chain 0)
    (def %engine
      (fn (_ k u)
        (%load! %X1 (frombytes u))
        (%one %X2) (%zero %Z2) (%copy %X3 %X1) (%one %Z3)
        ; the clamped scalar a byte a word, then the 255 steps in one call
        ((fn (self i)
           (unless (= i 32)
             (do (def b (char->int (str-byte-ref k i)))
                 (%poke (+ %KB i) (match ((= i 0) (& b 248)) ((= i 31) (| (& b 127) 64)) (#t b)))
                 (self (+ i 1)))))
         0)
        ((first %ladder) %addr 254 0)
        ; the inverse and the last multiply, from the table's first step
        ((fn (_ s) (%chain %addr 0 (List ref 3 s) (List ref 0 s) (List ref 1 s) (List ref 2 s))) (first %xj-chain))
        (tobytes (%store %X2))))
    ; the differential check: the RFC's 6.1 exchange, both directions
    (def %same
      (fn (self x y i)
        (if (= i 32) #t
          (if (= (char->int (str-byte-ref x i)) (char->int (str-byte-ref y i)))
            (self x y (+ i 1))
            #f))))
    (def %hex-bytes
      (fn (_ hex)
        (def n (>> (Str8 length hex) 1))
        (def s (str-make n))
        (def p (str->ptr s))
        (def %digit (fn (_ c) (if (< c 58) (- c 48) (- c 87))))
        ((fn (self i)
           (unless (= i n)
             (do (ptr-set! p i (| (<< (%digit (char->int (str-byte-ref hex (* 2 i)))) 4)
                                (%digit (char->int (str-byte-ref hex (+ (* 2 i) 1))))) 1)
                 (self (+ i 1))))) 0)
        s))
    ; The field operations were proven against the pure-x field when they
    ; were built; what is left to prove is the ladder over them, and the
    ; RFC's own bytes prove it -- the bytes the pure-x function's spec
    ; holds it to -- in both directions of the exchange.
    (def %check
      (fn (_ k u expect)
        (unless (%same (%engine k u) expect 0)
          (Err raise 'state "x25519-jit: engine disagrees with RFC 7748" ()))))
    ; Operations replayed from the cache group passed this very check in
    ; the process that stored them; the ladder over them is this file's
    ; own source, the same in every process.
    (unless (fe-jit-replayed?)
      (do
        (def %a (%hex-bytes "77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a"))
        (def %b (%hex-bytes "5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb"))
        (def %apub (%hex-bytes "8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a"))
        (def %nine (%hex-bytes "0900000000000000000000000000000000000000000000000000000000000000"))
        (%check %a %nine %apub)
        (%check %b %apub (%hex-bytes "4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742"))))
    %engine))

; The codec reaches the maker through the catalogue: it loads this module
; inside the function that builds its engine, and a name imported there is
; one the linter cannot see.
(prim-reg! (lit x25519) (lit jit-make) x25519-jit-make)

(doc (provide x/codec/x25519-jit x25519-jit-make)
  "The compiled X25519 ladder (JIT, ARM64 and x86-64 backends) over x/codec/fe25519-jit's checked field operations; built and adopted only via (X25519 jit!) after answering RFC 7748's exchange in both directions.")

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
; codec's own loader and packer.  It is adopted only after it agrees
; with the reference on the RFC's vectors.
;
; The operations are x/codec/fe25519-jit's, shared with Ed25519's engine;
; the scratch here keeps its elements clear of that module's row area
; and swap slot.  Nothing here collects: the per-call garbage is the
; caller's to sweep.
(module x/codec/x25519-jit)

(import x/type/vector)
(import x/codec/fe25519-jit fe-jit-compile)

(def %xj-make-str (prim-ref (lit str) (lit make)))
(def %xj-str->ptr (prim-ref (lit str) (lit ->ptr)))
(def %xj-ptr->int (prim-ref (lit ptr) (lit ->int)))
(def %xj-pset (prim-ref (lit ptr) (lit set-word!)))
(def %xj-pref (prim-ref (lit ptr) (lit ref-word)))
(def %xj-oref (prim-ref (lit obj) (lit ref)))
(def %xj-oset! (prim-ref (lit obj) (lit set!)))
(def %xj-byte-ref (prim-ref (lit str) (lit byte-ref)))
(def %xj-char->int (prim-ref (lit char) (lit ->int)))

; scratch layout, one 2048-byte buffer (words), ten a field element:
;   0 x1 | 10 x2 | 20 z2 | 30 x3 | 40 z3 | 50 tmp0 | 60 tmp1
;   70..119 t0..t4, the inverse's | 120 rows | 130 swap temp
(def %X1 0) (def %X2 10) (def %Z2 20) (def %X3 30) (def %Z3 40)
(def %T0 50) (def %T1 60)
(def %I0 70) (def %I1 80) (def %I2 90) (def %I3 100) (def %I4 110)

; --- build: compile, wire the ladder, and PROVE it against the reference ---
;
; ref:       the pure-x function, (fn (_ k u) -> 32 bytes) -- the oracle.
; frombytes: the codec's loader, 32 bytes -> a ten-limb vector.
; tobytes:   the codec's packer, a ten-limb vector -> 32 bytes.
;
; Returns a function of ref's shape driving the compiled operations, or
; raises -- on a host whose architecture has no assembler backend, on any
; toolchain error, or on DISAGREEMENT with the reference.
(def x25519-jit-make
  (fn (_ ref frombytes tobytes)
    (def %ops (fe-jit-compile))
    (def %mul (List ref 0 %ops))
    (def %add (List ref 1 %ops))
    (def %sub (List ref 2 %ops))
    (def %m121666 (List ref 3 %ops))
    (def %cswap (List ref 4 %ops))
    ; the build's garbage goes before the engine runs; a collect here has
    ; nothing of the caller's live (the maker is called once, to build)
    (Heap collect)
    (def %buf (%xj-make-str 2048))
    (def %ptr (%xj-str->ptr %buf))
    (def %addr (%xj-ptr->int %ptr))
    (def %poke (fn (_ i v) (%xj-pset %ptr (* i 8) v)))
    (def %peek (fn (_ i) (%xj-pref %ptr (* i 8))))
    (def %load!
      (fn (_ off v)
        ((fn (self i) (unless (= i 10) (do (%poke (+ off i) (%xj-oref v (+ i 1))) (self (+ i 1))))) 0)))
    (def %store
      (fn (_ off)
        (def v (Vector make 10 0))
        ((fn (self i) (unless (= i 10) (do (%xj-oset! v (+ i 1) (%peek (+ off i))) (self (+ i 1))))) 0)
        v))
    (def %one (fn (_ off) (%poke off 1) ((fn (self i) (unless (= i 10) (do (%poke (+ off i) 0) (self (+ i 1))))) 1)))
    (def %zero (fn (_ off) ((fn (self i) (unless (= i 10) (do (%poke (+ off i) 0) (self (+ i 1))))) 0)))
    (def %copy (fn (_ to from) ((fn (self i) (unless (= i 10) (do (%poke (+ to i) (%peek (+ from i))) (self (+ i 1))))) 0)))
    (def %sq (fn (_ h f) (%mul %addr h f f)))
    (def %sq-n (fn (self h n) (unless (= n 0) (do (%sq h h) (self h (- n 1))))))
    ; the clamped scalar's bit at pos
    (def %bit
      (fn (_ k pos)
        (def b (%xj-char->int (%xj-byte-ref k (>> pos 3))))
        (def c (match ((< pos 8) (& b 248)) ((>= pos 248) (| (& b 127) 64)) (#t b)))
        (& (>> c (& pos 7)) 1)))
    ; z2 <- 1/z2, ref10's chain over the inverse's temporaries
    (def %invert!
      (fn (_)
        (%sq %I0 %Z2)
        (%sq %I1 %I0) (%sq %I1 %I1) (%mul %addr %I1 %Z2 %I1)
        (%mul %addr %I0 %I0 %I1)
        (%sq %I2 %I0) (%mul %addr %I1 %I1 %I2)
        (%sq %I2 %I1) (%sq-n %I2 4) (%mul %addr %I1 %I2 %I1)
        (%sq %I2 %I1) (%sq-n %I2 9) (%mul %addr %I2 %I2 %I1)
        (%sq %I3 %I2) (%sq-n %I3 19) (%mul %addr %I2 %I3 %I2)
        (%sq %I2 %I2) (%sq-n %I2 9) (%mul %addr %I1 %I2 %I1)
        (%sq %I2 %I1) (%sq-n %I2 49) (%mul %addr %I2 %I2 %I1)
        (%sq %I3 %I2) (%sq-n %I3 99) (%mul %addr %I2 %I3 %I2)
        (%sq %I2 %I2) (%sq-n %I2 49) (%mul %addr %I1 %I2 %I1)
        (%sq %I1 %I1) (%sq-n %I1 4) (%mul %addr %Z2 %I1 %I0)))
    (def %engine
      (fn (_ k u)
        (%load! %X1 (frombytes u))
        (%one %X2) (%zero %Z2) (%copy %X3 %X1) (%one %Z3)
        ((fn (self pos swap)
           (def b (%bit k pos))
           (def sw (^ swap b))
           (%cswap %addr %X2 %X3 sw)
           (%cswap %addr %Z2 %Z3 sw)
           (%sub %addr %T0 %X3 %Z3)
           (%sub %addr %T1 %X2 %Z2)
           (%add %addr %X2 %X2 %Z2)
           (%add %addr %Z2 %X3 %Z3)
           (%mul %addr %Z3 %T0 %X2)
           (%mul %addr %Z2 %Z2 %T1)
           (%sq %T0 %T1)
           (%sq %T1 %X2)
           (%add %addr %X3 %Z3 %Z2)
           (%sub %addr %Z2 %Z3 %Z2)
           (%mul %addr %X2 %T1 %T0)
           (%sub %addr %T1 %T1 %T0)
           (%sq %Z2 %Z2)
           (%m121666 %addr %Z3 %T1)
           (%sq %X3 %X3)
           (%add %addr %T0 %T0 %Z3)
           (%mul %addr %Z3 %X1 %Z2)
           (%mul %addr %Z2 %T1 %T0)
           (if (= pos 0)
             (do (%cswap %addr %X2 %X3 b) (%cswap %addr %Z2 %Z3 b))
             (self (- pos 1) b)))
         254 0)
        (%invert!)
        (%mul %addr %X2 %X2 %Z2)
        (tobytes (%store %X2))))
    ; the differential check: the RFC's 6.1 exchange, both directions
    (def %same
      (fn (self x y i)
        (if (= i 32) #t
          (if (= (%xj-char->int (%xj-byte-ref x i)) (%xj-char->int (%xj-byte-ref y i)))
            (self x y (+ i 1))
            #f))))
    (def %hex-bytes
      (fn (_ hex)
        (def n (>> (Str8 length hex) 1))
        (def s (%xj-make-str n))
        (def p (%xj-str->ptr s))
        (def %pset1 (prim-ref (lit ptr) (lit set!)))
        (def %digit (fn (_ c) (if (< c 58) (- c 48) (- c 87))))
        ((fn (self i)
           (unless (= i n)
             (do (%pset1 p i (| (<< (%digit (%xj-char->int (%xj-byte-ref hex (* 2 i)))) 4)
                                (%digit (%xj-char->int (%xj-byte-ref hex (+ (* 2 i) 1))))) 1)
                 (self (+ i 1))))) 0)
        s))
    ; One exchange against the reference, whose five seconds are most of
    ; the build, and the other against the RFC's own bytes, which the
    ; reference's spec proves it answers; the two cover both directions.
    (def %check
      (fn (_ k u expect)
        (unless (%same (%engine k u) (if (null? expect) (ref k u) expect) 0)
          (Err raise 'state "x25519-jit: engine disagrees with the pure-x function" ()))))
    (def %a (%hex-bytes "77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a"))
    (def %b (%hex-bytes "5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb"))
    (def %apub (%hex-bytes "8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a"))
    (def %nine (%hex-bytes "0900000000000000000000000000000000000000000000000000000000000000"))
    (%check %a %nine ())
    (%check %b %apub (%hex-bytes "4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742"))
    %engine))

; The codec reaches the maker through the catalogue: it loads this module
; inside the function that builds its engine, and a name imported there is
; one the linter cannot see.
(prim-reg! (lit x25519) (lit jit-make) x25519-jit-make)

(doc (provide x/codec/x25519-jit x25519-jit-make)
  "The compiled X25519 field engine (JIT, ARM64 and x86-64 backends); built and adopted only via (X25519 jit!) after proving agreement with the pure-x function.")

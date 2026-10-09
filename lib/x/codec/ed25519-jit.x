; ed25519-jit.x -- the compiled field work behind (Ed25519 jit!).
;
; Loaded lazily by x/codec/ed25519, as x/codec/x25519-jit is by its
; codec: this module pulls the JIT toolchain, and the codec must stay
; loadable and correct on a host with no JIT.  The pure-x %scalarmult,
; fe-invert and fe-pow22523 the codec uses are the reference and the
; fallback; this engine replaces all three.  The scalar multiplication
; keeps a point in extended coordinates as four field elements in a
; scratch of 64-bit words, doubled and added by x/codec/fe25519-jit's
; compiled operations, the double-and-add driven from x; the inverse
; and the square root's power are that module's chains.  It is adopted
; only after it answers RFC 8032's test 1: the field operations are
; proven against the pure-x field where they are built, and running the
; reference multiplication here would cost six seconds a build.  The
; hashes and the scalars mod L stay in x on both paths.  Nothing here
; collects: the per-call garbage is the caller's to sweep.
(module x/codec/ed25519-jit)

(import x/type/vector)
(import x/codec/fe25519 fe-tobytes fe-mul)
(import x/codec/fe25519-jit fe-jit-compile fe-jit-chains)

(def %ej-make-str (prim-ref (lit str) (lit make)))
(def %ej-str->ptr (prim-ref (lit str) (lit ->ptr)))
(def %ej-ptr->int (prim-ref (lit ptr) (lit ->int)))
(def %ej-pset (prim-ref (lit ptr) (lit set-word!)))
(def %ej-pref (prim-ref (lit ptr) (lit ref-word)))
(def %ej-oref (prim-ref (lit obj) (lit ref)))
(def %ej-oset! (prim-ref (lit obj) (lit set!)))
(def %ej-byte-ref (prim-ref (lit str) (lit byte-ref)))
(def %ej-char->int (prim-ref (lit char) (lit ->int)))

; scratch layout, one 2048-byte buffer (words), ten a field element:
;   0 X | 10 Y | 20 Z | 30 T        the accumulator
;   40 Y+X | 50 Y-X | 60 Zq | 70 2dT  the addend, cached
;   80..110 four temporaries | 120..130 the field engine's row area and swap
;   140..170 a b c dd | 180 X' | 190 Y' | 200 Z' | 210 T'  the completed form
;   220 2d
(def %X 0) (def %Y 10) (def %Z 20) (def %T 30)
(def %YpX 40) (def %YmX 50) (def %Zq 60) (def %T2d 70)
(def %T0 80) (def %T1 90) (def %T2 100) (def %T3 110)
(def %A 140) (def %B 150) (def %C 160) (def %D 170)
(def %Xc 180) (def %Yc 190) (def %Zc 200) (def %Tc 210)
(def %D2 220)

; --- build: compile, wire the double-and-add, and PROVE it ---------------
;
; d2:   the field element 2d, as the codec holds it.
; base: the base point, for the check.
;
; Returns (SCALARMULT INVERT POW22523): (fn (_ k p) -> point), and the
; field's two chains as (fn (_ z) -> element); or raises -- on a host
; whose architecture has no assembler backend, on any toolchain error,
; or on DISAGREEMENT with the RFC's bytes.
(def ed25519-jit-make
  (fn (_ d2 base)
    (def %ops (fe-jit-compile))
    (def %mul (List ref 0 %ops))
    (def %add (List ref 1 %ops))
    (def %sub (List ref 2 %ops))
    ; the build's garbage goes before the engine runs; a collect here has
    ; nothing of the caller's live (the maker is called once, to build)
    (Heap collect)
    (def %buf (%ej-make-str 2048))
    (def %ptr (%ej-str->ptr %buf))
    (def %addr (%ej-ptr->int %ptr))
    (def %poke (fn (_ i v) (%ej-pset %ptr (* i 8) v)))
    (def %peek (fn (_ i) (%ej-pref %ptr (* i 8))))
    (def %load!
      (fn (_ off v)
        ((fn (self i) (unless (= i 10) (do (%poke (+ off i) (%ej-oref v (+ i 1))) (self (+ i 1))))) 0)))
    (def %store
      (fn (_ off)
        (def v (Vector make 10 0))
        ((fn (self i) (unless (= i 10) (do (%ej-oset! v (+ i 1) (%peek (+ off i))) (self (+ i 1))))) 0)
        v))
    (def %fill (fn (_ off v) ((fn (self i) (unless (= i 10) (do (%poke (+ off i) (if (= i 0) v 0)) (self (+ i 1))))) 0)))
    (def %sq (fn (_ h f) (%mul %addr h f f)))
    (%load! %D2 d2)
    ; the accumulator doubled (ref10 ge_p2_dbl) into the completed form
    (def %double!
      (fn (_)
        (%sq %T0 %X) (%sq %T1 %Y) (%sq %T2 %Z) (%add %addr %T2 %T2 %T2)
        (%add %addr %T3 %X %Y) (%sq %T3 %T3)
        (%add %addr %Yc %T1 %T0) (%sub %addr %Zc %T1 %T0)
        (%sub %addr %Xc %T3 %Yc) (%sub %addr %Tc %T2 %Zc)))
    ; the accumulator plus the cached addend (ref10 ge_add), completed
    (def %add-cached!
      (fn (_)
        (%add %addr %A %Y %X) (%mul %addr %A %A %YpX)
        (%sub %addr %B %Y %X) (%mul %addr %B %B %YmX)
        (%mul %addr %C %T2d %T)
        (%mul %addr %D %Z %Zq) (%add %addr %D %D %D)
        (%sub %addr %Xc %A %B) (%add %addr %Yc %A %B)
        (%add %addr %Zc %D %C) (%sub %addr %Tc %D %C)))
    ; the completed form made the accumulator again (ref10 p1p1_to_p3)
    (def %complete!
      (fn (_)
        (%mul %addr %X %Xc %Tc) (%mul %addr %Y %Yc %Zc)
        (%mul %addr %Z %Zc %Tc) (%mul %addr %T %Xc %Yc)))
    (def %engine
      (fn (_ k p)
        ; the addend cached: Y+X, Y-X, Z, 2dT
        (%load! %Zq (first (rest (rest p))))
        (%load! %T0 (first p)) (%load! %T1 (first (rest p))) (%load! %T2d (first (rest (rest (rest p)))))
        (%add %addr %YpX %T1 %T0) (%sub %addr %YmX %T1 %T0)
        (%mul %addr %T2d %T2d %D2)
        (%fill %X 0) (%fill %Y 1) (%fill %Z 1) (%fill %T 0)
        ((fn (self bit)
           (unless (< bit 0)
             (do (%double!) (%complete!)
                 (when (= (& (>> (%ej-char->int (%ej-byte-ref k (>> bit 3))) (& bit 7)) 1) 1)
                   (%add-cached!) (%complete!))
                 (self (- bit 1)))))
         255)
        (list (%store %X) (%store %Y) (%store %Z) (%store %T))))
    ; The field operations were proven against the pure-x field when they
    ; were built; what is left to prove is the double-and-add over them,
    ; and RFC 8032's test 1 proves it: its seed's clamped scalar times the
    ; base point encodes as its public key, the bytes the pure-x
    ; function's spec holds it to.  The encoding's inverse is the field
    ; engine's chain, itself checked where it is built.
    (def %invert (first (fe-jit-chains)))
    (def %pow22523 (first (rest (fe-jit-chains))))
    (def %pset1 (prim-ref (lit ptr) (lit set!)))
    (def %encode
      (fn (_ p)
        (def recip (%invert (List ref 2 p)))
        (def xb (fe-tobytes (fe-mul (first p) recip)))
        (def s (fe-tobytes (fe-mul (first (rest p)) recip)))
        (when (= (& (%ej-char->int (%ej-byte-ref xb 0)) 1) 1)
          (%pset1 (%ej-str->ptr s) 31 (| (%ej-char->int (%ej-byte-ref s 31)) 128) 1))
        s))
    (def %hex-bytes
      (fn (_ hex)
        (def n (>> (Str8 length hex) 1))
        (def s (%ej-make-str n))
        (def p (%ej-str->ptr s))
        (def %digit (fn (_ c) (if (< c 58) (- c 48) (- c 87))))
        ((fn (self i)
           (unless (= i n)
             (do (%pset1 p i (| (<< (%digit (%ej-char->int (%ej-byte-ref hex (* 2 i)))) 4)
                                (%digit (%ej-char->int (%ej-byte-ref hex (+ (* 2 i) 1))))) 1)
                 (self (+ i 1))))) 0)
        s))
    (def %same
      (fn (self x y i)
        (if (= i 32) #t
          (if (= (%ej-char->int (%ej-byte-ref x i)) (%ej-char->int (%ej-byte-ref y i)))
            (self x y (+ i 1))
            #f))))
    (unless (%same (%encode (%engine (%hex-bytes "307c83864f2833cb427a2ef1c00a013cfdff2768d980c0a3a520f006904de94f") base))
                   (%hex-bytes "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a") 0)
      (Err raise 'state "ed25519-jit: engine disagrees with RFC 8032" ()))
    (list %engine %invert %pow22523)))

; The codec reaches the maker through the catalogue: it loads this module
; inside the function that builds its engine, and a name imported there is
; one the linter cannot see.
(prim-reg! (lit ed25519) (lit jit-make) ed25519-jit-make)

(doc (provide x/codec/ed25519-jit ed25519-jit-make)
  "The compiled Ed25519 scalar multiplication, inverse and square root's power (JIT, ARM64 and x86-64 backends) over x/codec/fe25519-jit's checked operations; built and adopted only via (Ed25519 jit!) after answering RFC 8032's test 1.")

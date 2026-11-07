; x25519.x -- X25519: Diffie-Hellman on Curve25519 (RFC 7748) in pure x-lang.
;
; The key exchange of curve25519-sha256, the first an SSH written in x
; offers and the one Dropbear and OpenSSH prefer; it needs the function
; where no C library is present.  (X25519 scalarmult k u) is the RFC's
; function, (X25519 base k) its public key, both 32 bytes.
;
; The field is x/codec/fe25519's -- GF(2^255 - 19) on ref10's ten
; signed limbs, tower-proof on the int prims -- and this module is the
; RFC's Montgomery ladder over it, bit by bit from the top, with the
; inverse's 2^255 - 21 power chain at the end.  A compiled engine in
; x/codec/x25519-jit takes the field operations and is adopted only after
; it agrees with this one; a 4-byte word runs the ladder's step as a
; program on fe25519's engine.  This is not constant time: an interpreter
; branches on the data it handles, and the swap here is a branch.
(module x/codec/x25519)

(import x/type/vector)
; Collection is explicit-trigger-only; an exchange makes three thousand
; field elements and their arithmetic's integers, so the ladder and the
; inverse collect at fixed points, as sha1.x's block loop does.
(import x/sys/gc)
; The compiled engine is on Compiled's list.
(import x/tool/compiled)

(import x/core/doors char->int int* int+ int- obj-ref obj-set! ptr-set! str->ptr str-byte-ref str-make)

(def %byte (fn (_ s i) (char->int (str-byte-ref s i))))

(import x/codec/fe25519 fe-zero fe-limbs fe-frombytes fe-tobytes fe-add fe-sub fe-mul fe-sq fe-mul121666 fe-invert fe-engine)
; a 4-byte word's ladder
(import x/codec/mont-jit mont-jit-load! mont-jit-store mont-jit-program mont-jit-run!)

; The clamped scalar's bit at position pos.
(def %bit
  (fn (_ k pos)
    (def b (%byte k (>> pos 3)))
    (def c (match ((< pos 8) (& b 248))
                  ((>= pos 248) (| (& b 127) 64))
                  (#t b)))
    (& (>> c (& pos 7)) 1)))

; The ladder (RFC 7748 5): from the top bit down, one differential
; addition and doubling a step, the pair swapped when the bit changes.
(def %ladder
  (fn (self k x1 x2 z2 x3 z3 swap pos)
    ; every sixteenth step returns the steps' garbage: the live set is the
    ; five elements in hand, and a collect marks the whole session
    (when (= (& pos 15) 0) (Heap collect))
    (def b (%bit k pos))
    (def sw (^ swap b))
    (def a2 (if (= sw 1) x3 x2)) (def c2 (if (= sw 1) z3 z2))
    (def a3 (if (= sw 1) x2 x3)) (def c3 (if (= sw 1) z2 z3))
    (def tmp0 (fe-sub a3 c3))
    (def tmp1 (fe-sub a2 c2))
    (def xx2 (fe-add a2 c2))
    (def zz2 (fe-add a3 c3))
    (def zz3 (fe-mul tmp0 xx2))
    (def zz2b (fe-mul zz2 tmp1))
    (def tmp0b (fe-sq tmp1))
    (def tmp1b (fe-sq xx2))
    (def xx3 (fe-add zz3 zz2b))
    (def zz2c (fe-sub zz3 zz2b))
    (def xx2b (fe-mul tmp1b tmp0b))
    (def tmp1c (fe-sub tmp1b tmp0b))
    (def zz2d (fe-sq zz2c))
    (def zz3b (fe-mul121666 tmp1c))
    (def xx3b (fe-sq xx3))
    (def tmp0c (fe-add tmp0b zz3b))
    (def zz3c (fe-mul x1 zz2d))
    (def zz2e (fe-mul tmp1c tmp0c))
    (if (= pos 0)
      (if (= b 1) (list xx3b zz3c) (list xx2b zz2e))
      (self k x1 xx2b zz2e xx3b zz3c b (int- pos 1)))))

; The pure-x function: k and u as 32-byte strings -> 32 bytes.  The
; compiled engine answers the same bytes, so it is a drop-in.
(def %scalarmult
  (fn (_ k u)
    (def x1 (fe-frombytes u))
    (def r (%ladder k x1 (fe-limbs (list 1)) (fe-zero) x1 (fe-limbs (list 1)) 0 254))
    (fe-tobytes (fe-mul (first r) (fe-invert (first (rest r)))))))

; --- The ladder on a 4-byte word ---------------------------------------
;
; There the field is x/codec/mont-jit's engine (fe-engine), where an
; operation through x is a load, a call and a store: the ladder's step is
; written to the engine as a program once, in two orders -- the swap is
; which slots it reads -- and run in one call a step.  The slots: x1, the
; pair x2 z2 and x3 z3, the constant, then eighteen temporaries.
(def %narrow (< %word-size 8))
(def %X1 3) (def %X2 4) (def %Z2 5) (def %X3 6) (def %Z3 7) (def %C 8)
(def %t (fn (_ k) (+ 9 k)))

; The step of %ladder above, from (a2 c2 a3 c3), its four answers left in
; x2 z2 x3 z3.
(def %step
  (fn (_ a2 c2 a3 c3)
    (list (list (lit sub) (%t 0) a3 c3) (list (lit sub) (%t 1) a2 c2)
          (list (lit add) (%t 2) a2 c2) (list (lit add) (%t 3) a3 c3)
          (list (lit mul) (%t 4) (%t 0) (%t 2)) (list (lit mul) (%t 5) (%t 3) (%t 1))
          (list (lit mul) (%t 6) (%t 1) (%t 1)) (list (lit mul) (%t 7) (%t 2) (%t 2))
          (list (lit add) (%t 8) (%t 4) (%t 5)) (list (lit sub) (%t 9) (%t 4) (%t 5))
          (list (lit mul) (%t 10) (%t 7) (%t 6)) (list (lit sub) (%t 11) (%t 7) (%t 6))
          (list (lit mul) (%t 12) (%t 9) (%t 9)) (list (lit mul) (%t 13) (%t 11) %C)
          (list (lit mul) (%t 14) (%t 8) (%t 8)) (list (lit add) (%t 15) (%t 6) (%t 13))
          (list (lit mul) (%t 16) %X1 (%t 12)) (list (lit mul) (%t 17) (%t 11) (%t 15))
          (list (lit copy) %X2 (%t 10)) (list (lit copy) %Z2 (%t 17))
          (list (lit copy) %X3 (%t 14)) (list (lit copy) %Z3 (%t 16)))))

; the two programs, made on the engine the first time: unswapped, swapped
(def %progs ())
; written into fe-engine's table, so dropped with it from an image
((prim-ref (lit image) (lit transient!)) (fn (_) (set! %progs ())))

(def %scalarmult-narrow
  (fn (_ k u)
    (def e (fe-engine))
    (when (null? %progs)
      (set! %progs (list (mont-jit-program e (%step %X2 %Z2 %X3 %Z3)) (mont-jit-program e (%step %X3 %Z3 %X2 %Z2)))))
    (def x1 (fe-frombytes u))
    (def one (fe-limbs (list 1)))
    (mont-jit-load! e %X1 x1)
    (mont-jit-load! e %X2 one)
    (mont-jit-load! e %Z2 (fe-zero))
    (mont-jit-load! e %X3 x1)
    (mont-jit-load! e %Z3 one)
    (mont-jit-load! e %C (fe-limbs (list 121666)))
    (def last
      ((fn (self swap pos)
         (do (when (= (& pos 15) 0) (Heap collect))
             (def b (%bit k pos))
             (mont-jit-run! e (if (= (^ swap b) 1) (first (rest %progs)) (first %progs)))
             (if (= pos 0) b (self b (int- pos 1)))))
       0 254))
    (def x (mont-jit-store e (if (= last 1) %X3 %X2)))
    (def z (mont-jit-store e (if (= last 1) %Z3 %Z2)))
    (fe-tobytes (fe-mul x (fe-invert z)))))

(def %nine
  (fn (_)
    (def s (str-make 32))
    (def p (str->ptr s))
    ((fn (self i) (unless (= i 32) (do (ptr-set! p i (if (= i 0) 9 0) 1) (self (int+ i 1))))) 0)
    s))

; --- The compiled engine (JIT), adopted only when it proves out ------
;
; As chacha20.x's: an entry of Compiled's, made the first time a build is
; asked for, interpreted by %scalarmult above, and built on (X25519 jit!)
; -- never on its own, so the pure-x function stays what a host without
; the JIT runs and what the specs prove.
(def %entry ())

(def %jit-try!
  (fn (_)
    (when (null? %entry)
      (set! %entry
        (Compiled make-on-demand (lit x25519) %scalarmult
          (fn (_)
            (import x/codec/x25519-jit)
            ((prim-ref (lit x25519) (lit jit-make)) fe-frombytes fe-tobytes))
          (fn (_ v) ()))))
    ((fn (_ entry)
       (when (eq? (entry state) (lit interpreted)) (entry compile!))
       (eq? (entry state) (lit compiled)))
     %entry)))

(def %run
  (fn (_ k u)
    ((fn (_ entry)
       (if (if (null? entry) #f (eq? (entry state) (lit compiled)))
         ((entry compiled) k u)
         (if %narrow (%scalarmult-narrow k u) (%scalarmult k u))))
     %entry)))

(def-class X25519 ()
  (static
    (method scalarmult (self (param k STRING "The scalar: 32 bytes are read, clamped as the RFC says")
                             (param u STRING "The u-coordinate: 32 bytes are read, little-endian, the top bit ignored"))
      (doc "X25519 (RFC 7748 5): the u-coordinate of k times the point at u, as 32 little-endian bytes. With a peer's public key as u this is the shared secret; the caller checks it against all zeros if its protocol says to. Computed pure-x, or by the differentially-verified compiled engine once (jit!) has built it -- identical output either way. Not constant time."
        (returns STRING "32 bytes"))
      (%run k u))
    (method base (self (param k STRING "The private key: 32 bytes are read"))
      (doc "The public key for k: k times the base point, u = 9."
        (returns STRING "32 bytes"))
      (%run k (%nine)))
    (method jit! (self)
      (doc "Build and adopt the compiled ladder (JIT; ARM64 and x86-64 backends) now, if it answers RFC 7748's exchange and the field operations under it agree with the pure-x field. Idempotent. Returns #t when the engine is active, #f when unavailable -- pure-x carries on and results are identical either way. scalarmult never builds it on its own, so the pure-x function stays what a host without the JIT runs and what the specs prove; the build costs less than one pure-x exchange, so a process that exchanges keys asks for it."
        (returns BOOL "#t when the compiled engine is active"))
      (%jit-try!))))

(doc (provide x/codec/x25519 X25519)
  "X25519 (RFC 7748): (X25519 scalarmult k u) and (X25519 base k), 32 bytes each. Pure x-lang on ref10's ten-limb field, with an optional differentially-verified JIT engine ((X25519 jit!)).")

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
; it agrees with this one.  This is not constant time: an interpreter
; branches on the data it handles, and the swap here is a branch.
(module x/codec/x25519)

(import x/type/vector)
; Collection is explicit-trigger-only; an exchange makes three thousand
; field elements and their arithmetic's integers, so the ladder and the
; inverse collect at fixed points, as sha1.x's block loop does.
(import x/sys/gc)
; The compiled engine is on Compiled's list.
(import x/tool/compiled)

(def %add (prim-ref 'int '+))
(def %sub (prim-ref 'int '-))
(def %mul (prim-ref 'int '*))
(def %oref (prim-ref (lit obj) (lit ref)))
(def %oset! (prim-ref (lit obj) (lit set!)))
(def %byte-ref (prim-ref (lit str) (lit byte-ref)))
(def %char->int (prim-ref (lit char) (lit ->int)))
(def %make-str (prim-ref (lit str) (lit make)))
(def %str->ptr (prim-ref (lit str) (lit ->ptr)))
(def %pset1 (prim-ref (lit ptr) (lit set!)))

(def %byte (fn (_ s i) (%char->int (%byte-ref s i))))

(import x/codec/fe25519 fe-zero fe-limbs fe-frombytes fe-tobytes fe-add fe-sub fe-mul fe-sq fe-mul121666 fe-invert)

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
      (self k x1 xx2b zz2e xx3b zz3c b (%sub pos 1)))))

; The pure-x function: k and u as 32-byte strings -> 32 bytes.  The
; compiled engine answers the same bytes, so it is a drop-in.
(def %scalarmult
  (fn (_ k u)
    (def x1 (fe-frombytes u))
    (def r (%ladder k x1 (fe-limbs (list 1)) (fe-zero) x1 (fe-limbs (list 1)) 0 254))
    (fe-tobytes (fe-mul (first r) (fe-invert (first (rest r)))))))

(def %nine
  (fn (_)
    (def s (%make-str 32))
    (def p (%str->ptr s))
    ((fn (self i) (unless (= i 32) (do (%pset1 p i (if (= i 0) 9 0) 1) (self (%add i 1))))) 0)
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
         (%scalarmult k u)))
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

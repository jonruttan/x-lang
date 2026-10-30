; ghash.x -- GHASH: GCM's universal hash (NIST SP 800-38D 6.4).
;
; What AES-GCM authenticates with: the additional data and the
; ciphertext, each padded with zeros to a whole block, then their lengths
; in bits as two big-endian 64-bit integers, folded block by block as
; Y = (Y xor X) * H in GF(2^128), H the cipher of the zero block.
;
; The pure-x multiply is SP 800-38D's own algorithm 1, a bit at a time
; over four 32-bit words -- the reference.  Over a connection's traffic
; the hash is x/codec/ghash-jit's compiled engine, adopted once it agrees
; with it.  The field's bits are GCM's: the first byte's top bit is the
; coefficient of x^0.
(module x/codec/ghash)

(import x/type/vector)
(import x/codec/bytes)
; The compiled engine is on Compiled's list.
(import x/tool/compiled)

(def %byte-ref (prim-ref (lit str) (lit byte-ref)))
(def %char->int (prim-ref (lit char) (lit ->int)))
(def %make-str (prim-ref (lit str) (lit make)))
(def %str->ptr (prim-ref (lit str) (lit ->ptr)))
(def %pset1 (prim-ref (lit ptr) (lit set!)))
(def %oref (prim-ref (lit obj) (lit ref)))
(def %oset! (prim-ref (lit obj) (lit set!)))
; No int xor: a ^ b is (a | b) - (a & b).
(def %xor (fn (_ a b) (- (| a b) (& a b))))

(def %byte (fn (_ s i) (%char->int (%byte-ref s i))))

; Word k of the block at s[at..]: bytes 4k..4k+3, big-endian.
(def %word
  (fn (_ s at k)
    (def i (+ at (* 4 k)))
    (| (<< (%byte s i) 24) (| (<< (%byte s (+ i 1)) 16) (| (<< (%byte s (+ i 2)) 8) (%byte s (+ i 3)))))))

; X * Y in GF(2^128), each four words in slots 1..4 (algorithm 1): Z
; gathers V for each set bit of X, first bit first; V moves right a bit
; a step, R folded in when a bit falls off.
(def %mul
  (fn (_ x y)
    (def z (Vector make 4 0))
    (def v (Vector make 4 0))
    ((fn (self k) (unless (= k 5) (do (%oset! v k (%oref y k)) (self (+ k 1))))) 1)
    ((fn (self i)
       (unless (= i 128)
         (do (when (= (& (>> (%oref x (+ (>> i 5) 1)) (- 31 (& i 31))) 1) 1)
               (%oset! z 1 (%xor (%oref z 1) (%oref v 1))) (%oset! z 2 (%xor (%oref z 2) (%oref v 2)))
               (%oset! z 3 (%xor (%oref z 3) (%oref v 3))) (%oset! z 4 (%xor (%oref z 4) (%oref v 4))))
             (def low (& (%oref v 4) 1))
             (%oset! v 4 (| (>> (%oref v 4) 1) (<< (& (%oref v 3) 1) 31)))
             (%oset! v 3 (| (>> (%oref v 3) 1) (<< (& (%oref v 2) 1) 31)))
             (%oset! v 2 (| (>> (%oref v 2) 1) (<< (& (%oref v 1) 1) 31)))
             (%oset! v 1 (>> (%oref v 1) 1))
             (when (= low 1) (%oset! v 1 (%xor (%oref v 1) 3774873600)))
             (self (+ i 1)))))
     0)
    z))

; The words as a fresh 16-byte string.
(def %block-string
  (fn (_ w)
    (def out (%make-str 16))
    (def p (%str->ptr out))
    ((fn (self i)
       (unless (= i 16)
         (do (%pset1 p i (& (>> (%oref w (+ (>> i 2) 1)) (- 24 (* 8 (& i 3)))) 255) 1)
             (self (+ i 1)))))
     0)
    out))

; The pure-x hash: H and an input of whole blocks, len a multiple of 16
; -> the 16-byte result.  The compiled engine answers the same string.
(def %hash-blocks
  (fn (_ h s len)
    (def hw (Vector make 4 0))
    ((fn (self k) (unless (= k 4) (do (%oset! hw (+ k 1) (%word h 0 k)) (self (+ k 1))))) 0)
    (def x (Vector make 4 0))
    ((fn (self at y)
       (if (>= at len) (%block-string y)
         (do ((fn (self k) (unless (= k 4) (do (%oset! x (+ k 1) (%xor (%oref y (+ k 1)) (%word s at k))) (self (+ k 1))))) 0)
             (self (+ at 16) (%mul x hw)))))
     0 (Vector make 4 0))))

; --- The compiled engine (JIT), adopted only when it proves out ------
(def %entry ())
(def %jit-threshold 256)

(def %jit-try!
  (fn (_)
    (when (null? %entry)
      (set! %entry
        (Compiled make-on-demand (lit ghash) %hash-blocks
          (fn (_)
            (import x/codec/ghash-jit)
            ((prim-ref (lit ghash) (lit jit-make)) %hash-blocks))
          (fn (_ v) ()))))
    ((fn (_ entry)
       (when (eq? (entry state) (lit interpreted)) (entry compile!))
       (eq? (entry state) (lit compiled)))
     %entry)))

(def %run
  (fn (_ h s len)
    (when (if (< len %jit-threshold) #f
            ((fn (_ entry) (if (null? entry) #t (eq? (entry state) (lit interpreted))))
             %entry))
      (%jit-try!))
    ((fn (_ entry)
       (if (if (null? entry) #f (eq? (entry state) (lit compiled)))
         ((entry compiled) h s len)
         (%hash-blocks h s len)))
     %entry)))

; The hash's input: a's region and c's, each zero-padded to a block, then
; their lengths in bits, big-endian 64-bit each -- joined by memcpy
; (Bytes join), where a loop in x is a few objects a byte.  The pads and
; the lengths come from one 32-byte tail: sixteen zeros, then the lengths.
(def %pad16 (fn (_ n) (& (- 16 (& n 15)) 15)))

(def %input
  (fn (_ a a-start a-len c c-start c-len)
    (def t (%make-str 32))
    (def p (%str->ptr t))
    (def put64
      (fn (_ where bits)
        ((fn (self i) (unless (= i 8) (do (%pset1 p (+ where i) (& (>> bits (* 8 (- 7 i))) 255) 1) (self (+ i 1))))) 0)))
    (put64 0 0)
    (put64 8 0)
    (put64 16 (* 8 a-len))
    (put64 24 (* 8 c-len))
    (def in (Bytes join (list a a-start a-len) (list t 0 (%pad16 a-len))
                        (list c c-start c-len) (list t 0 (%pad16 c-len)) (list t 16 16)))
    (pair (first in) (first (rest (rest in))))))

(def-class Ghash ()
  (static
    (method hash (self (param h STRING "The hash key H: 16 bytes are read, AES's cipher of the zero block")
                       (param a STRING "The additional data")
                       (param a-start INTEGER "Where a's region starts")
                       (param a-len INTEGER "Its length in bytes")
                       (param c STRING "The ciphertext")
                       (param c-start INTEGER "Where c's region starts")
                       (param c-len INTEGER "Its length in bytes"))
      (doc "GHASH (NIST SP 800-38D 6.4) of additional data and ciphertext under H: each region zero-padded to a 16-byte block, then their lengths in bits, folded as Y = (Y xor X) * H in GF(2^128). Answered as a fresh 16-byte string -- binary, so read it by count. Computed pure-x, or by the differentially-verified compiled engine once (jit!) has built it -- identical output either way."
        (returns STRING "16 bytes"))
      (def in (%input a a-start a-len c c-start c-len))
      (%run h (first in) (rest in)))
    (method jit! (self)
      (doc "Build and adopt the compiled GHASH engine (JIT; ARM64 and x86-64 backends) now, if it can prove itself against the pure-x hash. Idempotent. Returns #t when the engine is active, #f when unavailable -- pure-x carries on and results are identical either way. hash also builds it on its own for an input of 256 bytes or more."
        (returns BOOL "#t when the compiled engine is active"))
      (%jit-try!))))

(doc (provide x/codec/ghash Ghash)
  "GHASH (NIST SP 800-38D): (Ghash hash h a a-start a-len c c-start c-len) is GCM's hash of additional data and ciphertext under H. Pure x-lang, with an optional differentially-verified JIT engine ((Ghash jit!), or built on its own for an input of 256 bytes or more).")

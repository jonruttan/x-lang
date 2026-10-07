; sha1.x -- Sha1: the SHA-1 digest (FIPS 180-4) in pure x-lang.
;
; git names every object by its SHA-1, so a git written in x needs this
; digest where no C library is present.  It is not for security: SHA-1 is
; broken for collision resistance, and Sha256 is the digest to trust.
;
; The shape is sha256.x's: pure INT on the C bit ops, every addition
; through the cached int '+ prim and masked to 32 bits, so the digest is
; tower-proof; the padded message addressed virtually, with no padded copy
; built; and a compiled engine in x/codec/sha-jit, adopted only after it
; agrees with this digest.  The constants are written in decimal, each
; beside its FIPS hex spelling.
(module x/codec/sha1)

(import x/type/vector)
; Collection is explicit-trigger-only; the block loop collects as sha256.x's
; does, for the same reason.
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
(def %cvt (prim-ref (lit convert) (lit to)))
(def %string-type (Type named STRING))
(def %mask 4294967295)

; 67452301 efcdab89 98badcfe 10325476 c3d2e1f0 (5.3.1)
(def %ih (list 1732584193 4023233417 2562383102 271733878 3285377520))

(def %rotl (fn (_ x n) (& (| (<< x n) (>> x (%sub 32 n))) %mask)))

; Byte i of the padded message: the message; then 0x80; then zeros; then
; the bit length, big-endian in the last 8 bytes.
(def %byte
  (fn (_ s len total i)
    (match
      ((< i len) (%char->int (%byte-ref s i)))
      ((= i len) 128)
      ((< i (%sub total 8)) 0)
      (#t (& (>> (%mul len 8) (<< (%sub (%sub total 1) i) 3)) 255)))))

(def %word
  (fn (_ s len total base)
    (| (<< (%byte s len total base) 24)
       (| (<< (%byte s len total (%add base 1)) 16)
          (| (<< (%byte s len total (%add base 2)) 8)
             (%byte s len total (%add base 3)))))))

; W[t] in slot t+1 of an 80-slot vector (the length rides slot 0).
(def %fill!
  (fn (self s len total base w t)
    (unless (= t 16)
      (do (%oset! w (%add t 1) (%word s len total (%add base (<< t 2))))
          (self s len total base w (%add t 1))))))

(def %extend!
  (fn (self w t)
    (unless (= t 80)
      ; slots fold the +1: W[t-3] is slot t-2, and so on
      (do (%oset! w (%add t 1)
            (%rotl (^ (%oref w (%sub t 2))
                      (^ (%oref w (%sub t 7))
                         (^ (%oref w (%sub t 13)) (%oref w (%sub t 15)))))
                   1))
          (self w (%add t 1))))))

; f and K by the round's twenty (4.1.1, 4.2.1).
(def %f
  (fn (_ t b c d)
    (match
      ((< t 20) (| (& b c) (& (& (~ b) %mask) d)))
      ((< t 40) (^ b (^ c d)))
      ((< t 60) (| (| (& b c) (& b d)) (& c d)))
      (#t (^ b (^ c d))))))

; 5a827999 6ed9eba1 8f1bbcdc ca62c1d6
(def %k
  (fn (_ t)
    (match
      ((< t 20) 1518500249)
      ((< t 40) 1859775393)
      ((< t 60) 2400959708)
      (#t 3395469782))))

(def %rounds
  (fn (self w t a b c d e)
    (match
      ((= t 80) (list a b c d e))
      (#t
        (self w (%add t 1)
          (& (%add (%add (%rotl a 5) (%f t b c d))
                   (%add (%add e (%k t)) (%oref w (%add t 1))))
             %mask)
          a (%rotl b 30) c d)))))

(def %sum
  (fn (self hs rs)
    (if (null? hs) ()
      (pair (& (%add (first hs) (first rs)) %mask) (self (rest hs) (rest rs))))))

(def %blocks
  (fn (self s len total base w hs)
    (match
      ; one collect at completion returns the digest's net growth to zero,
      ; as sha256.x's does (#294)
      ((= base total) (do (Heap collect) hs))
      (#t
        (do (when (and (> base 0) (= (& (>> base 6) 7) 0)) (Heap collect))
            (%fill! s len total base w 0)
            (%extend! w 16)
            (self s len total (%add base 64) w
              (%sum hs
                (%rounds w 0 (first hs) (first (rest hs)) (first (rest (rest hs)))
                  (first (rest (rest (rest hs)))) (first (rest (rest (rest (rest hs)))))))))))))

; The pure-x digest: bytes -> the five H words.  The compiled engine
; answers the same list, so it is a drop-in for this function.  The
; optional length is the caller's claim, as Sha256 hex-n's is.
(def %digest-words
  (fn (_ s . n)
    (def len (match ((null? n) (Str8 length s)) (#t (first n))))
    (%blocks s len (<< (%add (>> (%add len 8) 6) 1) 6) 0 (Vector make 80 0) %ih)))

(def %hex8 (fn (_ wd) (Str pad-left 8 #\0 (%cvt wd %string-type 16))))

(def %hex (fn (_ hs) (Str8 join "" (List map %hex8 hs))))

; --- The compiled engine (JIT), adopted only when it proves out ------
;
; As sha256.x's: an entry of Compiled's, made the first time a build is
; asked for, interpreted by the pure-x digest above, and built only for an
; input of %jit-threshold bytes or more or on (Sha1 jit!).
(def %entry ())
(def %jit-threshold 12288)

(def %jit-try!
  (fn (_)
    (when (null? %entry)
      (set! %entry
        (Compiled make-on-demand (lit sha1) %digest-words
          (fn (_)
            (import x/codec/sha-jit)
            ((prim-ref (lit sha1) (lit jit-make)) %ih %digest-words))
          (fn (_ v) ()))))
    ((fn (_ entry)
       (when (eq? (entry state) (lit interpreted)) (entry compile!))
       (eq? (entry state) (lit compiled)))
     %entry)))

(def %words
  (fn (_ s . n)
    (def len (match ((null? n) (Str8 length s)) (#t (first n))))
    (when (and (>= len %jit-threshold)
               ((fn (_ entry) (if (null? entry) #t (eq? (entry state) (lit interpreted))))
                %entry))
      (%jit-try!))
    ((fn (_ entry)
       (if (if (null? entry) #f (eq? (entry state) (lit compiled)))
         ((entry compiled) s len)
         (%digest-words s len)))
     %entry)))

(def-class Sha1 ()
  (static
    (method hex (self (param s STRING "Bytes to digest (a byte string)"))
      (doc "SHA-1 digest of s, as a 40-character lowercase hex string (FIPS 180-4). For naming content, as git does; SHA-1 is broken for collision resistance, so use Sha256 to trust. Computed pure-x, or by the differentially-verified compiled engine once (jit!) has built it -- identical output either way."
        (returns STRING "40 hex characters")
        (example "(Sha1 hex \"\")" "\"da39a3ee5e6b4b0d3255bfef95601890afd80709\"")
        (example "(Sha1 hex \"abc\")" "\"a9993e364706816aba3e25717850c26c9cd0d89d\""))
      (%hex (%words s)))
    (method hex-n (self (param s STRING "Byte region to digest")
                        (param n INTEGER "How many bytes of s to digest"))
      (doc "SHA-1 of the FIRST n BYTES of s, for binary input hex cannot measure (Str8 length stops at the first NUL). THE LENGTH IS YOUR CLAIM AND IS NOT CHECKED: n past the region's allocation reads past the allocation."
        (returns STRING "40 hex characters")
        (example "(Sha1 hex-n \"abc\" 3)" "\"a9993e364706816aba3e25717850c26c9cd0d89d\"")
        (example "(Sha1 hex-n \"abc\" 0)" "\"da39a3ee5e6b4b0d3255bfef95601890afd80709\""))
      (%hex (%words s n)))
    (method jit! (self)
      (doc "Build and adopt the compiled digest engine (JIT; ARM64 and x86-64 backends) now, if it can prove itself against the pure-x digest. Idempotent. Returns #t when the engine is active, #f when unavailable -- pure-x carries on and results are identical either way. hex also builds it on its own for any single input of 12KB or more."
        (returns BOOL "#t when the compiled engine is active"))
      (%jit-try!))))

(doc (provide x/codec/sha1 Sha1)
  "SHA-1 (FIPS 180-4): (Sha1 hex s) digests a byte string. Pure x-lang, with an optional differentially-verified JIT engine ((Sha1 jit!), or built on its own for an input of 12KB or more).")

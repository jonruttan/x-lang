; sha3.x -- Sha3: the SHA-3 digest (FIPS 202) in pure x-lang.
;
; Keccak-f[1600]: twenty-five 64-bit lanes, a block of RATE bytes -- 200
; less a quarter of the width -- xored into them little-endian, then the
; twenty-four rounds.  The message ends with SHA-3's domain bits, 0x06, and
; the block's last byte or'd with 0x80; the digest is the state's first
; WIDTH/8 bytes.  Keccak has no additions, so unlike sha512.x a lane is one
; engine int: xor, and, not and the left shift wrap as the standard wants,
; and the only care is the right shift, which is arithmetic and is masked
; after to be logical.  The padded message is addressed virtually, with no
; copy built, and a compiled engine in x/codec/sha3-jit is adopted only
; after it agrees with this one.  The round constants are the standard's
; hex spellings, each as two 32-bit halves.
(module x/codec/sha3)

(import x/type/vector)
(import x/sys/gc)
(import x/tool/compiled)

(def %add (prim-ref 'int '+))
(def %sub (prim-ref 'int '-))
(def %mul (prim-ref 'int '*))
(def %div (prim-ref (lit int) (lit /)))
(def %mod (prim-ref (lit int) (lit %)))
(def %oref (prim-ref (lit obj) (lit ref)))
(def %oset! (prim-ref (lit obj) (lit set!)))
(def %byte-ref (prim-ref (lit str) (lit byte-ref)))
(def %char->int (prim-ref (lit char) (lit ->int)))
(def %cvt (prim-ref (lit convert) (lit to)))

; hex halves to the 64-bit words they spell, hi shifted over lo; the %cvt
; narrows a tower integer to the C int the bit ops take (sha512.x)
(def %lanes
  (let ((int-type (Type named INTEGER)))
    (fn (self hexes)
      (if (null? hexes) ()
        (pair (| (<< (%cvt (%str->number (first hexes) 16) int-type) 32)
                 (%cvt (%str->number (first (rest hexes)) 16) int-type))
              (self (rest (rest hexes))))))))

; the round constants (3.2.5), hi then lo
(def %rc (Vector from-list (%lanes (lit (
  "00000000" "00000001"  "00000000" "00008082"  "80000000" "0000808a"  "80000000" "80008000"
  "00000000" "0000808b"  "00000000" "80000001"  "80000000" "80008081"  "80000000" "00008009"
  "00000000" "0000008a"  "00000000" "00000088"  "00000000" "80008009"  "00000000" "8000000a"
  "00000000" "8000808b"  "80000000" "0000008b"  "80000000" "00008089"  "80000000" "00008003"
  "80000000" "00008002"  "80000000" "00000080"  "00000000" "0000800a"  "80000000" "8000000a"
  "80000000" "80008081"  "80000000" "00008080"  "00000000" "80000001"  "80000000" "80008008"
)))))

; lane X+5Y's rotation (3.2.2), and where pi moves it: Y + 5((2X + 3Y) mod 5)
(def %rot (Vector from-list (lit (0 1 62 28 27 36 44 6 55 20 3 10 43 25 39 41 45 15 21 8 18 2 61 56 14))))
(def %pi (Vector from-list (lit (0 10 20 5 15 16 1 11 21 6 7 17 2 12 22 23 8 18 3 13 14 24 9 19 4))))

; the mask that makes an arithmetic shift right by N logical: 64-N ones
(def %lmask
  (fn (_ n) (if (= n 1) 9223372036854775807 (%sub (<< 1 (%sub 64 n)) 1))))

(def %rotl
  (fn (_ x n) (if (= n 0) x (| (<< x n) (& (>> x (%sub 64 n)) (%lmask (%sub 64 n)))))))

; vector slot I of V (slot 0 of a Vector's object holds its length)
(def %v (fn (_ v i) (%oref v (%add i 1))))
(def %v! (fn (_ v i x) (%oset! v (%add i 1) x)))

; theta: each column's parity, mixed into the lanes beside it
(def %theta!
  (fn (_ a c)
    ((fn (self x)
       (unless (= x 5)
         (do (%v! c x (^ (%v a x) (^ (%v a (%add x 5)) (^ (%v a (%add x 10)) (^ (%v a (%add x 15)) (%v a (%add x 20)))))))
             (self (%add x 1))))) 0)
    ((fn (self i)
       (unless (= i 25)
         (do (def x (%mod i 5))
             (%v! a i (^ (%v a i) (^ (%v c (%mod (%add x 4) 5)) (%rotl (%v c (%mod (%add x 1) 5)) 1))))
             (self (%add i 1))))) 0)))

; rho and pi into B, then chi back into A, then iota
(def %rest!
  (fn (_ a b r)
    ((fn (self i)
       (unless (= i 25)
         (do (%v! b (%v %pi i) (%rotl (%v a i) (%v %rot i)))
             (self (%add i 1))))) 0)
    ((fn (self i)
       (unless (= i 25)
         (do (def x (%mod i 5))
             (def row (%sub i x))
             (%v! a i (^ (%v b i) (& (~ (%v b (%add row (%mod (%add x 1) 5)))) (%v b (%add row (%mod (%add x 2) 5))))))
             (self (%add i 1))))) 0)
    (%v! a 0 (^ (%v a 0) (%v %rc r)))))

(def %permute!
  (fn (self a b c r)
    (unless (= r 24)
      (do (%theta! a c) (%rest! a b r) (self a b c (%add r 1))))))

; byte I of the padded message: the message, SHA-3's 0x06, zeros, and 0x80
; on the last byte of the last block -- 0x86 where the two meet
(def %byte
  (fn (_ s len total i)
    (match
      ((< i len) (%char->int (%byte-ref s i)))
      ((= i len) (if (= i (%sub total 1)) 134 6))
      ((= i (%sub total 1)) 128)
      (#t 0))))

; the lane at byte BASE of the padded message, little-endian
(def %lane
  (fn (self s len total base k acc)
    (if (< k 0) acc
      (self s len total base (%sub k 1) (| (<< acc 8) (%byte s len total (%add base k)))))))

(def %absorb!
  (fn (self s len total base a i lanes)
    (unless (= i lanes)
      (do (%v! a i (^ (%v a i) (%lane s len total (%add base (<< i 3)) 7 0)))
          (self s len total base a (%add i 1) lanes)))))

; one collect at completion returns the digest's net growth to zero, and
; one every eighth block keeps a long input's garbage bounded (sha512.x)
(def %blocks
  (fn (self s len total rate base k a b c)
    (match
      ((= base total) (do (Heap collect) a))
      (#t
        (do (when (and (> k 0) (= (& k 7) 0)) (Heap collect))
            (%absorb! s len total base a 0 (>> rate 3))
            (%permute! a b c 0)
            (self s len total rate (%add base rate) (%add k 1) a b c))))))

; the state after the whole message, a Vector of the twenty-five lanes: the
; pure-x digest, which the compiled engine stands in for
(def %digest-state
  (fn (_ width s n)
    (def rate (%sub 200 (>> width 2)))
    (def total (%mul (%add (%div n rate) 1) rate))
    (%blocks s n total rate 0 0 (Vector make 25 0) (Vector make 25 0) (Vector make 5 0))))

; the state's first N bytes as lowercase hex
(def %hex
  (fn (_ a n)
    (def byte (fn (_ k) (& (>> (%v a (>> k 3)) (<< (& k 7) 3)) 255)))
    (Str8 join ""
      (List map (fn (_ k) (let ((v (byte k)))
                            (Str8 append (%v %digits (>> v 4)) (%v %digits (& v 15)))))
                (List range 0 n)))))

(def %digits (Vector from-list (lit ("0" "1" "2" "3" "4" "5" "6" "7" "8" "9" "a" "b" "c" "d" "e" "f"))))

; A width is a multiple of 8 between 8 and 792: what leaves a rate of at
; least one lane.  The standard's are 224, 256, 384 and 512.
(def %width-ok?
  (fn (_ w) (and (> w 0) (< w 800) (= (& w 7) 0))))

; --- The compiled engine (JIT), adopted only when it proves out ------
;
; As sha512.x's: an entry of Compiled's, made the first time a build is
; asked for, interpreted by the pure-x digest above, and built only for an
; input of %jit-threshold bytes or more or on (Sha3 jit!).
;
; THE BAR IS THE MEASURED BREAKEVEN, 2026-10-08, arm64: pure-x digests at
; 1.4KB/s (64KB in 47s), the build is 2.9s of CPU, and the engine 215KB/s
; (64KB in 0.30s), so the two cost the same at about 4KB.
(def %entry ())
(def %jit-threshold 4096)

(def %jit-try!
  (fn (_)
    (when (null? %entry)
      (set! %entry
        (Compiled make-on-demand (lit sha3) %digest-state
          (fn (_)
            (import x/codec/sha3-jit)
            ((prim-ref (lit sha3) (lit jit-make)) %rc %digest-state))
          (fn (_ v) ()))))
    ((fn (_ entry)
       (when (eq? (entry state) (lit interpreted)) (entry compile!))
       (eq? (entry state) (lit compiled)))
     %entry)))

(def %state-of
  (fn (_ width s n)
    (when (and (>= n %jit-threshold)
               ((fn (_ entry) (if (null? entry) #t (eq? (entry state) (lit interpreted))))
                %entry))
      (%jit-try!))
    ((fn (_ entry)
       (if (if (null? entry) #f (eq? (entry state) (lit compiled)))
         ((entry compiled) width s n)
         (%digest-state width s n)))
     %entry)))

(def %checked
  (fn (_ width s n)
    (if (%width-ok? width) (%hex (%state-of width s n) (>> width 3))
      (Err raise 'value "Sha3: the width is a multiple of 8 from 8 to 792" width))))

(def-class Sha3 ()
  (static
    (method hex (self (param width INTEGER "Digest width in bits: 224, 256, 384 or 512, or another multiple of 8 below 800")
                      (param s STRING "Bytes to digest (a byte string)"))
      (doc "SHA-3 digest of s at the given width, as lowercase hex (FIPS 202): WIDTH/8 bytes, two hex digits each. A width outside the four standard ones gives the state's first WIDTH/8 bytes with the rate it implies, as busybox's sha3sum -a does. Raises a label 'value for a width that is not a multiple of 8 from 8 to 792."
        (returns STRING "WIDTH/4 hex characters")
        (example "(Sha3 hex 256 \"abc\")" "\"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532\""))
      (%checked width s (Str8 length s)))
    (method hex-n (self (param width INTEGER "Digest width in bits")
                        (param s STRING "Byte region to digest")
                        (param n INTEGER "How many bytes of s to digest"))
      (doc "SHA-3 of the FIRST n BYTES of s, for binary input hex cannot measure (Str8 length stops at the first NUL). THE LENGTH IS YOUR CLAIM AND IS NOT CHECKED: n past the region's allocation reads past the allocation."
        (returns STRING "WIDTH/4 hex characters")
        (example "(Sha3 hex-n 224 \"abc\" 0)" "\"6b4e03423667dbb73b6e15454f0eb1abd4597f9a1b078e3f5b5a6bc7\""))
      (%checked width s n))
    (method jit! (self)
      (doc "Build and adopt the compiled permutation engine (JIT; ARM64 and x86-64 backends) now, if it can prove itself against the pure-x digest. Idempotent. Returns #t when the engine is active, #f when unavailable -- pure-x carries on and results are identical either way. hex also builds it on its own for any single input of 4KB or more."
        (returns BOOL "#t when the compiled engine is active"))
      (%jit-try!))))

(doc (provide x/codec/sha3 Sha3)
  "SHA-3 (FIPS 202): (Sha3 hex WIDTH s) digests a byte string. Pure x-lang, with an optional differentially-verified JIT engine ((Sha3 jit!), or built on its own for an input of 4KB or more).")

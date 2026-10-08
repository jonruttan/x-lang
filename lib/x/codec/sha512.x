; sha512.x -- Sha512: the SHA-512 digest (FIPS 180-4) in pure x-lang.
;
; Ed25519 hashes with it -- a key's expansion, a signature's nonce and
; its challenge -- so an SSH written in x needs it where no C library is
; present, for the host key and for publickey authentication.
;
; The shape is sha1.x's, with one difference the width forces: SHA-512's
; words are 64 bits, and a 64-bit sum overflows the engine's 64-bit int,
; so this digest keeps every word as TWO 32-bit halves, hi and lo, each
; a plain INT on the C bit ops, every addition through the cached int '+
; prim and masked to 32 bits with its carry handed up.  Tower-proof, as
; sha256.x's words are, at the cost of twice the arithmetic.  The padded
; message is addressed virtually, with no padded copy built, and a
; compiled engine in x/codec/sha512-jit -- which has the machine's 64-bit
; words -- is adopted only after it agrees with this digest.  The
; constants are the FIPS hex spellings, each as its two halves.
(module x/codec/sha512)

(import x/type/vector)
; Collection is explicit-trigger-only; the block loop collects as sha1.x's
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

; Hex spellings to ints, each half fitting 32 bits by construction; the
; %cvt narrows a tower integer to the C int the bit ops take, and is the
; identity under bare x-core (sha256.x).
(def %words
  (let ((int-type (Type named INTEGER)))
    (fn (self hexes)
      (if (null? hexes) ()
        (pair (%cvt (%str->number (first hexes) 16) int-type) (self (rest hexes)))))))

; Fractional parts of the cube roots of the first 80 primes (4.2.3), hi
; then lo: K[t] is slots 2t+1 and 2t+2.
(def %k (Vector from-list (%words (lit (
  "428a2f98" "d728ae22"  "71374491" "23ef65cd"  "b5c0fbcf" "ec4d3b2f"  "e9b5dba5" "8189dbbc"
  "3956c25b" "f348b538"  "59f111f1" "b605d019"  "923f82a4" "af194f9b"  "ab1c5ed5" "da6d8118"
  "d807aa98" "a3030242"  "12835b01" "45706fbe"  "243185be" "4ee4b28c"  "550c7dc3" "d5ffb4e2"
  "72be5d74" "f27b896f"  "80deb1fe" "3b1696b1"  "9bdc06a7" "25c71235"  "c19bf174" "cf692694"
  "e49b69c1" "9ef14ad2"  "efbe4786" "384f25e3"  "0fc19dc6" "8b8cd5b5"  "240ca1cc" "77ac9c65"
  "2de92c6f" "592b0275"  "4a7484aa" "6ea6e483"  "5cb0a9dc" "bd41fbd4"  "76f988da" "831153b5"
  "983e5152" "ee66dfab"  "a831c66d" "2db43210"  "b00327c8" "98fb213f"  "bf597fc7" "beef0ee4"
  "c6e00bf3" "3da88fc2"  "d5a79147" "930aa725"  "06ca6351" "e003826f"  "14292967" "0a0e6e70"
  "27b70a85" "46d22ffc"  "2e1b2138" "5c26c926"  "4d2c6dfc" "5ac42aed"  "53380d13" "9d95b3df"
  "650a7354" "8baf63de"  "766a0abb" "3c77b2a8"  "81c2c92e" "47edaee6"  "92722c85" "1482353b"
  "a2bfe8a1" "4cf10364"  "a81a664b" "bc423001"  "c24b8b70" "d0f89791"  "c76c51a3" "0654be30"
  "d192e819" "d6ef5218"  "d6990624" "5565a910"  "f40e3585" "5771202a"  "106aa070" "32bbd1b8"
  "19a4c116" "b8d2d0c8"  "1e376c08" "5141ab53"  "2748774c" "df8eeb99"  "34b0bcb5" "e19b48a8"
  "391c0cb3" "c5c95a63"  "4ed8aa4a" "e3418acb"  "5b9cca4f" "7763e373"  "682e6ff3" "d6b2b8a3"
  "748f82ee" "5defb2fc"  "78a5636f" "43172f60"  "84c87814" "a1f0ab72"  "8cc70208" "1a6439ec"
  "90befffa" "23631e28"  "a4506ceb" "de82bde9"  "bef9a3f7" "b2c67915"  "c67178f2" "e372532b"
  "ca273ece" "ea26619c"  "d186b8c7" "21c0c207"  "eada7dd6" "cde0eb1e"  "f57d4f7f" "ee6ed178"
  "06f067aa" "72176fba"  "0a637dc5" "a2c898a6"  "113f9804" "bef90dae"  "1b710b35" "131c471b"
  "28db77f5" "23047d84"  "32caab7b" "40c72493"  "3c9ebe0a" "15c9bebc"  "431d67c4" "9c100d4c"
  "4cc5d4be" "cb3e42b6"  "597f299c" "fc657e2a"  "5fcb6fab" "3ad6faec"  "6c44198c" "4a475817"
)))))

; The initial hash (5.3.5), hi then lo.
(def %ih (%words (lit (
  "6a09e667" "f3bcc908"  "bb67ae85" "84caa73b"  "3c6ef372" "fe94f82b"  "a54ff53a" "5f1d36f1"
  "510e527f" "ade682d1"  "9b05688c" "2b3e6c1f"  "1f83d9ab" "fb41bd6b"  "5be0cd19" "137e2179"
))))

; --- 64-bit words as (hi, lo) halves --------------------------------
;
; A rotation by n < 32 moves bits across the halves; by n >= 32 it is
; the halves swapped, then rotated by n - 32.  The callers below spell
; the swap by passing the halves the other way round.
(def %rotr-hi (fn (_ hi lo n) (& (| (>> hi n) (<< lo (%sub 32 n))) %mask)))
(def %rotr-lo (fn (_ hi lo n) (& (| (>> lo n) (<< hi (%sub 32 n))) %mask)))
(def %shr-lo (fn (_ hi lo n) (& (| (>> lo n) (<< hi (%sub 32 n))) %mask)))

; Sigma-0 (4.1.3): rotr 28, 34, 39
(def %bs0-hi (fn (_ hi lo) (^ (%rotr-hi hi lo 28) (^ (%rotr-hi lo hi 2) (%rotr-hi lo hi 7)))))
(def %bs0-lo (fn (_ hi lo) (^ (%rotr-lo hi lo 28) (^ (%rotr-lo lo hi 2) (%rotr-lo lo hi 7)))))
; Sigma-1: rotr 14, 18, 41
(def %bs1-hi (fn (_ hi lo) (^ (%rotr-hi hi lo 14) (^ (%rotr-hi hi lo 18) (%rotr-hi lo hi 9)))))
(def %bs1-lo (fn (_ hi lo) (^ (%rotr-lo hi lo 14) (^ (%rotr-lo hi lo 18) (%rotr-lo lo hi 9)))))
; sigma-0: rotr 1, 8, shr 7
(def %ss0-hi (fn (_ hi lo) (^ (%rotr-hi hi lo 1) (^ (%rotr-hi hi lo 8) (>> hi 7)))))
(def %ss0-lo (fn (_ hi lo) (^ (%rotr-lo hi lo 1) (^ (%rotr-lo hi lo 8) (%shr-lo hi lo 7)))))
; sigma-1: rotr 19, 61, shr 6
(def %ss1-hi (fn (_ hi lo) (^ (%rotr-hi hi lo 19) (^ (%rotr-hi lo hi 29) (>> hi 6)))))
(def %ss1-lo (fn (_ hi lo) (^ (%rotr-lo hi lo 19) (^ (%rotr-lo lo hi 29) (%shr-lo hi lo 6)))))

(def %ch (fn (_ x y z) (^ (& x y) (& (& (~ x) %mask) z))))
(def %maj (fn (_ x y z) (^ (& x y) (^ (& x z) (& y z)))))

; Byte i of the padded message: the message; then 0x80; then zeros; then
; the bit length, big-endian in the last 16 bytes (the top eight zero).
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

; W[t] in slots t+1 of the hi and lo vectors (the length rides slot 0):
; the sixteen message words, each a hi half then a lo half.
(def %fill!
  (fn (self s len total base wh wl t)
    (unless (= t 16)
      (do (%oset! wh (%add t 1) (%word s len total (%add base (<< t 3))))
          (%oset! wl (%add t 1) (%word s len total (%add (%add base (<< t 3)) 4)))
          (self s len total base wh wl (%add t 1))))))

; W[t] = sigma1(W[t-2]) + W[t-7] + sigma0(W[t-15]) + W[t-16], the lo halves
; summed first and their carry handed to the hi sum.
(def %extend!
  (fn (self wh wl t)
    (unless (= t 80)
      ; slots fold the +1: W[t-2] is slot t-1, and so on
      (do (def lo (%add (%add (%ss1-lo (%oref wh (%sub t 1)) (%oref wl (%sub t 1))) (%oref wl (%sub t 6)))
                        (%add (%ss0-lo (%oref wh (%sub t 14)) (%oref wl (%sub t 14))) (%oref wl (%sub t 15)))))
          (def hi (%add (%add (%ss1-hi (%oref wh (%sub t 1)) (%oref wl (%sub t 1))) (%oref wh (%sub t 6)))
                        (%add (%ss0-hi (%oref wh (%sub t 14)) (%oref wl (%sub t 14))) (%oref wh (%sub t 15)))))
          (%oset! wl (%add t 1) (& lo %mask))
          (%oset! wh (%add t 1) (& (%add hi (>> lo 32)) %mask))
          (self wh wl (%add t 1))))))

; The eighty rounds (6.4.2), the working variables as sixteen halves.
(def %rounds
  (fn (self wh wl t ah al bh bl ch cl dh dl eh el fh fl gh gl hh hl)
    (if (= t 80) (list ah al bh bl ch cl dh dl eh el fh fl gh gl hh hl)
      (do
        ; T1 = h + Sigma1(e) + Ch(e, f, g) + K[t] + W[t]
        (def t1l (%add (%add (%add hl (%bs1-lo eh el)) (%add (%ch el fl gl) (%oref %k (%add (%mul t 2) 2))))
                       (%oref wl (%add t 1))))
        (def t1h (%add (%add (%add (%add hh (%bs1-hi eh el)) (%add (%ch eh fh gh) (%oref %k (%add (%mul t 2) 1))))
                             (%oref wh (%add t 1)))
                       (>> t1l 32)))
        ; T2 = Sigma0(a) + Maj(a, b, c)
        (def t2l (%add (%bs0-lo ah al) (%maj al bl cl)))
        (def t2h (%add (%add (%bs0-hi ah al) (%maj ah bh ch)) (>> t2l 32)))
        (def el2 (%add dl (& t1l %mask)))
        (def al2 (%add (& t1l %mask) (& t2l %mask)))
        (self wh wl (%add t 1)
          (& (%add (%add t1h t2h) (>> al2 32)) %mask) (& al2 %mask)
          ah al bh bl ch cl
          (& (%add (%add dh t1h) (>> el2 32)) %mask) (& el2 %mask)
          eh el fh fl gh gl)))))

; H + the round's result, half by half with carries.
(def %sum
  (fn (self hs rs)
    (if (null? hs) ()
      (do (def lo (%add (first (rest hs)) (first (rest rs))))
          (pair (& (%add (%add (first hs) (first rs)) (>> lo 32)) %mask)
                (pair (& lo %mask) (self (rest (rest hs)) (rest (rest rs)))))))))

(def %blocks
  (fn (self s len total base wh wl hs)
    (match
      ; one collect at completion returns the digest's net growth to zero,
      ; as sha1.x's does
      ((= base total) (do (Heap collect) hs))
      (#t
        (do (when (and (> base 0) (= (& (>> base 7) 7) 0)) (Heap collect))
            (%fill! s len total base wh wl 0)
            (%extend! wh wl 16)
            (self s len total (%add base 128) wh wl
              (%sum hs
                (%rounds wh wl 0
                  (List ref 0 hs) (List ref 1 hs) (List ref 2 hs) (List ref 3 hs)
                  (List ref 4 hs) (List ref 5 hs) (List ref 6 hs) (List ref 7 hs)
                  (List ref 8 hs) (List ref 9 hs) (List ref 10 hs) (List ref 11 hs)
                  (List ref 12 hs) (List ref 13 hs) (List ref 14 hs) (List ref 15 hs)))))))))

; The pure-x digest: bytes -> the eight H words as sixteen halves, hi
; then lo.  The compiled engine answers the same list, so it is a drop-in
; for this function.  The optional length is the caller's claim, as Sha1
; hex-n's is.
(def %digest-words
  (fn (_ s . n)
    (def len (match ((null? n) (Str8 length s)) (#t (first n))))
    (%blocks s len (<< (%add (>> (%add len 16) 7) 1) 7) 0 (Vector make 80 0) (Vector make 80 0) %ih)))

(def %hex8 (fn (_ wd) (Str pad-left 8 #\0 (%cvt wd %string-type 16))))

(def %hex (fn (_ hs) (Str8 join "" (List map %hex8 hs))))

; --- The compiled engine (JIT), adopted only when it proves out ------
;
; As sha1.x's: an entry of Compiled's, made the first time a build is
; asked for, interpreted by the pure-x digest above, and built only for an
; input of %jit-threshold bytes or more or on (Sha512 jit!).
;
; THE BAR IS THE MEASURED BREAKEVEN, 2026-10-08, arm64, asm cache warm:
; pure-x digests at 1.9KB/s (4000 bytes in 2.1s), the build is 1.4s
; (2.9s on a cold cache), and the engine 790KB/s (64KB in 83ms), so the
; two cost the same at ~2.6KB; 4KB keeps a cold build from losing much.
(def %entry ())
(def %jit-threshold 4096)

(def %jit-try!
  (fn (_)
    (when (null? %entry)
      (set! %entry
        (Compiled make-on-demand (lit sha512) %digest-words
          (fn (_)
            (import x/codec/sha512-jit)
            ((prim-ref (lit sha512) (lit jit-make)) %k %ih %digest-words))
          (fn (_ v) ()))))
    ((fn (_ entry)
       (when (eq? (entry state) (lit interpreted)) (entry compile!))
       (eq? (entry state) (lit compiled)))
     %entry)))

(def %words-of
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

(def-class Sha512 ()
  (static
    (method hex (self (param s STRING "Bytes to digest (a byte string)"))
      (doc "SHA-512 digest of s, as a 128-character lowercase hex string (FIPS 180-4). Computed pure-x, or by the differentially-verified compiled engine once (jit!) has built it -- identical output either way."
        (returns STRING "128 hex characters")
        (example "(Sha512 hex \"abc\")" "\"ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f\""))
      (%hex (%words-of s)))
    (method hex-n (self (param s STRING "Byte region to digest")
                        (param n INTEGER "How many bytes of s to digest"))
      (doc "SHA-512 of the FIRST n BYTES of s, for binary input hex cannot measure (Str8 length stops at the first NUL). THE LENGTH IS YOUR CLAIM AND IS NOT CHECKED: n past the region's allocation reads past the allocation."
        (returns STRING "128 hex characters")
        (example "(Sha512 hex-n \"abc\" 0)" "\"cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e\""))
      (%hex (%words-of s n)))
    (method jit! (self)
      (doc "Build and adopt the compiled digest engine (JIT; ARM64 and x86-64 backends) now, if it can prove itself against the pure-x digest. Idempotent. Returns #t when the engine is active, #f when unavailable -- pure-x carries on and results are identical either way. hex also builds it on its own for any single input of 4KB or more."
        (returns BOOL "#t when the compiled engine is active"))
      (%jit-try!))))

(doc (provide x/codec/sha512 Sha512)
  "SHA-512 (FIPS 180-4): (Sha512 hex s) digests a byte string. Pure x-lang, with an optional differentially-verified JIT engine ((Sha512 jit!), or built on its own for an input of 4KB or more).")

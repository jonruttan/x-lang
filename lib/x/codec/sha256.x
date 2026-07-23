; sha256.x -- Sha256: the SHA-256 digest (FIPS 180-4) in pure x-lang.
;
; The pin lockfile's trust anchor (GH #115 phase 4).  Pure INT on the C
; bit ops (& | ^ ~ << >> are int-only, tower-untouched); additions go
; through the cached int '+ prim and mask to 32 bits, so the digest is
; tower-proof (ambient + becomes the tower dispatcher once x/num loads
; -- the TOWER-DIVISION trap class; there is no division here at all,
; block math rides shifts).  Deliberately x-lang and slower than C:
; this is tooling, and NO NEW C is the rule.
;
; K/H are the FIPS hex spellings parsed at load (%str->number, radix 16
; -- the post-#108 boot spelling, as codec/json.x) -- transcription is
; checkable against the standard by eye, and the (example) vectors on
; `hex` are the executable proof.
(import x/type/vector)
; Collection is explicit-trigger-only: without the periodic collect in
; the block loop below, digesting an amalgam-sized input allocates
; gigabytes and dies on small machines (the release runner did).  The
; live set at a block boundary is tiny, so the collects stay cheap.
(import x/sys/gc)

; ALL arithmetic rides the cached int prims: under the tower, bare
; +/-/* return tower numbers the C bit ops reject (>> errors) -- the
; hash.x precedent, met here via the doctest gate (which runs tower-up).
(def %sha+ (prim-ref 'int '+))
(def %sha- (prim-ref 'int '-))
(def %sha* (prim-ref 'int '*))
; Raw slot access for the fixed 64-slot schedule vectors: the class
; dispatch behind (Vector ref)/(Vector set!) costs hundreds of heap
; objects PER CALL, and this loop makes millions of calls -- it was the
; whole of #123's 2GB peak (~42M objects between collects, all dispatch
; scaffolding; the GC itself reclaimed perfectly).  Indices here are
; structurally in range (0..63 against 64-slot vectors, t>=16 for the
; backward references), the same trust model as unchecked first/rest;
; slot = index + 1, the length rides slot 0.
(def %sha-oref (prim-ref (lit obj) (lit ref)))
(def %sha-oset! (prim-ref (lit obj) (lit set!)))
(def %sha-mask 4294967295)

(def %sha-words
  (fn (_ hexes)
    ; the %cvt narrows: under the tower %str->number returns a TOWER
    ; integer (bignum-capable parsing), which the C bit ops reject --
    ; %int coercion is identity under bare x-core and a narrowing
    ; conversion tower-up; every value fits 32 bits by construction
    ((fn (self lst)
       (match
         ((null? lst) ())
         (#t (pair (%cvt (%str->number (first lst) 16) %int) (self (rest lst))))))
     hexes)))

; Fractional parts of the cube roots of the first 64 primes (FIPS 180-4 4.2.2).
(def %sha-k (Vector from-list (%sha-words (lit (
  "428a2f98" "71374491" "b5c0fbcf" "e9b5dba5" "3956c25b" "59f111f1" "923f82a4" "ab1c5ed5"
  "d807aa98" "12835b01" "243185be" "550c7dc3" "72be5d74" "80deb1fe" "9bdc06a7" "c19bf174"
  "e49b69c1" "efbe4786" "0fc19dc6" "240ca1cc" "2de92c6f" "4a7484aa" "5cb0a9dc" "76f988da"
  "983e5152" "a831c66d" "b00327c8" "bf597fc7" "c6e00bf3" "d5a79147" "06ca6351" "14292967"
  "27b70a85" "2e1b2138" "4d2c6dfc" "53380d13" "650a7354" "766a0abb" "81c2c92e" "92722c85"
  "a2bfe8a1" "a81a664b" "c24b8b70" "c76c51a3" "d192e819" "d6990624" "f40e3585" "106aa070"
  "19a4c116" "1e376c08" "2748774c" "34b0bcb5" "391c0cb3" "4ed8aa4a" "5b9cca4f" "682e6ff3"
  "748f82ee" "78a5636f" "84c87814" "8cc70208" "90befffa" "a4506ceb" "bef9a3f7" "c67178f2")))))

; Fractional parts of the square roots of the first 8 primes (5.3.3).
(def %sha-ih (%sha-words (lit (
  "6a09e667" "bb67ae85" "3c6ef372" "a54ff53a" "510e527f" "9b05688c" "1f83d9ab" "5be0cd19"))))

; The sigmas open-code their rotates -- rotr(x,n) = (>>n | <<32-n)&mask
; -- because a %sha-rotr helper costs an interpreted call, and the four
; sigmas would make twelve of them PER ROUND (#123: the digest's cost
; is call scaffolding, not arithmetic).  Each pair below reads n/32-n.
(def %sha-bsig0
  (fn (_ x)
    (^ (& (| (>> x 2) (<< x 30)) %sha-mask)
       (^ (& (| (>> x 13) (<< x 19)) %sha-mask)
          (& (| (>> x 22) (<< x 10)) %sha-mask)))))
(def %sha-bsig1
  (fn (_ x)
    (^ (& (| (>> x 6) (<< x 26)) %sha-mask)
       (^ (& (| (>> x 11) (<< x 21)) %sha-mask)
          (& (| (>> x 25) (<< x 7)) %sha-mask)))))
(def %sha-ssig0
  (fn (_ x)
    (^ (& (| (>> x 7) (<< x 25)) %sha-mask)
       (^ (& (| (>> x 18) (<< x 14)) %sha-mask)
          (>> x 3)))))
(def %sha-ssig1
  (fn (_ x)
    (^ (& (| (>> x 17) (<< x 15)) %sha-mask)
       (^ (& (| (>> x 19) (<< x 13)) %sha-mask)
          (>> x 10)))))
(def %sha-ch  (fn (_ x y z) (^ (& x y) (& (& (~ x) %sha-mask) z))))
(def %sha-maj (fn (_ x y z) (^ (& x y) (^ (& x z) (& y z)))))

(def %sha+4 (fn (_ a b c d) (%sha+ (%sha+ a b) (%sha+ c d))))
(def %sha+5 (fn (_ a b c d e) (%sha+ (%sha+4 a b c d) e)))

; The padded message, addressed virtually -- no padded copy is built.
; Byte i is: the message; then 0x80; then zeros; then the bit length,
; big-endian in the last 8 bytes.
(def %sha-byte
  (fn (_ s len total i)
    (match
      ((< i len) (%cvt (%str-ref s i) %int))
      ((= i len) 128)
      ((< i (%sha- total 8)) 0)
      (#t (& (>> (%sha* len 8) (<< (%sha- (%sha- total 1) i) 3)) 255)))))

(def %sha-word
  (fn (_ s len total base)
    (| (<< (%sha-byte s len total base) 24)
       (| (<< (%sha-byte s len total (%sha+ base 1)) 16)
          (| (<< (%sha-byte s len total (%sha+ base 2)) 8)
             (%sha-byte s len total (%sha+ base 3)))))))

(def %sha-fill-w!
  (fn (self s len total base w t)
    (match
      ((= t 16) ())
      (#t
        (do (%sha-oset! w (%sha+ t 1) (%sha-word s len total (%sha+ base (<< t 2))))
            (self s len total base w (%sha+ t 1)))))))

(def %sha-extend-w!
  (fn (self w t)
    (match
      ((= t 64) ())
      (#t
        ; slots fold the +1: (t-2)+1 = t-1, and so on
        (do (%sha-oset! w (%sha+ t 1)
              (& (%sha+4 (%sha-ssig1 (%sha-oref w (%sha- t 1)))
                         (%sha-oref w (%sha- t 6))
                         (%sha-ssig0 (%sha-oref w (%sha- t 14)))
                         (%sha-oref w (%sha- t 15)))
                 %sha-mask))
            (self w (%sha+ t 1)))))))

; The 64-round compression; sums stay below 2^35, masked where stored.
(def %sha-rounds
  (fn (self w t a b c d e f g h)
    (match
      ((= t 64) (list a b c d e f g h))
      (#t
        (let ((t1 (%sha+5 h (%sha-bsig1 e) (%sha-ch e f g)
                          (%sha-oref %sha-k (%sha+ t 1)) (%sha-oref w (%sha+ t 1))))
              (t2 (%sha+ (%sha-bsig0 a) (%sha-maj a b c))))
          (self w (%sha+ t 1)
            (& (%sha+ t1 t2) %sha-mask) a b c
            (& (%sha+ d t1) %sha-mask) e f g))))))

(def %sha-blocks
  (fn (self s len total base w h0 h1 h2 h3 h4 h5 h6 h7)
    (match
      ((= base total) (list h0 h1 h2 h3 h4 h5 h6 h7))
      (#t
        (do (match
              ; every 8th block (512B): bound the between-collect churn
              ; (~150MB at the measured per-block cost); tiny inputs
              ; (the vectors) never pay a collect, and a collect at the
              ; small live set costs ~ms
              ((and (> base 0) (= (& (>> base 6) 7) 0)) (Heap collect))
              (#t ()))
            (%sha-fill-w! s len total base w 0)
            (%sha-extend-w! w 16)
            (let ((r (%sha-rounds w 0 h0 h1 h2 h3 h4 h5 h6 h7)))
              (self s len total (%sha+ base 64) w
                (& (%sha+ h0 (first r)) %sha-mask)
                (& (%sha+ h1 (first (rest r))) %sha-mask)
                (& (%sha+ h2 (first (rest (rest r)))) %sha-mask)
                (& (%sha+ h3 (first (rest (rest (rest r))))) %sha-mask)
                (& (%sha+ h4 (first (rest (rest (rest (rest r)))))) %sha-mask)
                (& (%sha+ h5 (first (rest (rest (rest (rest (rest r))))))) %sha-mask)
                (& (%sha+ h6 (first (rest (rest (rest (rest (rest (rest r)))))))) %sha-mask)
                (& (%sha+ h7 (first (rest (rest (rest (rest (rest (rest (rest r))))))))) %sha-mask))))))))

(def %sha-hex8
  (fn (_ wd) (Str pad-left 8 #\0 (%cvt wd %string 16))))

(def %sha-hex-list
  (fn (self hs)
    (match
      ((null? hs) "")
      (#t (Str8 append (%sha-hex8 (first hs)) (self (rest hs)))))))

(def-class Sha256 ()
  (static
    (method hex (self (param s STRING "Bytes to digest (a byte string)"))
      (doc "SHA-256 digest of s, as a 64-character lowercase hex string. Pure x-lang (FIPS 180-4); the executable vectors below are the standard's."
        (returns STRING "64 hex characters")
        (example "(Sha256 hex \"\")" "\"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"")
        (example "(Sha256 hex \"abc\")" "\"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad\""))
      (def %len (Str8 length s))
      ; padded length: L+1+k+8 rounded to a 64-byte block -- via shifts,
      ; no division (the tower / trap has nothing to bite)
      (def %total (<< (%sha+ (>> (%sha+ %len 8) 6) 1) 6))
      (%sha-hex-list
        (%sha-blocks s %len %total 0 (Vector make 64 0)
          (first %sha-ih)
          (first (rest %sha-ih))
          (first (rest (rest %sha-ih)))
          (first (rest (rest (rest %sha-ih))))
          (first (rest (rest (rest (rest %sha-ih)))))
          (first (rest (rest (rest (rest (rest %sha-ih))))))
          (first (rest (rest (rest (rest (rest (rest %sha-ih)))))))
          (first (rest (rest (rest (rest (rest (rest (rest %sha-ih)))))))))))))

(doc (provide x/codec/sha256 Sha256)
  "SHA-256 (FIPS 180-4) in pure x-lang: (Sha256 hex s) digests a byte string.")

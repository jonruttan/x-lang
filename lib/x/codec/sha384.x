; sha384.x -- Sha384: the SHA-384 digest (FIPS 180-4) in pure x-lang.
;
; A certificate signed ecdsa-with-SHA384 is checked over this digest, and
; TLS 1.3's SHA-384 cipher suites run their key schedule on it.  SHA-384
; is SHA-512's compression from other initial words, cut to the first six
; of the eight; x/codec/sha512 holds both sets of words and the one
; digest, so the compiled engine is the same engine, proven on both.
(module x/codec/sha384)

(import x/codec/sha512 sha384-words sha512-jit-try!)

(def %cvt (prim-ref (lit convert) (lit to)))
(def %string-type (Type named STRING))

(def %hex8 (fn (_ wd) (Str pad-left 8 #\0 (%cvt wd %string-type 16))))

; The first twelve halves of the sixteen: six 64-bit words.
(def %hex
  (fn (_ hs)
    (Str8 join "" (List map %hex8 (List take 12 hs)))))

(def-class Sha384 ()
  (static
    (method hex (self (param s STRING "Bytes to digest (a byte string)"))
      (doc "SHA-384 digest of s, as a 96-character lowercase hex string (FIPS 180-4). Computed pure-x, or by SHA-512's differentially-verified compiled engine once (jit!) has built it -- identical output either way."
        (returns STRING "96 hex characters")
        (example "(Sha384 hex \"abc\")" "\"cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7\""))
      (%hex (sha384-words s (Str8 length s))))
    (method hex-n (self (param s STRING "Byte region to digest")
                        (param n INTEGER "How many bytes of s to digest"))
      (doc "SHA-384 of the FIRST n BYTES of s, for binary input hex cannot measure (Str8 length stops at the first NUL). THE LENGTH IS YOUR CLAIM AND IS NOT CHECKED: n past the region's allocation reads past the allocation."
        (returns STRING "96 hex characters")
        (example "(Sha384 hex-n \"abc\" 0)" "\"38b060a751ac96384cd9327eb1b1e36a21fdb71114be07434c0cc7bf63f6e1da274edebfe76f65fbd51ad2f14898b95b\""))
      (%hex (sha384-words s n)))
    (method jit! (self)
      (doc "Build and adopt the compiled digest engine (SHA-512's, which SHA-384 shares) now, if it can prove itself against the pure-x digest. Idempotent. Returns #t when the engine is active, #f when unavailable -- pure-x carries on and results are identical either way. hex also builds it on its own for any single input of 4KB or more."
        (returns BOOL "#t when the compiled engine is active"))
      (sha512-jit-try!))))

(doc (provide x/codec/sha384 Sha384)
  "SHA-384 (FIPS 180-4): (Sha384 hex s) digests a byte string. Pure x-lang, on SHA-512's digest and its optional differentially-verified JIT engine.")

; hash.x -- Hash: FNV-1a string hashing as the Hash class.
;
; Loaded after x-core.x in every context (the xenon/x-base/radon dialects and the
; ext/hash.spec test lib all (include "lib/x-core.x") first), so def-class is
; available when this loads.

(module x/type/hash)

; The base type handles, from their public door, fetched once at load.
(def %string (Type named STRING))

; The binary integer primitives, fetched from the catalogue: the C operators as
; they were before core/arithmetic.x wrapped the bare names.
(import x/core/doors char->int int* int+ int- int< int<< int= int& int| str-append str-byte-len str-byte-ref)
(import x/type/class)
; Fetch the string prims from the catalogue (ns `str` is de-registered, R5).

; Fetch the conversion dispatcher from the catalogue (registered by sys/convert.x).
(def %cvt (prim-ref 'convert 'to))

; Message bytes ride (str byte-len)/(str byte-ref) + (char ->int), NOT
; the generic converter: %cvt is a full catalogue dispatch per character,
; and this loop is the inner loop of every Dict get/set! with a symbol
; or string key (#334).  sha256.x measured this exact substitution on
; its own byte loop at ~142us -> ~11us per byte.  Values are unchanged
; -- both spellings yield the byte -- and the ->hex doctest below pins
; that.

(import x/type/str)

; FNV-1a over the word: the 64-bit constants on an 8-byte word, the 32-bit
; ones on a 4-byte word.  The 64-bit offset basis 0xCBF29CE484222325 and
; prime 2^40 + 435 are built from parts a 4-byte reader can hold.
(def %narrow (int< %word-size 8))
(def %fnv-offset
  (if %narrow 0x811C9DC5 (int| (int<< 0xCBF29CE4 32) 0x84222325)))
(def %fnv-prime (if %narrow 16777619 (int+ (int<< 1 40) 435)))

; ->hex prints the word as two halves, each unsigned in its own half-word
(def %half-bits (int* 4 %word-size))
(def %half-mask (int- (int<< 1 %half-bits) 1))

; The loop over S's bytes from I, LEN its length, H the hash so far.  A
; module-level closure on integer doors only, so compile-fn! can rewrite it
; in place: loading x/tool/fn-compile compiles it where the engine has a
; JIT (the tower dialects load it at boot), and elsewhere it runs as written.  The xor is spelled (a|b)-(a&b),
; which compile-fn! carries; it equals (^ a b) for every pair of words.
(def %fnv-go
  (fn (self s len i h)
    (if (int= i len) h
      (self s len (int+ i 1)
        (int* (do (def b (char->int (str-byte-ref s i)))
                  (int- (int| h b) (int& h b)))
              %fnv-prime)))))

(def-class Hash ()
  (static
    (method fnv-1a (self (param s STRING "String to hash"))
      (doc "Hash a string to a word using the FNV-1a algorithm: FNV-1a 64 on an 8-byte word, FNV-1a 32 on a 4-byte word."
        (returns INTEGER "The FNV-1a hash, the word's width")
        (example "(= (Hash fnv-1a \"a\") (Hash fnv-1a \"a\"))" "#t")
        (example "(str=? (Hash ->hex (Hash fnv-1a \"\")) (if (< %word-size 8) \"811c9dc5\" \"cbf29ce484222325\"))" "#t"))
      (%fnv-go s (str-byte-len s) 0 %fnv-offset))
    (method ->hex (self (param n INTEGER "A word, such as a hash"))
      (doc "Convert a word to its unsigned hex string, two digits a byte: 16 on an 8-byte word, 8 on a 4-byte word."
        (returns STRING "The word's bits in hexadecimal")
        (example "(str=? (Hash ->hex 255) (if (< %word-size 8) \"000000ff\" \"00000000000000ff\"))" "#t")
        (example "(= (Str8 length (Hash ->hex -1)) (* 2 %word-size))" "#t"))
      (def %lo (& n %half-mask))
      (def %hi (& (>> n %half-bits) %half-mask))
      (str-append (Str pad-left %word-size #\0 (%cvt %hi %string 16))
                  (Str pad-left %word-size #\0 (%cvt %lo %string 16))))))

(doc (provide x/type/hash Hash)
  (example "(str=? (Hash ->hex (Hash fnv-1a \"hello\")) (if (< %word-size 8) \"4f9f2cab\" \"a430d84680aabd0b\"))" "#t")
  "FNV-1a string hashing, homed on the Hash class.")

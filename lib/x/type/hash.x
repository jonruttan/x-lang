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
(import x/core/doors char->int int* int+ int- int= int& int| str-append str-byte-len str-byte-ref)
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

; FNV-1a 64-bit constants. Offset basis 14695981039346656037 (unsigned) =
; -3750763034362895579 (signed); prime 1099511628211 fits in signed 64-bit.
(def %fnv-offset -3750763034362895579)
(def %fnv-prime 1099511628211)

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
      (doc "Hash a string to a 64-bit integer using the FNV-1a algorithm."
        (returns INTEGER "64-bit FNV-1a hash value"))
      (%fnv-go s (str-byte-len s) 0 %fnv-offset))
    (method ->hex (self (param n INTEGER "64-bit signed hash value"))
      (doc "Convert a 64-bit signed integer to a 16-character unsigned hex string."
        (returns STRING "16-character hexadecimal string"))
      (def %lo (& n 4294967295))
      (def %hi (& (>> n 32) 4294967295))
      (str-append (Str pad-left 8 #\0 (%cvt %hi %string 16))
                  (Str pad-left 8 #\0 (%cvt %lo %string 16))))))

(doc (provide x/type/hash Hash)
  (example "(Hash ->hex (Hash fnv-1a \"hello\"))" "\"a430d84680aabd0b\"")
  "FNV-1a string hashing, homed on the Hash class.")

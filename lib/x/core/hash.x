; hash.x -- Hash: FNV-1a string hashing as the Hash class.
;
; Loaded after x-core.x in every context (the x-and/x-base/x-or dialects and the
; ext/hash.spec test lib all (include "lib/x-core.x") first), so def-class is
; available when this loads.

(import x/type/object)
; Fetch the string prims from the catalog (ns `str` is de-registered, R5).
(def %str-append (prim-ref 'str 'append))

; Fetch the conversion dispatcher from the catalog (registered by sys/convert.x).
(def %cvt (prim-ref 'convert 'to))

(import x/type/str)

; FNV-1a 64-bit constants. Offset basis 14695981039346656037 (unsigned) =
; -3750763034362895579 (signed); prime 1099511628211 fits in signed 64-bit.
(def %fnv-offset -3750763034362895579)
(def %fnv-prime 1099511628211)

(def-class Hash ()
  (static
    (method fnv-1a (self (param s STRING "String to hash"))
      (doc "Hash a string to a 64-bit integer using the FNV-1a algorithm."
        (returns INT "64-bit FNV-1a hash value"))
      (def %len (str-length s))
      (def %go
        (fn (self i h)
          (if (%int= i %len) h
            (self (%int+ i 1)
              (%int* (^ h (%cvt (str-ref s i) %int)) %fnv-prime)))))
      (%go 0 %fnv-offset))
    (method ->hex (self (param n INT "64-bit signed hash value"))
      (doc "Convert a 64-bit signed integer to a 16-character unsigned hex string."
        (returns STRING "16-character hexadecimal string"))
      (def %lo (& n 4294967295))
      (def %hi (& (>> n 32) 4294967295))
      (%str-append (Str pad-left 8 #\0 (%cvt %hi %string 16))
                  (Str pad-left 8 #\0 (%cvt %lo %string 16))))))

(doc (provide x/core/hash Hash)
  (example "(Hash ->hex (Hash fnv-1a \"hello\"))" "\"a430d84680aabd0b\"")
  "FNV-1a string hashing, homed on the Hash class.")

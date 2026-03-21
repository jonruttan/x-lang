; hash.x -- FNV-1a hash function
(import x/string)
;
; FNV-1a 64-bit hash operating on strings.
; Returns an integer suitable for use as a cache key.

; FNV-1a constants (64-bit, signed representation)
; Offset basis: 14695981039346656037 unsigned = -3750763034362895579 signed
; Prime: 1099511628211 (fits in signed 64-bit)
(def %fnv-offset -3750763034362895579)
(def %fnv-prime 1099511628211)

(note "Hashing")

; fnv-1a: hash a string to a 64-bit integer
(doc (def fnv-1a
  (fn ((param s STRING "String to hash"))
    (def %len (string-length s))
    (def %go
      (fn (i h)
        (if (%int= i %len) h
          (%go (%int+ i 1)
            (%int* (^ h (convert (string-ref s i) %int))
               %fnv-prime)))))
    (%go 0 %fnv-offset)))
  (returns INTEGER "64-bit FNV-1a hash value")
  "Hash a string to a 64-bit integer using the FNV-1a algorithm.")

; hash->hex: convert 64-bit signed integer to 16-char unsigned hex
; Splits into high and low 32-bit halves, each rendered as 8-char hex.
(doc (def hash->hex
  (fn ((param n INTEGER "64-bit signed hash value"))
    (def %lo (& n 4294967295))
    (def %hi (& (>> n 32) 4294967295))
    (string-append (string-pad-left (convert %hi %string 16) 8 ("0" 0))
                   (string-pad-left (convert %lo %string 16) 8 ("0" 0)))))
  (returns STRING "16-character hexadecimal string")
  "Convert a 64-bit signed integer to a 16-character unsigned hex string.")

(doc (provide x/hash fnv-1a hash->hex)
  (example "(hash->hex (fnv-1a \"hello\"))" "a430d84680aabd0b")
  "FNV-1a hash function for strings.")

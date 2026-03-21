; hash.x -- FNV-1a hash function
;
; Provides: fnv-1a, hash->hex
;
; FNV-1a 64-bit hash operating on strings.
; Returns an integer suitable for use as a cache key.

; FNV-1a constants (64-bit, signed representation)
; Offset basis: 14695981039346656037 unsigned = -3750763034362895579 signed
; Prime: 1099511628211 (fits in signed 64-bit)
(def %fnv-offset -3750763034362895579)
(def %fnv-prime 1099511628211)

; fnv-1a: hash a string to a 64-bit integer
(def fnv-1a
  (fn (s)
    (def %len (string-length s))
    (def %go
      (fn (i h)
        (if (= i %len) h
          (%go (+ i 1)
            (* (^ h (convert (string-ref s i) %int))
               %fnv-prime)))))
    (%go 0 %fnv-offset)))

; %hex-pad: left-pad hex string to n chars with zeros
(def %hex-pad
  (fn (s n)
    (if (>= (string-length s) n) s
      (%hex-pad (string-append "0" s) n))))

; hash->hex: convert 64-bit signed integer to 16-char unsigned hex
; Splits into high and low 32-bit halves, each rendered as 8-char hex.
(def hash->hex
  (fn (n)
    (def %lo (& n 4294967295))
    (def %hi (& (>> n 32) 4294967295))
    (string-append (%hex-pad (convert %hi %string 16) 8)
                   (%hex-pad (convert %lo %string 16) 8))))

(provide x/hash fnv-1a hash->hex)

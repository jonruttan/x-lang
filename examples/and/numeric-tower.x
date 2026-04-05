; numeric-tower.x -- Numeric tower examples
;
; Usage:
;   sh x.sh -l x-and -f examples/and/numeric-tower.x

; Arbitrary-precision integers (bignum)
(display "2^100 = ")
(display (expt 2 100))
(newline)

; Exact rationals
(display "1/3 + 1/6 = ")
(display (+ 1/3 1/6))
(newline)

; Floating-point
(display "pi ~= ")
(display (* 4.0 (atan 1.0)))
(newline)

; Complex numbers
(display "(1+2i) * (3+4i) = ")
(display (* 1+2i 3+4i))
(newline)

; Automatic promotion: integer -> bignum when needed
(display "factorial(50) = ")
(def factorial
  (fn (n)
    (def go (fn (n acc) (if (<= n 1) acc (go (- n 1) (* acc n)))))
    (go n 1)))
(display (factorial 50))
(newline)

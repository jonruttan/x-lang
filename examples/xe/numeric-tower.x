; numeric-tower.x -- Numeric tower examples
;
; Usage:
;   sh x.sh -l xe -f examples/xe/numeric-tower.x

; Arbitrary-precision integers (bignum)
(display "2^100 = ")
(display (Num expt 2 100))
(newline)

; Exact rationals
(display "1/3 + 1/6 = ")
(display (+ 1/3 1/6))
(newline)

; Floating-point
(display "pi ~= ")
(display (* 4.0 (Float atan 1.0)))
(newline)

; Complex numbers
(display "(1+2i) * (3+4i) = ")
(display (* 1+2i 3+4i))
(newline)

; Automatic promotion: integer -> bignum when the result overflows
(display "factorial(50) = ")
(display (let go ((n 50) (acc 1)) (if (<= n 1) acc (go (- n 1) (* acc n)))))
(newline)

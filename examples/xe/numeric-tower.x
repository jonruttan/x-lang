; numeric-tower.x -- Numeric tower examples
;
; Usage:
;   sh x.sh -l xe -f examples/xe/numeric-tower.x

; Arbitrary-precision integers (bignum)
(display "2^100 = " (Num expt 2 100) "\n" "1/3 + 1/6 = " (+ 1/3 1/6) "\n"
         "pi ~= " (* 4.0 (Float atan 1.0)) "\n" "(1+2i) * (3+4i) = "
         (* 1+2i 3+4i) "\n" "factorial(50) = "
         (let go ((n 50) (acc 1)) (if (<= n 1) acc (go (- n 1) (* acc n))))
         "\n")

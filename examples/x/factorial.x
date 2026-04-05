; factorial.x -- Factorial with tail-call optimization
;
; Usage:
;   sh x.sh -f examples/x/factorial.x

; Naive recursive factorial
(def factorial
  (fn (n)
    (if (<= n 1) 1 (* n (factorial (- n 1))))))

; Tail-recursive factorial using an accumulator
(def factorial-tc
  (fn (n)
    (def go
      (fn (n acc)
        (if (<= n 1) acc (go (- n 1) (* acc n)))))
    (go n 1)))

(display "factorial(10) = ")
(display (factorial 10))
(newline)

(display "factorial-tc(10) = ")
(display (factorial-tc 10))
(newline)

; TCO means this won't overflow the stack
(display "factorial-tc(1000) = ")
(display (factorial-tc 1000))
(newline)

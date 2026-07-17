; fibonacci.x -- Fibonacci sequence
;
; Usage:
;   sh x.sh -f examples/x/fibonacci.x

; Recursion via the implicit self argument (every closure gets itself
; as argument 0).
(def fib
  (fn (self n)
    (if (<= n 1)
      n
      (+ (self (- n 1)) (self (- n 2))))))

; Print the first 20 Fibonacci numbers
(def print-fibs
  (fn (self i n)
    (if (> i n)
      ()
      (do
        (display "fib(")
        (display i)
        (display ") = ")
        (display (fib i))
        (newline)
        (self (+ i 1) n)))))

(print-fibs 0 19)

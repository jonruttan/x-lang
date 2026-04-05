; fibonacci.x -- Fibonacci sequence
;
; Usage:
;   sh x.sh -f examples/x/fibonacci.x

(def fib
  (fn (n)
    (if (<= n 1)
      n
      (+ (fib (- n 1)) (fib (- n 2))))))

; Print the first 20 Fibonacci numbers
(def print-fibs
  (fn (i n)
    (if (> i n)
      ()
      (do
        (display "fib(")
        (display i)
        (display ") = ")
        (display (fib i))
        (newline)
        (print-fibs (+ i 1) n)))))

(print-fibs 0 19)

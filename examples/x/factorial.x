; factorial.x -- Factorial two ways: self-recursion and a tail-recursive loop
;
; Usage:
;   sh x.sh -f examples/x/factorial.x

; Every closure receives itself as implicit argument 0. Name it `self`
; and recursion needs no global name.
(def factorial
  (fn (self n)
    (if (<= n 1) 1 (* n (self (- n 1))))))

; Tail-recursive with an accumulator via named let: constant stack space.
(def factorial-tc
  (fn (_ n)
    (let go ((n n) (acc 1))
      (if (<= n 1) acc (go (- n 1) (* acc n))))))

(display "factorial(10)    = " (factorial 10) "\n" "factorial-tc(20) = "
         (factorial-tc 20) "\n" "count(1000000)   = "
         (let go ((n 1000000)) (if (= n 0) 'done (go (- n 1)))) "\n")

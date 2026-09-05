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

; A hundred thousand, not a million: the loop is here to show constant STACK,
; and the heap is a different story.  Collection is explicit-trigger-only, so
; every iteration's ~111 objects stay until a collect -- ~29 bytes each on
; arm64, ~64 on x86-64 -- and a million iterations peaked at 7.1GB on the
; linux CI runner, more than the box.  A tenth of that still proves the point.
(display "factorial(10)    = " (factorial 10) "\n" "factorial-tc(20) = "
         (factorial-tc 20) "\n" "count(100000)    = "
         (let go ((n 100000)) (if (= n 0) 'done (go (- n 1)))) "\n")

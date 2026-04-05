; lists.x -- List processing examples
;
; Usage:
;   sh x.sh -f examples/x/lists.x

; Map: square every element
(display "squares: ")
(write (map (fn (_ x) (* x x)) (list 1 2 3 4 5)))
(newline)

; Filter: keep only even numbers
(display "evens:   ")
(write (filter even? (list 1 2 3 4 5 6 7 8 9 10)))
(newline)

; Fold: sum a list
(display "sum:     ")
(display (fold + 0 (list 1 2 3 4 5)))
(newline)

; Sort
(display "sorted:  ")
(write (sort < (list 5 3 8 1 9 2 7 4 6)))
(newline)

; Compose: build a pipeline
(def add1 (fn (_ x) (+ x 1)))
(def double (fn (_ x) (* x 2)))
(def add1-then-double (compose double add1))
(display "compose: ")
(display (add1-then-double 5))
(newline)

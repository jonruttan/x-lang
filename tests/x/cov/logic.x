; Coverage tests for lib/x/logic.x
; Exercises all branches in boolean?, default-to, until, equal?

; boolean? -- both short-circuit paths of (or (eq? x #t) (eq? x #f))
(boolean? #t)        ; first short-circuit: (eq? x #t) = #t
(boolean? #f)        ; second short-circuit: (eq? x #f) = #t
(boolean? 42)        ; both fail

; default-to -- both branches
(default-to 0 42)    ; non-nil → return x
(default-to 0 ())    ; nil → return d

; until -- both branches
(until (fn (x) (> x 10)) inc 1)   ; recurse path
(until (fn (x) #t) inc 1)         ; immediate return (pred already true)

; equal? -- all 3 match clauses
(equal? 5 5)         ; numbers: (= a b)
(equal? "hi" "hi")   ; strings: (string=? a b)
(equal? (lit a) (lit a))  ; fallthrough: (eq? a b)

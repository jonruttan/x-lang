; Coverage tests for lib/x/math.x
; Exercises all branches

; abs -- both branches
(abs 5)    ; positive: (< n 0) = false → return n
(abs -5)   ; negative: (< n 0) = true → (- 0 n)

; negate
(negate 5)
(negate -3)

; min -- both branches
(min 3 7)  ; a < b → a
(min 7 3)  ; a >= b → b

; max -- both branches
(max 3 7)  ; a > b is false → b
(max 7 3)  ; a > b is true → a

; clamp (exercises both min and max)
(clamp 0 10 -5)  ; below min
(clamp 0 10 15)  ; above max
(clamp 0 10 5)   ; in range

; min-by / max-by
(min-by abs 3 -5)
(max-by abs 3 -5)

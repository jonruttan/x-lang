; math.x -- Logo math functions and LFSR random number generator
(import x/logo/state)
(import x/logo/types)
(import x/logo/expr)
(import x/num/float)

; ============================================================
; Degree/radian conversion
; ============================================================

(def %deg->rad
  (fn (_ deg) (Float / (Float * (%as-float deg) %pi) (Float exact->inexact 180))))

(def %rad->deg
  (fn (_ rad) (Float / (Float * rad (Float exact->inexact 180)) %pi)))

; ============================================================
; LFSR random number generator (pure x-lang, no C dependency)
; ============================================================

(def %lfsr-state 48271)

(def %lfsr-next
  (fn ()
    ; 32-bit xorshift
    (set! %lfsr-state (^ %lfsr-state (<< %lfsr-state 13)))
    (set! %lfsr-state (^ %lfsr-state (>> %lfsr-state 17)))
    (set! %lfsr-state (^ %lfsr-state (<< %lfsr-state 5)))
    (set! %lfsr-state (& %lfsr-state 2147483647))
    %lfsr-state))

(def %logo-rand
  (fn (_ low high)
    (def range (+ (- high low) 1))
    (+ low (% (%lfsr-next) range))))

; ============================================================
; Register math functions
; ============================================================

(set! %logo-functions
  (list
    ; 1-arg math functions
    (list "SQRT"      1 (fn (_ x) (Float sqrt (%as-float x))))
    (list "ABS"       1 (fn (_ x) (if (Float float? x) (Float abs x) (if (< x 0) (- x) x))))
    (list "SIN"       1 (fn (_ x) (Float sin (%deg->rad x))))
    (list "COS"       1 (fn (_ x) (Float cos (%deg->rad x))))
    (list "TAN"       1 (fn (_ x) (Float tan (%deg->rad x))))
    (list "ARCTAN"    1 (fn (_ x) (%rad->deg (Float atan (%as-float x)))))
    (list "ROUND"     1 (fn (_ x) (Float inexact->exact (Float round (%as-float x)))))
    (list "INT"       1 (fn (_ x) (Float inexact->exact (Float floor (%as-float x)))))
    (list "NOT"       1 (fn (_ x) (not x)))

    ; 2-arg math functions
    (list "REMAINDER" 2 (fn (_ a b) (% a b)))
    (list "RAND"      2 (fn (_ low high) (%logo-rand low high)))
    (list "POWER"     2 (fn (_ base exp) (Float exp (Float * (%as-float exp) (Float log (%as-float base))))))

    ))

; Constants as variables
(set! %logo-vars
  (pair (pair "PI" %pi) %logo-vars))

(provide x/logo/math
  %logo-rand %lfsr-state)

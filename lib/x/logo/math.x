; math.x -- Logo math functions and LFSR random number generator
(import x/logo/state)
(import x/logo/types)
(import x/logo/expr)
(import x/num/float)

; ============================================================
; Degree/radian conversion
; ============================================================

(def %deg->rad
  (fn (_ deg) (f/ (f* (%as-float deg) %pi) (exact->inexact 180))))

(def %rad->deg
  (fn (_ rad) (f/ (f* rad (exact->inexact 180)) %pi)))

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
    (list "SQRT"      1 (fn (_ x) (fsqrt (%as-float x))))
    (list "ABS"       1 (fn (_ x) (if (float? x) (fabs x) (if (< x 0) (- x) x))))
    (list "SIN"       1 (fn (_ x) (fsin (%deg->rad x))))
    (list "COS"       1 (fn (_ x) (fcos (%deg->rad x))))
    (list "TAN"       1 (fn (_ x) (ftan (%deg->rad x))))
    (list "ARCTAN"    1 (fn (_ x) (%rad->deg (fatan (%as-float x)))))
    (list "ROUND"     1 (fn (_ x) (inexact->exact (fround (%as-float x)))))
    (list "INT"       1 (fn (_ x) (inexact->exact (ffloor (%as-float x)))))
    (list "NOT"       1 (fn (_ x) (not x)))

    ; 2-arg math functions
    (list "REMAINDER" 2 (fn (_ a b) (% a b)))
    (list "RAND"      2 (fn (_ low high) (%logo-rand low high)))
    (list "POWER"     2 (fn (_ base exp) (fexp (f* (%as-float exp) (flog (%as-float base))))))

    ))

; Constants as variables
(set! %logo-vars
  (pair (pair "PI" %pi) %logo-vars))

(provide x/logo/math
  %logo-rand %lfsr-state)

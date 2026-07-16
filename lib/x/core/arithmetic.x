; arithmetic.x -- Variadic arithmetic wrappers
;
; Wraps binary C arithmetic primitives into variadic functions using fold.
; Requires: core/list.x (fold)

; Save integer primitives before overriding
(def %int+ +)
(def %int- -)
(def %int* *)
(def %int/ /)
(def %int% %)
(def %int< <)
(def %int= =)
(def %int-number? number?)

; The BINARY case bypasses fold entirely: (op a b) is the overwhelming
; shape (every counter, every digit loop), and the fold entry costs
; ~1,100 objects per call (per-step churn -- the measured 2026-07-16
; allocation disease).  0/1/2-arg tiers touch no list machinery.
(set! +
  (fn (_ . args)
    (if (eq? args ()) 0
      (if (eq? (rest args) ()) (first args)
        (if (eq? (rest (rest args)) ())
          (%int+ (first args) (first (rest args)))
          (fold %int+ (first args) (rest args)))))))
(set! *
  (fn (_ . args)
    (if (eq? args ()) 1
      (if (eq? (rest args) ()) (first args)
        (if (eq? (rest (rest args)) ())
          (%int* (first args) (first (rest args)))
          (fold %int* (first args) (rest args)))))))
(set! /
  (fn (_ . args)
    (if (eq? args ()) 1
      (if (eq? (rest args) ()) (first args)
        (if (eq? (rest (rest args)) ())
          (%int/ (first args) (first (rest args)))
          (fold %int/ (first args) (rest args)))))))
(set! -
  (fn (_ . args)
    (if (eq? args ())
      0
      (if (eq? (rest args) ())
        (%int- 0 (first args))
        (if (eq? (rest (rest args)) ())
          (%int- (first args) (first (rest args)))
          (fold %int- (first args) (rest args)))))))
(set! %
  (fn (_ . args)
    (if (eq? (rest args) ()) (first args)
      (if (eq? (rest (rest args)) ())
        (%int% (first args) (first (rest args)))
        (fold %int% (first args) (rest args))))))

(doc (provide x/core/arithmetic)
  "Variadic +, -, *, /, % folded over the binary C primitives.")

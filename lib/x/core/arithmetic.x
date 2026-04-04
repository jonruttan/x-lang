; arithmetic.x -- Variadic arithmetic wrappers
;
; Wraps binary C arithmetic primitives into variadic functions using fold.
; Requires: core/list.x (fold)

; Save integer primitives before overriding
(def %int+ +)
(def %int- -)
(def %int* *)
(def %int/ /)
(def modulo-int %)
(def %int< <)
(def %int= =)
(def %int-number? number?)

(set! +
  (fn (_ . args)
    (if (null? args) 0 (fold %int+ (first args) (rest args)))))
(set! *
  (fn (_ . args)
    (if (null? args) 1 (fold %int* (first args) (rest args)))))
(set! /
  (fn (_ . args)
    (if (null? args) 1 (fold %int/ (first args) (rest args)))))
(set! -
  (fn (_ . args)
    (if (null? args)
      0
      (if (null? (rest args))
        (%int- 0 (first args))
        (fold %int- (first args) (rest args))))))
(set! % (fn (_ . args) (fold modulo-int (first args) (rest args))))

(provide x/core/arithmetic modulo-int)

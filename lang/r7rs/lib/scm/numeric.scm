; --- Numeric extensions (R7RS §6.2) ---

(define (square x) (* x x))
(define (truncate-quotient a b) (quotient a b))
(define (truncate-remainder a b) (remainder a b))
(define
  (floor-quotient a b)
  (let ((q (quotient a b)))
    (if (and
          (not (zero? (remainder a b)))
          (or
            (and (negative? a) (positive? b))
            (and (positive? a) (negative? b))))
      (- q 1)
      q)))
(define
  (floor-remainder a b)
  (- a (* b (floor-quotient a b))))

; --- IEEE 754 predicates ---

(define %pos-inf (/ (exact->inexact 1) (exact->inexact 0)))
(define
  %neg-inf
  (/ (exact->inexact (- 0 1)) (exact->inexact 0)))
(define (nan? x) (and (float? x) (not (= x x))))
(define
  (infinite? x)
  (and (float? x) (or (= x %pos-inf) (= x %neg-inf))))
(define
  (finite? x)
  (and (number? x) (not (nan? x)) (not (infinite? x))))

; --- Exact/inexact conversion (R7RS names) ---

(define exact inexact->exact)
(define inexact exact->inexact)

; --- exact-integer-sqrt ---

(define
  (exact-integer-sqrt k)
  (let ((s (inexact->exact (fsqrt (exact->inexact k)))))
    (if (> (* s s) k)
      (let ((s1 (- s 1))) (values s1 (- k (* s1 s1))))
      (values s (- k (* s s))))))

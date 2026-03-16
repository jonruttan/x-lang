; --- Character extensions (R7RS §6.6) ---

(define (char-foldcase c) (char-downcase c))

; --- Case-insensitive character comparisons (override R5RS to use char-foldcase) ---

(define
  (char-ci=? a b)
  (char=? (char-foldcase a) (char-foldcase b)))
(define
  (char-ci<? a b)
  (char<? (char-foldcase a) (char-foldcase b)))
(define
  (char-ci>? a b)
  (char>? (char-foldcase a) (char-foldcase b)))
(define
  (char-ci<=? a b)
  (char<=? (char-foldcase a) (char-foldcase b)))
(define
  (char-ci>=? a b)
  (char>=? (char-foldcase a) (char-foldcase b)))

; --- digit-value ---

(define
  (digit-value c)
  (let ((n (char->integer c)))
    (cond ((and (>= n 48) (<= n 57)) (- n 48)) (#t #f))))

; --- Deep structural equality (R5RS §6.1) ---

(define
  (equal? a b)
  (cond
    ((and (pair? a) (pair? b))
      (and (equal? (car a) (car b)) (equal? (cdr a) (cdr b))))
    ((and (vector? a) (vector? b))
      (equal? (vector->list a) (vector->list b)))
    ((and (number? a) (number? b)) (= a b))
    ((and (string? a) (string? b)) (string=? a b))
    ((and (char? a) (char? b))
      (= (char->integer a) (char->integer b)))
    (#t (eq? a b))))

; --- Equivalence (identity for pairs/procs, = for numbers/chars) ---

(define
  (eqv? a b)
  (cond
    ((and (number? a) (number? b)) (= a b))
    ((and (char? a) (char? b))
      (= (char->integer a) (char->integer b)))
    (#t (eq? a b))))

; --- boolean? ---

(define (boolean? x) (or (eq? x #t) (eq? x #f)))

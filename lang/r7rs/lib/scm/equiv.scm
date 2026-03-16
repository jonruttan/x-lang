; --- Equivalence extensions (R7RS §6.1) ---

(define (boolean=? a b) (if a (if b #t #f) (if b #f #t)))
(define (symbol=? a b) (eq? a b))

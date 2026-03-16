; --- Vector extensions (R7RS §6.8) ---

(define (vector-copy v) (list->vector (vector->list v)))
(define
  (vector-append a b)
  (list->vector (append (vector->list a) (vector->list b))))
(define
  (vector-map f v)
  (list->vector (map f (vector->list v))))
(define
  (vector-for-each f v)
  (for-each f (vector->list v)))

; --- String/Vector conversions ---

(define (string->vector s) (list->vector (string->list s)))
(define (vector->string v) (list->string (vector->list v)))

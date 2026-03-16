; --- String extensions (R7RS §6.7) ---

; --- Case-insensitive string comparisons (loop-based with char-foldcase) ---

(define
  (string-ci=? a b)
  (and
    (= (string-length a) (string-length b))
    (let loop
      ((i 0))
      (or
        (= i (string-length a))
        (and
          (char-ci=? (string-ref a i) (string-ref b i))
          (loop (+ i 1)))))))
(define
  (string-ci<? a b)
  (let loop
    ((i 0))
    (cond
      ((= i (string-length a)) (< i (string-length b)))
      ((= i (string-length b)) #f)
      ((char-ci<? (string-ref a i) (string-ref b i)) #t)
      ((char-ci>? (string-ref a i) (string-ref b i)) #f)
      (#t (loop (+ i 1))))))
(define (string-ci>? a b) (string-ci<? b a))
(define (string-ci<=? a b) (not (string-ci>? a b)))
(define (string-ci>=? a b) (not (string-ci<? a b)))

; --- String case conversion ---

(define
  (string-upcase s)
  (list->string (map char-upcase (string->list s))))
(define
  (string-downcase s)
  (list->string (map char-downcase (string->list s))))
(define
  (string-foldcase s)
  (list->string (map char-foldcase (string->list s))))

; --- String higher-order operations ---

(define
  (string-map f s)
  (list->string (map f (string->list s))))
(define
  (string-for-each f s)
  (for-each f (string->list s)))

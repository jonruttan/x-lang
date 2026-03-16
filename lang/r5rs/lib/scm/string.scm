; --- String operations (R5RS §6.3.5) ---

; --- String to list ---

(define
  (string->list s)
  (let loop
    ((i (- (string-length s) 1)) (acc ()))
    (if (< i 0) acc (loop (- i 1) (cons (string-ref s i) acc)))))

; --- String constructor ---

(define (string . chars) (list->string chars))

; --- String mutation (rebuilds; x-lang strings are immutable) ---

(define (string-set! s k c)
  (list->string
    (let loop ((i 0) (lst (string->list s)))
      (if (null? lst) ()
        (cons (if (= i k) c (car lst))
              (loop (+ i 1) (cdr lst)))))))
(define (string-fill! s c)
  (make-string (string-length s) c))

; --- Variadic string-append ---

(define %string-append-2 string-append)
(define
  (string-append . args)
  (if (null? args)
    ""
    (let loop
      ((rest (cdr args)) (acc (car args)))
      (if (null? rest)
        acc
        (loop (cdr rest) (%string-append-2 acc (car rest)))))))

; --- String ordering ---

(define
  (string<? a b)
  (let loop
    ((i 0))
    (cond
      ((= i (string-length a)) (< i (string-length b)))
      ((= i (string-length b)) #f)
      ((char<? (string-ref a i) (string-ref b i)) #t)
      ((char>? (string-ref a i) (string-ref b i)) #f)
      (#t (loop (+ i 1))))))
(define (string>? a b) (string<? b a))
(define (string<=? a b) (not (string>? a b)))
(define (string>=? a b) (not (string<? a b)))

; --- Case-insensitive string comparison ---

(define
  (%string-downcase s)
  (list->string (map char-downcase (string->list s))))
(define
  (string-ci=? a b)
  (string=? (%string-downcase a) (%string-downcase b)))
(define
  (string-ci<? a b)
  (string<? (%string-downcase a) (%string-downcase b)))
(define
  (string-ci>? a b)
  (string>? (%string-downcase a) (%string-downcase b)))
(define
  (string-ci<=? a b)
  (string<=? (%string-downcase a) (%string-downcase b)))
(define
  (string-ci>=? a b)
  (string>=? (%string-downcase a) (%string-downcase b)))

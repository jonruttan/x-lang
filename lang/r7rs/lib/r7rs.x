; # Computational Expressions in C
;
; ## r7rs.x -- R7RS Scheme Personality
;
; @description R7RS-compatible Scheme built on x-lang (extends R5RS)
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2024 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
(do
  (include "lang/r5rs/lib/r5rs.x")

  ; --- Booleans ---
  (define (boolean=? a b) (if a (if b #t #f) (if b #f #t)))

  ; --- Symbols ---
  (define (symbol=? a b) (eq? a b))

  ; --- Number predicates ---
  (define integer? number?)

  ; --- Math ---
  (define (square x) (* x x))
  (define (exact-integer? x) (number? x))
  (define (exact? x) (number? x))
  (define (inexact? x) #f)
  (define (truncate-quotient a b) (quotient a b))
  (define (truncate-remainder a b) (remainder a b))
  (define (floor-quotient a b)
    (let ((q (quotient a b)))
      (if (and (not (zero? (remainder a b)))
               (or (and (negative? a) (positive? b))
                   (and (positive? a) (negative? b))))
        (- q 1) q)))
  (define (floor-remainder a b) (- a (* b (floor-quotient a b))))
  (define (truncate x) x)

  ; --- Character classification ---
  (define (char-alphabetic? c)
    (let ((n (char->integer c)))
      (or (and (>= n 65) (<= n 90)) (and (>= n 97) (<= n 122)))))
  (define (char-numeric? c)
    (let ((n (char->integer c)))
      (and (>= n 48) (<= n 57))))
  (define (char-whitespace? c)
    (let ((n (char->integer c)))
      (or (= n 32) (= n 9) (= n 10) (= n 13))))
  (define (char-upper-case? c)
    (let ((n (char->integer c)))
      (and (>= n 65) (<= n 90))))
  (define (char-lower-case? c)
    (let ((n (char->integer c)))
      (and (>= n 97) (<= n 122))))
  (define (char-upcase c)
    (if (char-lower-case? c) (integer->char (- (char->integer c) 32)) c))
  (define (char-downcase c)
    (if (char-upper-case? c) (integer->char (+ (char->integer c) 32)) c))
  (define (char-foldcase c) (char-downcase c))

  ; --- Case-insensitive character comparisons ---
  (define (char-ci=? a b) (char=? (char-foldcase a) (char-foldcase b)))
  (define (char-ci<? a b) (char<? (char-foldcase a) (char-foldcase b)))
  (define (char-ci>? a b) (char>? (char-foldcase a) (char-foldcase b)))
  (define (char-ci<=? a b) (char<=? (char-foldcase a) (char-foldcase b)))
  (define (char-ci>=? a b) (char>=? (char-foldcase a) (char-foldcase b)))

  ; --- Case-insensitive string comparisons ---
  (define (string-ci=? a b)
    (and (= (string-length a) (string-length b))
         (let loop ((i 0))
           (or (= i (string-length a))
               (and (char-ci=? (string-ref a i) (string-ref b i))
                    (loop (+ i 1)))))))
  (define (string-ci<? a b)
    (let loop ((i 0))
      (cond ((= i (string-length a)) (< i (string-length b)))
            ((= i (string-length b)) #f)
            ((char-ci<? (string-ref a i) (string-ref b i)) #t)
            ((char-ci>? (string-ref a i) (string-ref b i)) #f)
            (#t (loop (+ i 1))))))
  (define (string-ci>? a b) (string-ci<? b a))
  (define (string-ci<=? a b) (not (string-ci>? a b)))
  (define (string-ci>=? a b) (not (string-ci<? a b)))

  ; --- Lists ---
  (define (make-list n . fill)
    (let ((v (if (null? fill) #f (car fill))))
      (let loop ((i n) (acc ()))
        (if (= i 0) acc (loop (- i 1) (cons v acc))))))
  (define (list-copy lst)
    (if (pair? lst) (cons (car lst) (list-copy (cdr lst))) lst))

  ; --- Vectors ---
  (define (vector-copy v)
    (list->vector (vector->list v)))
  (define (vector-append a b)
    (list->vector (append (vector->list a) (vector->list b))))
  (define (vector-map f v)
    (list->vector (map f (vector->list v))))
  (define (vector-for-each f v)
    (for-each f (vector->list v)))

  ; --- Strings ---
  (define (string-for-each f s)
    (for-each f (string->list s)))

  (lit r7rs)
)

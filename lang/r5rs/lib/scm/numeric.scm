; --- Numeric operations (R5RS §6.2) ---

; --- Math ---

(define (quotient a b) (%int/ a b))
(define (remainder a b) (- a (* b (quotient a b))))
(define
  (modulo a b)
  (let ((r (remainder a b)))
    (if (zero? r)
      r
      (if (if (> b 0) (< r 0) (> r 0)) (+ r b) r))))

; --- Number type predicates ---
; Tower: integer? ⊂ rational? ⊂ real? ⊂ complex? = number?

(define
  (integer? x)
  (cond
    ((%int-number? x) #t)
    ((float? x) (= x (ftrunc x)))
    (#t #f)))
(define (exact? x) (if (%rat? x) #t (%int-number? x)))
(define (inexact? x) (float? x))
(define (exact-integer? x) (%int-number? x))
; rational?, real?, complex?, number? already set by rational.x / complex.x

; --- Rational accessors ---

(define
  (numerator x)
  (cond
    ((%rat? x) (first (first x)))
    ((%int-number? x) x)
    (#t (error "non-rational"))))
(define
  (denominator x)
  (cond
    ((%rat? x) (rest (first x)))
    ((%int-number? x) 1)
    (#t (error "non-rational"))))

; --- Variadic comparisons ---

; Save binary float-aware versions before redefining as variadic

(define %bin= =)
(define %bin< <)
(define
  (= . args)
  (if (null? (cdr args))
    #t
    (let loop
      ((a (car args)) (rest (cdr args)))
      (if (null? rest)
        #t
        (if (%bin= a (car rest)) (loop (car rest) (cdr rest)) #f)))))
(define
  (< . args)
  (if (null? (cdr args))
    #t
    (let loop
      ((a (car args)) (rest (cdr args)))
      (if (null? rest)
        #t
        (if (%bin< a (car rest)) (loop (car rest) (cdr rest)) #f)))))
(define
  (> . args)
  (if (null? (cdr args))
    #t
    (let loop
      ((a (car args)) (rest (cdr args)))
      (if (null? rest)
        #t
        (if (%bin< (car rest) a) (loop (car rest) (cdr rest)) #f)))))
(define
  (<= . args)
  (if (null? (cdr args))
    #t
    (let loop
      ((a (car args)) (rest (cdr args)))
      (if (null? rest)
        #t
        (if (not (%bin< (car rest) a))
          (loop (car rest) (cdr rest))
          #f)))))
(define
  (>= . args)
  (if (null? (cdr args))
    #t
    (let loop
      ((a (car args)) (rest (cdr args)))
      (if (null? rest)
        #t
        (if (not (%bin< a (car rest)))
          (loop (car rest) (cdr rest))
          #f)))))

; --- Variadic min/max ---

(define
  (min . args)
  (let loop
    ((best (car args)) (rest (cdr args)))
    (if (null? rest)
      best
      (loop (if (< (car rest) best) (car rest) best) (cdr rest)))))
(define
  (max . args)
  (let loop
    ((best (car args)) (rest (cdr args)))
    (if (null? rest)
      best
      (loop (if (> (car rest) best) (car rest) best) (cdr rest)))))

; --- Variadic gcd/lcm ---

(define
  (%gcd2 a b)
  (if (zero? b) a (%gcd2 b (remainder a b))))
(define
  (gcd . args)
  (if (null? args)
    0
    (let loop
      ((acc (abs (car args))) (rest (cdr args)))
      (if (null? rest)
        acc
        (loop (%gcd2 acc (abs (car rest))) (cdr rest))))))
(define
  (%lcm2 a b)
  (if (zero? b) 0 (abs (* (quotient a (%gcd2 a b)) b))))
(define
  (lcm . args)
  (if (null? args)
    1
    (let loop
      ((acc (abs (car args))) (rest (cdr args)))
      (if (null? rest)
        acc
        (loop (%lcm2 acc (abs (car rest))) (cdr rest))))))

; --- R5RS math with float support ---

(define
  (floor x)
  (if (float? x) (inexact->exact (ffloor x)) x))
(define
  (ceiling x)
  (if (float? x) (inexact->exact (fceil x)) x))
(define
  (truncate x)
  (if (float? x) (inexact->exact (ftrunc x)) x))
(define
  (round x)
  (if (float? x) (inexact->exact (frint x)) x))
(define
  (sqrt x)
  (if (and (%int-number? x) (>= x 0))
    (let ((s (inexact->exact (fsqrt (exact->inexact x)))))
      (if (= (* s s) x) s (fsqrt (exact->inexact x))))
    (fsqrt (if (float? x) x (exact->inexact x)))))
(define
  sin
  (lambda (x) (fsin (if (float? x) x (exact->inexact x)))))
(define
  cos
  (lambda (x) (fcos (if (float? x) x (exact->inexact x)))))
(define
  tan
  (lambda (x) (ftan (if (float? x) x (exact->inexact x)))))
(define
  asin
  (lambda (x) (fasin (if (float? x) x (exact->inexact x)))))
(define
  acos
  (lambda (x) (facos (if (float? x) x (exact->inexact x)))))
(define
  atan
  (lambda
    (x . rest)
    (if (null? rest)
      (fatan (if (float? x) x (exact->inexact x)))
      (fatan2
        (if (float? x) x (exact->inexact x))
        (if (float? (car rest))
          (car rest)
          (exact->inexact (car rest)))))))
(define
  (exp x)
  (fexp (if (float? x) x (exact->inexact x))))
(define
  (log x)
  (flog (if (float? x) x (exact->inexact x))))

; --- Generic number->string / string->number ---

(define %int-number->string number->string)
(define %int-string->number string->number)
(define
  (number->string n . radix)
  (if (float? n)
    (float->string (first n))
    (if (null? radix)
      (%int-number->string n)
      (%int-number->string n (car radix)))))
(define
  (string->number s . radix)
  (if (null? radix)
    (let ((has-dot
            (let loop
              ((i 0))
              (cond
                ((= i (string-length s)) #f)
                ((char=? (string-ref s i) #\.) #t)
                (#t (loop (+ i 1)))))))
      (if has-dot
        (make-instance %float (string->float s))
        (%int-string->number s)))
    (%int-string->number s (car radix))))

; --- Generic expt (supports float exponents) ---

(define
  (expt base exp)
  (cond
    ((and (%int-number? base) (%int-number? exp) (>= exp 0))
      (cond
        ((zero? exp) 1)
        ((even? exp) (expt (* base base) (quotient exp 2)))
        (#t (* base (expt base (- exp 1))))))
    (#t
      (fpow
        (if (float? base) base (exact->inexact base))
        (if (float? exp) exp (exact->inexact exp))))))

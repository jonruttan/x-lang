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

(include "lang/r5rs/lib/r5rs-base.x")

(begin
  ; float.x is already included by r5rs-base.x

  ; --- Booleans ---

  (define (boolean=? a b) (if a (if b #t #f) (if b #f #t)))
  ; --- Symbols ---

  (define (symbol=? a b) (eq? a b))
  ; --- Math ---

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
  ; floor/ceiling/truncate/round already provided by r5rs-base.x

  ; --- IEEE 754 predicates ---

  ; Note: float literals not available inside do blocks; use exact->inexact

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
  ; sqrt/expt/number->string/string->number already provided by r5rs-base.x

  ; --- Character classification ---

  (define
    (char-alphabetic? c)
    (let ((n (char->integer c)))
      (or (and (>= n 65) (<= n 90)) (and (>= n 97) (<= n 122)))))
  (define
    (char-numeric? c)
    (let ((n (char->integer c))) (and (>= n 48) (<= n 57))))
  (define
    (char-whitespace? c)
    (let ((n (char->integer c)))
      (or (= n 32) (= n 9) (= n 10) (= n 13))))
  (define
    (char-upper-case? c)
    (let ((n (char->integer c))) (and (>= n 65) (<= n 90))))
  (define
    (char-lower-case? c)
    (let ((n (char->integer c))) (and (>= n 97) (<= n 122))))
  (define
    (char-upcase c)
    (if (char-lower-case? c)
      (integer->char (- (char->integer c) 32))
      c))
  (define
    (char-downcase c)
    (if (char-upper-case? c)
      (integer->char (+ (char->integer c) 32))
      c))
  (define (char-foldcase c) (char-downcase c))
  ; --- Case-insensitive character comparisons ---

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
  ; --- Case-insensitive string comparisons ---

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
  ; --- Lists ---

  (define
    (make-list n . fill)
    (let ((v (if (null? fill) #f (car fill))))
      (let loop
        ((i n) (acc ()))
        (if (= i 0) acc (loop (- i 1) (cons v acc))))))
  (define
    (list-copy lst)
    (if (pair? lst) (cons (car lst) (list-copy (cdr lst))) lst))
  ; --- Vectors ---

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
  ; --- Strings ---

  (define (string . chars) (list->string chars))
  (define
    (string-upcase s)
    (list->string (map char-upcase (string->list s))))
  (define
    (string-downcase s)
    (list->string (map char-downcase (string->list s))))
  (define
    (string-foldcase s)
    (list->string (map char-foldcase (string->list s))))
  (define
    (string-map f s)
    (list->string (map f (string->list s))))
  (define
    (string-for-each f s)
    (for-each f (string->list s)))
  ; --- Override forms that use (lit do) to use (lit begin) instead ---

  (define
    when
    (op (test . body)
      e
      (if (eval test e) (eval (pair (lit begin) body) e))))
  (define
    unless
    (op (test . body)
      e
      (if (not (eval test e)) (eval (pair (lit begin) body) e))))
  (define
    let*
    (op (bindings . body)
      e
      (if (null? bindings)
        (eval (pair (lit begin) body) e)
        (eval
          (list
            (lit let)
            (list (first bindings))
            (pair (lit let*) (pair (rest bindings) body)))
          e))))
  ; --- Iteration ---

  ; (do ((var init step) ...) (test expr ...) command ...)

  (define
    do
    (op (bindings test-and-result . body)
      env
      (let ((vars (map car bindings))
             (inits (map (lambda (b) (list-ref b 1)) bindings))
             (steps
               (map
                 (lambda (b) (if (> (length b) 2) (list-ref b 2) (car b)))
                 bindings))
             (test (car test-and-result))
             (result (cdr test-and-result)))
        (eval
          (cons
            (list
              (lit lambda)
              ()
              (cons
                (lit letrec)
                (cons
                  (list
                    (list
                      (lit %do-loop)
                      (cons
                        (lit lambda)
                        (cons
                          vars
                          (list
                            (list
                              (lit if)
                              test
                              (if (null? result)
                                (list (lit if) #f #f)
                                (cons (lit begin) result))
                              (append
                                (cons (lit begin) body)
                                (list (cons (lit %do-loop) steps)))))))))
                  (list (cons (lit %do-loop) inits)))))
            ())
          env))))
  ; --- case-lambda ---

  ; (case-lambda (formals body ...) ...)

  (define
    case-lambda
    (op clauses
      env
      (eval
        (list
          (lit lambda)
          (lit %cl-args)
          (cons
            (lit cond)
            (append
              (map
                (lambda
                  (clause)
                  (list
                    (list
                      (lit =)
                      (list (lit length) (lit %cl-args))
                      (length (car clause)))
                    (list
                      (lit apply)
                      (cons (lit lambda) clause)
                      (lit %cl-args))))
                clauses)
              (list
                (list
                  #t
                  (list (lit error) "case-lambda: no matching clause"))))))
        env)))
  ; --- Promises ---

  (define
    %promise
    (make-type
      (lit PROMISE)
      (list
        (pair (lit write) (lambda (self) (display "#<promise>"))))))
  (define (promise? x) (type? x %promise))
  ; delay creates a promise wrapping a thunk with memoization

  (define
    delay
    (op (expr)
      env
      (let ((forced #f) (result #f))
        (make-instance
          %promise
          (lambda
            ()
            (if forced
              result
              (let ((val (eval expr env)))
                (set! forced #t)
                (set! result val)
                val)))))))
  ; make-promise wraps an already-computed value

  (define
    (make-promise x)
    (if (promise? x)
      x
      (let ((val x)) (make-instance %promise (lambda () val)))))
  ; force extracts the value from a promise

  (define (force p) (if (promise? p) ((first p)) p))
  ; values/call-with-values already provided by r5rs-base.x

  ; --- Characters (R7RS additions) ---

  (define
    (digit-value c)
    (let ((n (char->integer c)))
      (cond ((and (>= n 48) (<= n 57)) (- n 48)) (#t #f))))
  ; --- Strings/Vectors conversions ---

  (define (string->vector s) (list->vector (string->list s)))
  (define (vector->string v) (list->string (vector->list v)))
  ; --- Math (R7RS additions) ---

  (define
    (exact-integer-sqrt k)
    (let ((s (inexact->exact (fsqrt (exact->inexact k)))))
      (if (> (* s s) k)
        (let ((s1 (- s 1))) (values s1 (- k (* s1 s1))))
        (values s (- k (* s s))))))
  ; --- Error objects ---

  ; x-lang errors are strings; error-object? tests for string

  (define (error-object? obj) (string? obj))
  (define (error-object-message obj) obj)
  (define (error-object-irritants obj) ())
  ; --- Records ---

  ; (define-record-type <name> (<ctor> field ...) <pred> (field accessor) ...)

  (define
    define-record-type
    (op (name constructor-spec pred . field-specs)
      env
      ; Build a (begin ...) form with all definitions, eval it at top level

      (eval
        (cons
          (lit begin)
          (append
            (list
              ; Type handle definition

              (list
                (lit def)
                name
                (list
                  (lit make-type)
                  (list (lit quote) name)
                  (list
                    (lit list)
                    (list
                      (lit pair)
                      (list (lit quote) (lit write))
                      (list
                        (lit fn)
                        (list (lit self))
                        (list
                          (lit display)
                          (string-append "#<" (symbol->string name) ">")))))))
              ; Constructor definition

              (list
                (lit def)
                (car constructor-spec)
                (list
                  (lit fn)
                  (cdr constructor-spec)
                  (list
                    (lit make-instance)
                    name
                    (cons
                      (lit list)
                      (map
                        (lambda (f) (list (lit pair) (list (lit quote) f) f))
                        (cdr constructor-spec))))))
              ; Predicate definition

              (list
                (lit def)
                pred
                (list
                  (lit fn)
                  (list (lit x))
                  (list (lit type?) (lit x) name))))
            ; Accessor definitions + return name

            (append
              (map
                (lambda
                  (spec)
                  (list
                    (lit def)
                    (list-ref spec 1)
                    (list
                      (lit fn)
                      (list (lit x))
                      (list
                        (lit cdr)
                        (list
                          (lit assq)
                          (list (lit quote) (car spec))
                          (list (lit first) (lit x)))))))
                field-specs)
              (list (list (lit quote) name)))))))))

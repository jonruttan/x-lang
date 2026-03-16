; # Computational Expressions in C
;
; ## scm.x -- Scheme Personality
;
; @description R5RS-compatible Scheme built on x-lang
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2024 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "

(include "lib/x-core.x")

(do
  ; --- Aliases ---

  (def lambda fn)
  (def begin do)
  (def set! set)
  (def modulo %)
  (def cons pair)
  (def car first)
  (def cdr rest)
  (def set-car! set-first)
  (def set-cdr! set-rest)
  (def quote lit)
  (def quasiquote quasi)
  (def cond match)
  ; --- Boolean constants ---

  (def else #t)
  ; --- Float support ---

  (include "lib/x/float.x")
  ; --- Numeric tower ---

  (include "lib/x/rational.x")
  (include "lib/x/complex.x")
  ; --- string->number: try integer first, then float ---

  (def %string->number-int string->number)
  (def %string->number-try-float
    (fn (s)
      (def %raw (string->float s))
      (if (= %raw 0)
        (if (= (string-ref s 0) (string-ref "0" 0))
          (make-instance %float 0)
          ())
        (make-instance %float %raw))))
  (def string->number
    (fn (s . rest)
      (if (not (null? rest))
        (%string->number-int s (first rest))
        (if (= (string-length s) 0) ()
          (let ((%r (%string->number-int s)))
            (if %r %r (%string->number-try-float s)))))))
  ; --- write-char / newline ---

  (def write-char (fn (c) (display (make-string 1 c))))
  ; --- define: (define x val) or (define (f args...) body...) ---

  (def define
    (op (name-or-form . body)
      e
      (if (pair? name-or-form)
        (eval
          (list
            (lit def)
            (first name-or-form)
            (pair (lit fn) (pair (rest name-or-form) body))))
        (eval (list (lit def) name-or-form (first body))))))
  ; --- Conditional forms ---

  (def when
    (op (test . body)
      e
      (if (eval test e) (tail-eval (pair (lit do) body) e))))
  (def unless
    (op (test . body)
      e
      (if (not (eval test e)) (tail-eval (pair (lit do) body) e))))
  ; --- let* ---

  (def let*
    (op (bindings . body)
      e
      (if (null? bindings)
        (tail-eval (pair (lit do) body) e)
        (tail-eval
          (list
            (lit let)
            (list (first bindings))
            (pair (lit let*) (pair (rest bindings) body)))
          e))))
  ; --- Mutation ---

  (define
    (%vector-set-walk lst n val)
    (if (= n 0) (set-first lst val) (%vector-set-walk (rest lst) (- n 1) val)))
  (define
    (vector-set! v i val)
    (%vector-set-walk (first v) i val))
  (define
    (%vector-fill-walk lst n fill)
    (if (> n 0) (begin (set-first lst fill) (%vector-fill-walk (rest lst) (- n 1) fill))))
  (define (vector-fill! v fill)
    (%vector-fill-walk (first v) (vector-length v) fill))
  ; --- Composition accessors (all 28 c*r, up to 4 deep) ---

  (define (caar x) (first (first x)))
  (define (cadr x) (first (rest x)))
  (define (cdar x) (rest (first x)))
  (define (cddr x) (rest (rest x)))
  (define (caaar x) (first (first (first x))))
  (define (caadr x) (first (first (rest x))))
  (define (cadar x) (first (rest (first x))))
  (define (caddr x) (first (rest (rest x))))
  (define (cdaar x) (rest (first (first x))))
  (define (cdadr x) (rest (first (rest x))))
  (define (cddar x) (rest (rest (first x))))
  (define (cdddr x) (rest (rest (rest x))))
  (define (caaaar x) (first (first (first (first x)))))
  (define (caaadr x) (first (first (first (rest x)))))
  (define (caadar x) (first (first (rest (first x)))))
  (define (caaddr x) (first (first (rest (rest x)))))
  (define (cadaar x) (first (rest (first (first x)))))
  (define (cadadr x) (first (rest (first (rest x)))))
  (define (caddar x) (first (rest (rest (first x)))))
  (define (cadddr x) (first (rest (rest (rest x)))))
  (define (cdaaar x) (rest (first (first (first x)))))
  (define (cdaadr x) (rest (first (first (rest x)))))
  (define (cdadar x) (rest (first (rest (first x)))))
  (define (cdaddr x) (rest (first (rest (rest x)))))
  (define (cddaar x) (rest (rest (first (first x)))))
  (define (cddadr x) (rest (rest (first (rest x)))))
  (define (cdddar x) (rest (rest (rest (first x)))))
  (define (cddddr x) (rest (rest (rest (rest x)))))
  ; --- make-vector: accept 1 or 2 args (R5RS optional fill) ---

  (def %make-vector-orig make-vector)
  (define (make-vector n . rest)
    (%make-vector-orig n (if (null? rest) () (first rest))))
  ; --- Scheme list aliases (x.x provides the implementations) ---

  (define (list-ref lst n) (nth n lst))
  (define (list-tail lst n) (drop n lst))
  ; --- Scheme-specific list operations ---

  (define
    (member x lst)
    (match
      ((null? lst) #f)
      ((equal? x (first lst)) lst)
      (#t (member x (rest lst)))))
  (define
    (assoc key alist)
    (match
      ((null? alist) #f)
      ((equal? key (caar alist)) (first alist))
      (#t (assoc key (rest alist)))))
  ; --- String operations (R5RS aliases) ---

  (define (string-copy s) (substring s 0 (string-length s)))
  ; --- letrec ---

  (def letrec
    (op (bindings . body)
      e
      (tail-eval
        (pair
          (lit let)
          (pair
            (map (lambda (b) (list (first b) ())) bindings)
            (append
              (map
                (lambda (b) (list (lit set!) (first b) (cadr b)))
                bindings)
              body)))
        e)))
  ; --- Named let ---

  (def %let let)
  (def let
    (op (first-arg . rest-args)
      e
      (if (symbol? first-arg)
        (tail-eval
          (list
            (lit letrec)
            (list
              (list
                first-arg
                (pair
                  (lit lambda)
                  (pair (map car (first rest-args)) (rest rest-args)))))
            (pair first-arg (map cadr (first rest-args))))
          e)
        (tail-eval (pair (lit %let) (pair first-arg rest-args)) e))))
  ; --- do ---

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
        (tail-eval
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
  ; --- Override forms that used (lit do) to use (lit begin) instead ---

  ; (do was just redefined as the R5RS iteration form)

  (define
    when
    (op (test . body)
      e
      (if (eval test e) (tail-eval (pair (lit begin) body) e))))
  (define
    unless
    (op (test . body)
      e
      (if (not (eval test e)) (tail-eval (pair (lit begin) body) e))))
  (define
    let*
    (op (bindings . body)
      e
      (if (null? bindings)
        (tail-eval (pair (lit begin) body) e)
        (tail-eval
          (list
            (lit let)
            (list (first bindings))
            (pair (lit let*) (pair (rest bindings) body)))
          e))))
  ; --- R5RS cond (multi-expression clause bodies + => syntax) ---

  (define
    cond
    (op clauses
      e
      (let %cond-loop
        ((cls clauses))
        (if (null? cls)
          ()
          (let ((clause (first cls)))
            (if (eq? (first clause) (lit else))
              (tail-eval (pair (lit begin) (rest clause)) e)
              (let ((test-val (eval (first clause) e)))
                (if test-val
                  (if (and (pair? (rest clause)) (eq? (cadr clause) (lit =>)))
                    ((eval (caddr clause) e) test-val)
                    (tail-eval (pair (lit begin) (rest clause)) e))
                  (%cond-loop (rest cls))))))))))
  ; --- Promises ---

  (define
    %promise
    (make-type
      (lit PROMISE)
      (list
        (pair (lit write) (lambda (self) (display "#<promise>"))))))
  (define (promise? x) (type? x %promise))
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
  (define (force p) (if (promise? p) ((first p)) p))
  ; --- case (multi-expression clause bodies) ---

  (def case
    (op (key . clauses)
      e
      (def case-val (eval key e))
      (def case-match?
        (fn (datum)
          (if (number? case-val)
            (= case-val datum)
            (eq? case-val datum))))
      (def case-check-datums
        (fn (datums)
          (match
            ((null? datums) ())
            ((case-match? (first datums)) #t)
            (#t (case-check-datums (rest datums))))))
      (def case-loop
        (fn (cls)
          (match
            ((null? cls) ())
            ((or
               (eq? (first (first cls)) (lit else))
               (case-check-datums (first (first cls))))
              (tail-eval (pair (lit begin) (rest (first cls))) e))
            (#t (case-loop (rest cls))))))
      (case-loop clauses)))
  ; --- Deep structural equality (override x-lib equal? for pairs/vectors) ---

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
  ; --- List predicate ---

  (define
    (list? x)
    (if (null? x) #t (if (pair? x) (list? (cdr x)) #f)))
  ; --- Membership with eq? ---

  (define
    (memq x lst)
    (cond
      ((null? lst) #f)
      ((eq? x (car lst)) lst)
      (#t (memq x (cdr lst)))))
  ; --- Membership with eqv? ---

  (define
    (memv x lst)
    (cond
      ((null? lst) #f)
      ((eqv? x (car lst)) lst)
      (#t (memv x (cdr lst)))))
  ; --- Membership with equal? (redefined to use deep equal?) ---

  (define
    (member x lst)
    (cond
      ((null? lst) #f)
      ((equal? x (car lst)) lst)
      (#t (member x (cdr lst)))))
  ; --- Association with eq? ---

  (define
    (assq key alist)
    (cond
      ((null? alist) #f)
      ((eq? key (caar alist)) (car alist))
      (#t (assq key (cdr alist)))))
  ; --- Association with eqv? ---

  (define
    (assv key alist)
    (cond
      ((null? alist) #f)
      ((eqv? key (caar alist)) (car alist))
      (#t (assv key (cdr alist)))))
  ; --- Association with equal? (redefined to use deep equal?) ---

  (define
    (assoc key alist)
    (cond
      ((null? alist) #f)
      ((equal? key (caar alist)) (car alist))
      (#t (assoc key (cdr alist)))))
  ; --- Character comparisons ---

  (define
    (char=? a b)
    (= (char->integer a) (char->integer b)))
  (define
    (char<? a b)
    (< (char->integer a) (char->integer b)))
  (define
    (char>? a b)
    (> (char->integer a) (char->integer b)))
  (define
    (char<=? a b)
    (<= (char->integer a) (char->integer b)))
  (define
    (char>=? a b)
    (>= (char->integer a) (char->integer b)))
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
  ; --- Math ---

  (define (quotient a b) (%int/ a b))
  (define (remainder a b) (- a (* b (quotient a b))))
  (define
    (modulo a b)
    (let ((r (remainder a b)))
      (if (zero? r)
        r
        (if (if (> b 0) (< r 0) (> r 0)) (+ r b) r))))
  ; gcd, lcm, expt defined below as variadic/float-aware

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
  ; --- Variadic string-append (R5RS: takes any number of args) ---

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
  ; --- Multiple values ---

  (define
    %values
    (make-type
      (lit VALUES)
      (list
        (pair
          (lit write)
          (lambda
            (self)
            (for-each
              (lambda (v) (display " ") (write v))
              (first self)))))))
  (define
    (values . args)
    (if (= (length args) 1)
      (car args)
      (make-instance %values args)))
  (define
    (call-with-values producer consumer)
    (let ((result (producer)))
      (if (type? result %values)
        (apply consumer (first result))
        (consumer result))))
  ; --- First-class continuations with dynamic-wind ---
  ; call/cc is a stack-copying C primitive; wrap it to support
  ; dynamic-wind before/after thunk transitions.

  (define %wind-stack (list))
  (define %c-call/cc call/cc)

  ; Find longest common tail of two wind stacks.
  (define (%wind-common-tail a b)
    (let ((la (length a)) (lb (length b)))
      (let ((a (if (> la lb) (list-tail a (- la lb)) a))
            (b (if (> lb la) (list-tail b (- lb la)) b)))
        (let loop ((a a) (b b))
          (if (eq? a b) a
            (loop (cdr a) (cdr b)))))))

  ; Exit from current wind stack to common tail (after thunks).
  (define (%wind-exit current common)
    (if (not (eq? current common))
      (begin
        (set! %wind-stack (cdr current))
        ((cdr (car current)))
        (%wind-exit (cdr current) common))))

  ; Enter from common tail to target wind stack (before thunks).
  ; Recurse first so outermost before runs first.
  (define (%wind-enter target common)
    (if (not (eq? target common))
      (begin
        (%wind-enter (cdr target) common)
        (set! %wind-stack target)
        ((car (car target))))))

  (define (call-with-current-continuation proc)
    (let ((saved-winds %wind-stack))
      (%c-call/cc
        (lambda (k)
          (proc
            (lambda args
              (let ((common (%wind-common-tail %wind-stack saved-winds)))
                (%wind-exit %wind-stack common)
                (%wind-enter saved-winds common))
              (apply k args)))))))
  (define call/cc call-with-current-continuation)

  (define (dynamic-wind before thunk after)
    (before)
    (set! %wind-stack (cons (cons before after) %wind-stack))
    (let ((result (thunk)))
      (set! %wind-stack (cdr %wind-stack))
      (after)
      result))
  ; --- Environment procedures ---

  (define %current-env (op () e e))
  (define (scheme-report-environment version)
    (if (= version 5) (%current-env)
      (error "unsupported version")))
  (define (null-environment version)
    (if (= version 5) (%current-env)
      (error "unsupported version")))
  (define (interaction-environment) (%current-env))
  ; --- Port system (R5RS §6.6) ---

  ; FFI setup for file operations
  (define %libc (dlopen () 1))
  (define %c-open (dlsym %libc "open"))
  (define %c-close (dlsym %libc "close"))
  (define %c-malloc (dlsym %libc "malloc"))

  ; Base object navigation
  (define %base-root (first (%base)))
  (define %base-files (first (rest %base-root)))
  (define %base-env (first (rest (rest %base-root))))
  (define %filein-stack-slot %base-files)
  (define %fileout-stack-slot (rest %base-files))
  (define %buffer-stack-slot (rest (rest %base-env)))
  (define %fileout-atom (first (first (rest %base-files))))
  (define %line-stack-slot
    (rest (rest (rest (rest (rest %base-root))))))

  ; Save C primitives before overriding
  (define %prim-read read)
  (define %prim-read-char read-char)
  (define %prim-peek-char peek-char)
  (define %prim-write write)
  (define %prim-display display)
  (define %prim-newline newline)

  ; PORT custom type
  (define %port-type
    (make-type "PORT"
      (list
        (cons (lit write)
          (lambda (self)
            (let ((data (first self)))
              (%prim-display "#<")
              (%prim-display (cadr data))
              (%prim-display "-port ")
              (%prim-display (car data))
              (%prim-display ">")))))))
  ; Port constructor: (fd direction buffer)
  ; direction = input or output, buffer = for input ports only
  (define (%make-port fd direction buf)
    (make-instance %port-type (list fd direction buf #t)))
  (define (input-port? x)
    (and (type? x %port-type) (eq? (cadr (first x)) (lit input))))
  (define (output-port? x)
    (and (type? x %port-type) (eq? (cadr (first x)) (lit output))))
  (define (%port-fd p) (car (first p)))
  (define (%port-open? p) (cadddr (first p)))
  (define (%port-buffer p) (caddr (first p)))
  (define (%port-close! p)
    (set-car! (cdddr (first p)) #f))

  ; EOF object
  (define %eof-obj (cons (lit eof) (lit eof)))
  (define (eof-object? x) (eq? x %eof-obj))

  ; Current ports
  (define (%make-stdin-port)
    (%make-port 0 (lit input) (first (first %buffer-stack-slot))))
  (define (%make-stdout-port)
    (%make-port 1 (lit output) #f))
  (define (current-input-port) (%make-stdin-port))
  (define (current-output-port) (%make-stdout-port))

  ; Open/close
  (define (open-input-file path)
    (let ((fd (ptr-call %c-open path 0)))
      (if (< fd 0) (error "cannot open input file")
        (%make-port fd (lit input)
          (obj-make "BUFFER"
            (int->ptr (ptr-call %c-malloc 65536)) 32)))))
  (define (open-output-file path)
    (let ((fd (ptr-call %c-open path 1537 438)))
      (if (< fd 0) (error "cannot open output file")
        (%make-port fd (lit output) #f))))
  (define (close-input-port p)
    (ptr-call %c-close (%port-fd p))
    (%port-close! p))
  (define (close-output-port p)
    (ptr-call %c-close (%port-fd p))
    (%port-close! p))

  ; Input port redirection: push fd and buffer onto stacks
  (define (%with-input-port port thunk)
    (let ((fd (%port-fd port))
          (buf (%port-buffer port)))
      (set-car! %filein-stack-slot
        (cons fd (car %filein-stack-slot)))
      (set-car! %buffer-stack-slot
        (cons buf (car %buffer-stack-slot)))
      (let ((result (thunk)))
        (set-car! %filein-stack-slot
          (cdr (car %filein-stack-slot)))
        (set-car! %buffer-stack-slot
          (cdr (car %buffer-stack-slot)))
        result)))

  ; Output port redirection: swap fileout fd
  (define (%with-output-port port thunk)
    (let ((saved (first-int %fileout-atom)))
      (set-first-int %fileout-atom (%port-fd port))
      (let ((result (thunk)))
        (set-first-int %fileout-atom saved)
        result)))

  ; Port-aware read
  (set! read
    (lambda args
      (if (null? args)
        (let ((r (%prim-read)))
          (if (null? r) %eof-obj r))
        (%with-input-port (car args)
          (lambda ()
            (let ((r (%prim-read)))
              (if (null? r) %eof-obj r)))))))

  ; Port-aware read-char
  (set! read-char
    (lambda args
      (if (null? args)
        (let ((r (%prim-read-char)))
          (if (null? r) %eof-obj r))
        (%with-input-port (car args)
          (lambda ()
            (let ((r (%prim-read-char)))
              (if (null? r) %eof-obj r)))))))

  ; Port-aware peek-char
  (set! peek-char
    (lambda args
      (if (null? args)
        (let ((r (%prim-peek-char)))
          (if (null? r) %eof-obj r))
        (%with-input-port (car args)
          (lambda ()
            (let ((r (%prim-peek-char)))
              (if (null? r) %eof-obj r)))))))

  ; char-ready? (always #t for file ports, check buffer for stdin)
  (define (char-ready? . args) #t)

  ; Port-aware write
  (set! write
    (lambda (obj . args)
      (if (null? args)
        (%prim-write obj)
        (%with-output-port (car args)
          (lambda () (%prim-write obj))))))

  ; Port-aware display
  (set! display
    (lambda (obj . args)
      (if (null? args)
        (%prim-display obj)
        (%with-output-port (car args)
          (lambda () (%prim-display obj))))))

  ; Port-aware newline
  (set! newline
    (lambda args
      (if (null? args)
        (%prim-newline)
        (%with-output-port (car args)
          (lambda () (%prim-newline))))))

  ; Port-aware write-char
  (set! write-char
    (lambda (c . args)
      (if (null? args)
        (%prim-display (make-string 1 c))
        (%with-output-port (car args)
          (lambda () (%prim-display (make-string 1 c)))))))

  ; Higher-order port operations
  (define (call-with-input-file path proc)
    (let ((port (open-input-file path)))
      (let ((result (proc port)))
        (close-input-port port)
        result)))
  (define (call-with-output-file path proc)
    (let ((port (open-output-file path)))
      (let ((result (proc port)))
        (close-output-port port)
        result)))
  (define (with-input-from-file path thunk)
    (let ((port (open-input-file path)))
      (let ((result (%with-input-port port thunk)))
        (close-input-port port)
        result)))
  (define (with-output-to-file path thunk)
    (let ((port (open-output-file path)))
      (let ((result (%with-output-port port thunk)))
        (close-output-port port)
        result)))

  ; load = include
  (define load include)

  ; transcript (optional, no-op)
  (define (transcript-on filename) #f)
  (define (transcript-off) #f)

  ; boolean?
  (define (boolean? x) (or (eq? x #t) (eq? x #f)))
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
      (or (= n 32) (= n 9) (= n 10) (= n 13) (= n 12))))
  (define
    (char-upper-case? c)
    (let ((n (char->integer c))) (and (>= n 65) (<= n 90))))
  (define
    (char-lower-case? c)
    (let ((n (char->integer c))) (and (>= n 97) (<= n 122))))
  ; --- Character case conversion ---

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
  ; --- Case-insensitive character comparison ---

  (define
    (char-ci=? a b)
    (char=? (char-downcase a) (char-downcase b)))
  (define
    (char-ci<? a b)
    (char<? (char-downcase a) (char-downcase b)))
  (define
    (char-ci>? a b)
    (char>? (char-downcase a) (char-downcase b)))
  (define
    (char-ci<=? a b)
    (char<=? (char-downcase a) (char-downcase b)))
  (define
    (char-ci>=? a b)
    (char>=? (char-downcase a) (char-downcase b)))
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
  ; --- Quote shorthand: 'expr -> (lit expr) ---

  (def %quote-reader
    (fn args (pair (lit lit) (pair (%prim-read) ()))))
  (make-type
    "QUOTE"
    (list
      (pair
        (lit analyse)
        (fn (buffer score chr)
          (if (= chr (char->integer #\'))
            (score-set score 1 buffer)
            ())))
      (pair (lit read) %quote-reader)
      (pair
        (lit delimit)
        (fn (buffer score chr)
          (if (= chr (char->integer #\'))
            (%seq (buffer-unread buffer) buffer)
            ())))))
  ; --- Quasiquote shorthand: `expr -> (quasiquote expr) ---

  (def %quasiquote-reader
    (fn args (pair (lit quasiquote) (pair (%prim-read) ()))))
  (make-type
    "QUASIQUOTE"
    (list
      (pair
        (lit analyse)
        (fn (buffer score chr)
          (if (= chr (char->integer #\`))
            (score-set score 1 buffer)
            ())))
      (pair (lit read) %quasiquote-reader)
      (pair
        (lit delimit)
        (fn (buffer score chr)
          (if (= chr (char->integer #\`))
            (%seq (buffer-unread buffer) buffer)
            ())))))
  ; --- Unquote shorthand: ,expr -> (unquote expr)

  ;                         ,@expr -> (unquote-splicing expr) ---

  (def %unquote-reader
    (fn args (pair (lit unquote) (pair (%prim-read) ()))))
  (def %unquote-splicing-reader
    (fn args (pair (lit unquote-splicing) (pair (%prim-read) ()))))
  (make-type
    "UNQUOTE"
    (list
      (pair
        (lit analyse)
        (fn (buffer score chr)
          (if (= chr (char->integer #\,))
            (score-set score 1 buffer)
            ())))
      (pair (lit read) %unquote-reader)
      (pair
        (lit delimit)
        (fn (buffer score chr)
          (if (= chr (char->integer #\,))
            (%seq (buffer-unread buffer) buffer)
            ())))))
  (make-type
    "UNQUOTE-SPLICING"
    (list
      (pair
        (lit analyse)
        (fn (buffer score chr)
          (if (= chr (char->integer #\,))
            (fn (buffer score chr)
              (if (= chr (char->integer #\@))
                (score-set score 1 buffer)
                ()))
            ())))
      (pair (lit read) %unquote-splicing-reader)
      (pair
        (lit delimit)
        (fn (buffer score chr)
          (if (= chr (char->integer #\,))
            (%seq (buffer-unread buffer) buffer)
            ())))))
  ; --- Ellipsis tokenizer type ---

  ; Register '...' as a token so it parses as a symbol, not as dot-pair

  (define %ellipsis-sym (string->symbol "..."))
  ; State machine: dot1 → dot2 → dot3 → lookahead check

  (define
    %ellipsis-check
    (lambda
      (buffer score chr)
      (if (= chr 46)
        ()
        (%seq (buffer-unread buffer) (score-set score 1 buffer)))))
  (define
    %ellipsis-dot3
    (lambda
      (buffer score chr)
      (if (= chr 46)
        (%seq (score-set score 1 buffer) %ellipsis-check)
        ())))
  (define
    %ellipsis-dot2
    (lambda
      (buffer score chr)
      (if (= chr 46) %ellipsis-dot3 ())))
  (make-type
    "ELLIPSIS"
    (list
      (pair
        (lit analyse)
        (lambda
          (buffer score chr)
          (if (= chr 46) %ellipsis-dot2 ())))
      (pair (lit read) (lambda args %ellipsis-sym))))
  ; --- Hygienic Macros (define-syntax, syntax-rules, let-syntax) ---

  ; Gensym: generate unique symbols for hygiene

  (define %gensym-counter 0)
  (define
    (gensym)
    (set! %gensym-counter (+ %gensym-counter 1))
    (string->symbol
      (string-append "%g" (number->string %gensym-counter))))
  ; Safe eval: returns (t . value) if bound, () if unbound

  (define
    (%sr-safe-eval sym env)
    (guard (e ()) (pair #t (eval sym env))))
  ; Sentinel for pattern match failure (unique identity)

  (define %sr-no-match (pair (lit no) (lit match)))
  ; Remove duplicates (eq?)

  (define
    (%sr-unique lst)
    (let loop
      ((in lst) (out ()))
      (if (null? in)
        (reverse out)
        (if (memq (car in) out)
          (loop (cdr in) out)
          (loop (cdr in) (pair (car in) out))))))
  ; --- Ellipsis helpers ---

  ; Count fixed elements in a pattern tail (after ...)

  (define
    (%sr-tail-length pat)
    (if (pair? pat) (+ 1 (%sr-tail-length (cdr pat))) 0))
  ; Collect pattern variable names from a sub-pattern

  (define
    (%sr-pattern-pvars pat literals)
    (if (symbol? pat)
      (if (or (eq? pat (lit _)) (memq pat literals))
        ()
        (list pat))
      (if (pair? pat)
        (append
          (%sr-pattern-pvars (car pat) literals)
          (%sr-pattern-pvars (cdr pat) literals))
        ())))
  ; Find pvars in template that have ellipsis bindings

  (define
    (%sr-ellipsis-pvars template bindings)
    (if (symbol? template)
      (let ((b (assq template bindings)))
        (if (and b (pair? (cdr b)) (eq? (cadr b) %ellipsis-sym))
          (list template)
          ()))
      (if (pair? template)
        (append
          (%sr-ellipsis-pvars (car template) bindings)
          (%sr-ellipsis-pvars (cdr template) bindings))
        ())))
  ; Forward declaration for mutual recursion

  (define %sr-match ())
  ; Match (sub-pat ... . tail-pat) against form list

  (define
    (%sr-ellipsis-match
      sub-pat
      tail-pat
      form
      literals
      bindings)
    (let*
      ((pvars (%sr-unique (%sr-pattern-pvars sub-pat literals)))
        (tail-len (%sr-tail-length tail-pat))
        (form-len (length form))
        (rep-count (- form-len tail-len)))
      (if (< rep-count 0)
        %sr-no-match
        (let loop
          ((i 0)
            (f form)
            (collected (map (lambda (v) (list v)) pvars)))
          (if (= i rep-count)
            ; Match tail, then add ellipsis bindings

            (let ((tb (%sr-match tail-pat f literals bindings)))
              (if (eq? tb %sr-no-match)
                %sr-no-match
                (let add
                  ((cs collected) (bs tb))
                  (if (null? cs)
                    bs
                    (add
                      (cdr cs)
                      (pair
                        (pair (caar cs) (pair %ellipsis-sym (reverse (cdar cs))))
                        bs))))))
            ; Match next repeated element

            (let ((b (%sr-match sub-pat (car f) literals ())))
              (if (eq? b %sr-no-match)
                %sr-no-match
                (loop
                  (+ i 1)
                  (cdr f)
                  (map
                    (lambda
                      (cv)
                      (let ((found (assq (car cv) b)))
                        (if found (pair (car cv) (pair (cdr found) (cdr cv))) cv)))
                    collected)))))))))
  ; Pattern matching for syntax-rules

  ; Returns bindings alist on success, %sr-no-match on failure

  ; Ellipsis bindings stored as (pvar . (... val1 val2 ...))

  (set!
    %sr-match
    (lambda
      (pattern form literals bindings)
      (if (eq? pattern (lit _))
        bindings
        (if (symbol? pattern)
          (if (memq pattern literals)
            (if (and (symbol? form) (eq? pattern form))
              bindings
              %sr-no-match)
            (pair (pair pattern form) bindings))
          (if (null? pattern)
            (if (null? form) bindings %sr-no-match)
            (if (pair? pattern)
              ; Check for ellipsis: (sub-pat ... . tail)

              (if (and
                    (pair? (cdr pattern))
                    (eq? (cadr pattern) %ellipsis-sym))
                (%sr-ellipsis-match
                  (car pattern)
                  (cddr pattern)
                  form
                  literals
                  bindings)
                ; Normal pair matching

                (if (pair? form)
                  (let ((b (%sr-match (car pattern) (car form) literals bindings)))
                    (if (eq? b %sr-no-match)
                      %sr-no-match
                      (%sr-match (cdr pattern) (cdr form) literals b)))
                  %sr-no-match))
              (if (equal? pattern form) bindings %sr-no-match)))))))
  ; Collect non-pvar symbols from template (excludes ... marker)

  (define
    (%sr-introduced template pvars)
    (if (symbol? template)
      (if (or (memq template pvars) (eq? template %ellipsis-sym))
        ()
        (list template))
      (if (pair? template)
        (append
          (%sr-introduced (car template) pvars)
          (%sr-introduced (cdr template) pvars))
        ())))
  ; Substitute pattern variables in template

  ; Handles (tmpl ... . rest) by expanding ellipsis-bound vars

  (define
    (%sr-subst template bindings)
    (if (symbol? template)
      (let ((b (assq template bindings)))
        (if b (cdr b) template))
      (if (pair? template)
        ; Check for ellipsis: (tmpl ... . rest)

        (if (and
              (pair? (cdr template))
              (eq? (cadr template) %ellipsis-sym))
          (let*
            ((sub-tmpl (car template))
              (rest-tmpl (cddr template))
              (epvars
                (%sr-unique (%sr-ellipsis-pvars sub-tmpl bindings)))
              (count
                (if (null? epvars)
                  0
                  (length (cddr (assq (car epvars) bindings))))))
            (let loop
              ((i 0) (acc ()))
              (if (= i count)
                (append (reverse acc) (%sr-subst rest-tmpl bindings))
                (let ((slice
                        (map
                          (lambda
                            (pv)
                            (pair pv (list-ref (cddr (assq pv bindings)) i)))
                          epvars)))
                  (loop
                    (+ i 1)
                    (pair (%sr-subst sub-tmpl (append slice bindings)) acc))))))
          ; Normal pair

          (pair
            (%sr-subst (car template) bindings)
            (%sr-subst (cdr template) bindings)))
        template)))
  ; Rename symbols in template

  (define
    (%sr-rename template renames)
    (if (symbol? template)
      (let ((r (assq template renames))) (if r (cdr r) template))
      (if (pair? template)
        (pair
          (%sr-rename (car template) renames)
          (%sr-rename (cdr template) renames))
        template)))
  ; Instantiate template with bindings and hygiene

  ; 1. Find introduced symbols (in template, not pattern vars)

  ; 2. For those bound in def-env: rename to gensyms, wrap in let

  ; 3. Substitute pattern variables

  (define
    (%sr-instantiate template bindings def-env)
    (let*
      ((pvars (map car bindings))
        (introduced (%sr-unique (%sr-introduced template pvars)))
        (renames
          (let loop
            ((syms introduced) (acc ()))
            (if (null? syms)
              (reverse acc)
              (let ((v (%sr-safe-eval (car syms) def-env)))
                (if (pair? v)
                  (loop (cdr syms) (pair (pair (car syms) (cdr v)) acc))
                  (loop (cdr syms) acc))))))
        (renamed (%sr-rename template renames))
        (expanded (%sr-subst renamed bindings)))
      expanded))
  ; Try each clause, return first match's expansion

  (define
    (%sr-expand form literals clauses def-env)
    (if (null? clauses)
      (error "syntax-rules: no matching pattern")
      (let*
        ((clause (car clauses))
          (pattern (car clause))
          (template
            (if (pair? (cdr clause)) (cadr clause) (lit (begin))))
          (bindings (%sr-match (cdr pattern) (cdr form) literals ())))
        (if (eq? bindings %sr-no-match)
          (%sr-expand form literals (cdr clauses) def-env)
          (%sr-instantiate template bindings def-env)))))
  ; syntax-rules: returns a transformer fn (lexically scoped closure)

  ; Captures literals, clauses, and def-env for hygiene

  (define
    syntax-rules
    (op (literals . clauses)
      sr-env
      (fn (form) (%sr-expand form literals clauses sr-env))))
  ; define-syntax: bind name to a syntax transformer

  ; Strategy: store transformer fn under a gensym, bind name to an op

  ; that calls it. The op is dynamically scoped so it finds the gensym

  ; in the env at call time.

  (define
    define-syntax
    (op (name transformer-expr)
      e
      (def %ds-xfm (eval transformer-expr e))
      (def %ds-xfm-name
        (string->symbol
          (string-append "%xfm-" (symbol->string name))))
      (eval
        (list
          (lit begin)
          (list (lit def) %ds-xfm-name %ds-xfm)
          (list
            (lit def)
            name
            (list
              (lit op)
              (lit %sr-args)
              (lit %sr-env)
              (list
                (lit eval!)
                (list
                  %ds-xfm-name
                  (list (lit pair) (list (lit lit) name) (lit %sr-args))))))))))
  ; let-syntax: local syntax bindings

  ; Processes one binding at a time, wrapping in let + recursing

  ; Uses %ls- prefixed params to avoid shadowing by let*/let (which also

  ; use 'bindings'/'body'/'e' as op params in dynamic scope).

  (define
    let-syntax
    (op (%ls-bindings . %ls-body)
      %ls-e
      (if (null? %ls-bindings)
        (eval (pair (lit begin) %ls-body) %ls-e)
        (begin
          (def %ls-b (car %ls-bindings))
          (def %ls-name (car %ls-b))
          (def %ls-xfm (eval (cadr %ls-b) %ls-e))
          (def %ls-xfm-name
            (string->symbol
              (string-append "%xfm-" (symbol->string %ls-name))))
          (eval
            (list
              (lit begin)
              (list (lit def) %ls-xfm-name %ls-xfm)
              (list
                (lit let)
                (list
                  (list
                    %ls-name
                    (list
                      (lit op)
                      (lit %sr-args)
                      (lit %sr-env)
                      (list
                        (lit eval!)
                        (list
                          %ls-xfm-name
                          (list (lit pair) (list (lit lit) %ls-name) (lit %sr-args)))))))
                (pair (lit let-syntax) (pair (cdr %ls-bindings) %ls-body))))
            %ls-e)))))
  ; letrec-syntax: like let-syntax but transformers can see each other

  ; We achieve this by evaluating all transformers first, then binding them all

  ; Uses same strategy as define-syntax: def gensym names, then let-bind macro ops

  (define
    letrec-syntax
    (op (%lrs-bindings . %lrs-body)
      %lrs-e
      (if (null? %lrs-bindings)
        (eval (pair (lit begin) %lrs-body) %lrs-e)
        (begin
          ; Build defs + let-bindings for all transformers

          (def %lrs-defs ())
          (def %lrs-let-bindings ())
          (for-each
            (lambda
              (b)
              (def %lrs-n (car b))
              (def %lrs-xfm (eval (cadr b) %lrs-e))
              (def %lrs-xn
                (string->symbol
                  (string-append "%xfm-" (symbol->string %lrs-n))))
              (set!
                %lrs-defs
                (cons (list (lit def) %lrs-xn %lrs-xfm) %lrs-defs))
              (set!
                %lrs-let-bindings
                (cons
                  (list
                    %lrs-n
                    (list
                      (lit op)
                      (lit %sr-args)
                      (lit %sr-env)
                      (list
                        (lit eval)
                        (list
                          %lrs-xn
                          (list (lit pair) (list (lit lit) %lrs-n) (lit %sr-args)))
                        (lit %sr-env))))
                  %lrs-let-bindings)))
            %lrs-bindings)
          (eval
            (append
              (list (lit begin))
              (reverse %lrs-defs)
              (list
                (pair
                  (lit let)
                  (pair (reverse %lrs-let-bindings) %lrs-body))))
            %lrs-e))))))

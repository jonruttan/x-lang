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
  (def #t t)
  (def #f ())
  (def else t)

  ; --- Float support ---
  (include "lib/x/float.x")

  ; --- write-char / newline ---
  (def write-char (fn (c) (display (make-string 1 c))))

  ; --- define: (define x val) or (define (f args...) body...) ---
  (def define (op (name-or-form . body) e
    (if (pair? name-or-form)
      (eval (list (lit def) (first name-or-form)
                  (pair (lit fn) (pair (rest name-or-form) body))))
      (eval (list (lit def) name-or-form (first body))))))

  ; --- Conditional forms ---
  (def when (op (test . body) e
    (if (eval test e)
      (eval (pair (lit do) body) e))))

  (def unless (op (test . body) e
    (if (not (eval test e))
      (eval (pair (lit do) body) e))))

  ; --- let* ---
  (def let* (op (bindings . body) e
    (if (null? bindings)
      (eval (pair (lit do) body) e)
      (eval (list (lit let) (list (first bindings))
                  (pair (lit let*) (pair (rest bindings) body))) e))))

  ; --- Mutation ---
  (define (vector-set! v i val)
    (let loop ((lst (first v)) (n i))
      (if (= n 0)
        (set-first lst val)
        (loop (rest lst) (- n 1)))))

  ; --- Composition accessors ---
  (define (caar x) (first (first x)))
  (define (cadr x) (first (rest x)))
  (define (cdar x) (rest (first x)))
  (define (cddr x) (rest (rest x)))
  (define (caaar x) (first (first (first x))))
  (define (caadr x) (first (first (rest x))))
  (define (caddr x) (first (rest (rest x))))
  (define (cdddr x) (rest (rest (rest x))))

  ; --- Scheme list aliases (x.x provides the implementations) ---
  (define (list-ref lst n) (nth n lst))
  (define (list-tail lst n) (drop n lst))

  ; --- Scheme-specific list operations ---
  (define (member x lst)
    (match
      ((null? lst) #f)
      ((equal? x (first lst)) lst)
      (t (member x (rest lst)))))

  (define (assoc key alist)
    (match
      ((null? alist) #f)
      ((equal? key (caar alist)) (first alist))
      (t (assoc key (rest alist)))))

  ; --- String operations (R5RS aliases) ---
  (define (string-copy s) (substring s 0 (string-length s)))

  ; --- letrec ---
  (def letrec (op (bindings . body) e
    (eval (pair (lit let)
      (pair (map (lambda (b) (list (first b) ())) bindings)
        (append (map (lambda (b) (list (lit set!) (first b) (cadr b))) bindings)
                body)))
      e)))

  ; --- Named let ---
  (def %let let)
  (def let (op (first-arg . rest-args) e
    (if (symbol? first-arg)
      (eval (list (lit letrec)
                  (list (list first-arg (pair (lit lambda)
                    (pair (map car (first rest-args)) (rest rest-args)))))
                  (pair first-arg (map cadr (first rest-args))))
            e)
      (eval (pair (lit %let) (pair first-arg rest-args)) e))))

  ; --- do ---
  ; (do ((var init step) ...) (test expr ...) command ...)
  (define do
    (op (bindings test-and-result . body) env
      (let ((vars (map car bindings))
            (inits (map (lambda (b) (list-ref b 1)) bindings))
            (steps (map (lambda (b)
                          (if (> (length b) 2) (list-ref b 2) (car b)))
                        bindings))
            (test (car test-and-result))
            (result (cdr test-and-result)))
        (eval
          (cons (list (lit lambda) ()
            (cons (lit letrec)
              (cons (list (list (lit %do-loop) (cons (lit lambda) (cons vars
                (list (list (lit if) test
                  (if (null? result) (list (lit if) #f #f) (cons (lit begin) result))
                  (append (cons (lit begin) body) (list (cons (lit %do-loop) steps)))))))))
                (list (cons (lit %do-loop) inits)))))
            ())
          env))))

  ; --- Override forms that used (lit do) to use (lit begin) instead ---
  ; (do was just redefined as the R5RS iteration form)
  (define when (op (test . body) e
    (if (eval test e)
      (eval (pair (lit begin) body) e))))
  (define unless (op (test . body) e
    (if (not (eval test e))
      (eval (pair (lit begin) body) e))))
  (define let* (op (bindings . body) e
    (if (null? bindings)
      (eval (pair (lit begin) body) e)
      (eval (list (lit let) (list (first bindings))
                  (pair (lit let*) (pair (rest bindings) body))) e))))

  ; --- R5RS cond (multi-expression clause bodies + => syntax) ---
  (define cond (op clauses e
    (let %cond-loop ((cls clauses))
      (if (null? cls) ()
        (let ((clause (first cls)))
          (if (eq? (first clause) (lit else))
            (eval (pair (lit begin) (rest clause)) e)
            (let ((test-val (eval (first clause) e)))
              (if test-val
                (if (and (pair? (rest clause))
                         (eq? (cadr clause) (lit =>)))
                  ((eval (caddr clause) e) test-val)
                  (eval (pair (lit begin) (rest clause)) e))
                (%cond-loop (rest cls))))))))))

  ; --- Promises ---
  (define %promise (make-type (lit PROMISE)
    (list
      (pair (lit write) (lambda (self) (display "#<promise>"))))))
  (define (promise? x) (type? x %promise))

  (define delay
    (op (expr) env
      (let ((forced #f) (result #f))
        (make-instance %promise
          (lambda ()
            (if forced result
              (let ((val (eval expr env)))
                (set! forced #t)
                (set! result val)
                val)))))))

  (define (force p)
    (if (promise? p) ((first p)) p))

  ; --- case (multi-expression clause bodies) ---
  (def case (op (key . clauses) e
    (def case-val (eval key e))
    (def case-match? (fn (datum)
      (if (number? case-val) (= case-val datum) (eq? case-val datum))))
    (def case-check-datums (fn (datums)
      (match
        ((null? datums) ())
        ((case-match? (first datums)) t)
        (t (case-check-datums (rest datums))))))
    (def case-loop (fn (cls)
      (match
        ((null? cls) ())
        ((or (eq? (first (first cls)) (lit else))
             (case-check-datums (first (first cls))))
          (eval (pair (lit begin) (rest (first cls))) e))
        (t (case-loop (rest cls))))))
    (case-loop clauses)))

  ; --- Deep structural equality (override x-lib equal? for pairs/vectors) ---
  (define (equal? a b)
    (cond ((and (pair? a) (pair? b))
           (and (equal? (car a) (car b)) (equal? (cdr a) (cdr b))))
          ((and (vector? a) (vector? b))
           (equal? (vector->list a) (vector->list b)))
          ((and (number? a) (number? b)) (= a b))
          ((and (string? a) (string? b)) (string=? a b))
          ((and (char? a) (char? b)) (= (char->integer a) (char->integer b)))
          (#t (eq? a b))))

  ; --- Equivalence (identity for pairs/procs, = for numbers/chars) ---
  (define (eqv? a b)
    (cond ((and (number? a) (number? b)) (= a b))
          ((and (char? a) (char? b)) (= (char->integer a) (char->integer b)))
          (#t (eq? a b))))

  ; --- List predicate ---
  (define (list? x)
    (if (null? x) #t
      (if (pair? x) (list? (cdr x)) #f)))

  ; --- Membership with eq? ---
  (define (memq x lst)
    (cond ((null? lst) #f)
          ((eq? x (car lst)) lst)
          (#t (memq x (cdr lst)))))

  ; --- Membership with eqv? ---
  (define (memv x lst)
    (cond ((null? lst) #f)
          ((eqv? x (car lst)) lst)
          (#t (memv x (cdr lst)))))

  ; --- Membership with equal? (redefined to use deep equal?) ---
  (define (member x lst)
    (cond ((null? lst) #f)
          ((equal? x (car lst)) lst)
          (#t (member x (cdr lst)))))

  ; --- Association with eq? ---
  (define (assq key alist)
    (cond ((null? alist) #f)
          ((eq? key (caar alist)) (car alist))
          (#t (assq key (cdr alist)))))

  ; --- Association with eqv? ---
  (define (assv key alist)
    (cond ((null? alist) #f)
          ((eqv? key (caar alist)) (car alist))
          (#t (assv key (cdr alist)))))

  ; --- Association with equal? (redefined to use deep equal?) ---
  (define (assoc key alist)
    (cond ((null? alist) #f)
          ((equal? key (caar alist)) (car alist))
          (#t (assoc key (cdr alist)))))

  ; --- Character comparisons ---
  (define (char=? a b) (= (char->integer a) (char->integer b)))
  (define (char<? a b) (< (char->integer a) (char->integer b)))
  (define (char>? a b) (> (char->integer a) (char->integer b)))
  (define (char<=? a b) (<= (char->integer a) (char->integer b)))
  (define (char>=? a b) (>= (char->integer a) (char->integer b)))

  ; --- String ordering ---
  (define (string<? a b)
    (let loop ((i 0))
      (cond ((= i (string-length a)) (< i (string-length b)))
            ((= i (string-length b)) #f)
            ((char<? (string-ref a i) (string-ref b i)) #t)
            ((char>? (string-ref a i) (string-ref b i)) #f)
            (#t (loop (+ i 1))))))
  (define (string>? a b) (string<? b a))
  (define (string<=? a b) (not (string>? a b)))
  (define (string>=? a b) (not (string<? a b)))

  ; --- Math ---
  (define (quotient a b) (/ a b))
  (define (remainder a b) (- a (* b (quotient a b))))
  (define (modulo a b)
    (let ((r (remainder a b)))
      (if (zero? r) r
        (if (if (> b 0) (< r 0) (> r 0))
          (+ r b)
          r))))
  ; gcd, lcm, expt defined below as variadic/float-aware

  ; --- String to list ---
  (define (string->list s)
    (let loop ((i (- (string-length s) 1)) (acc ()))
      (if (< i 0) acc (loop (- i 1) (cons (string-ref s i) acc)))))

  ; --- String constructor ---
  (define (string . chars) (list->string chars))

  ; --- Variadic string-append (R5RS: takes any number of args) ---
  (define %string-append-2 string-append)
  (define (string-append . args)
    (if (null? args) ""
      (let loop ((rest (cdr args)) (acc (car args)))
        (if (null? rest) acc
          (loop (cdr rest) (%string-append-2 acc (car rest)))))))

  ; --- Number type predicates ---
  (define (integer? x)
    (cond ((%int-number? x) #t)
          ((float? x) (= x (ftrunc x)))
          (#t #f)))
  (define (exact? x) (%int-number? x))
  (define (inexact? x) (float? x))
  (define (exact-integer? x) (%int-number? x))
  (define (rational? x) (%int-number? x))
  (define (real? x) (number? x))
  (define (complex? x) (number? x))

  ; --- Variadic comparisons ---
  ; Save binary float-aware versions before redefining as variadic
  (define %bin= =)
  (define %bin< <)
  (define (= . args)
    (if (null? (cdr args)) #t
      (let loop ((a (car args)) (rest (cdr args)))
        (if (null? rest) #t
          (if (%bin= a (car rest))
            (loop (car rest) (cdr rest))
            #f)))))
  (define (< . args)
    (if (null? (cdr args)) #t
      (let loop ((a (car args)) (rest (cdr args)))
        (if (null? rest) #t
          (if (%bin< a (car rest))
            (loop (car rest) (cdr rest))
            #f)))))
  (define (> . args)
    (if (null? (cdr args)) #t
      (let loop ((a (car args)) (rest (cdr args)))
        (if (null? rest) #t
          (if (%bin< (car rest) a)
            (loop (car rest) (cdr rest))
            #f)))))
  (define (<= . args)
    (if (null? (cdr args)) #t
      (let loop ((a (car args)) (rest (cdr args)))
        (if (null? rest) #t
          (if (not (%bin< (car rest) a))
            (loop (car rest) (cdr rest))
            #f)))))
  (define (>= . args)
    (if (null? (cdr args)) #t
      (let loop ((a (car args)) (rest (cdr args)))
        (if (null? rest) #t
          (if (not (%bin< a (car rest)))
            (loop (car rest) (cdr rest))
            #f)))))

  ; --- Variadic min/max ---
  (define (min . args)
    (let loop ((best (car args)) (rest (cdr args)))
      (if (null? rest) best
        (loop (if (< (car rest) best) (car rest) best) (cdr rest)))))
  (define (max . args)
    (let loop ((best (car args)) (rest (cdr args)))
      (if (null? rest) best
        (loop (if (> (car rest) best) (car rest) best) (cdr rest)))))

  ; --- Variadic gcd/lcm ---
  (define (%gcd2 a b) (if (zero? b) a (%gcd2 b (remainder a b))))
  (define (gcd . args)
    (if (null? args) 0
      (let loop ((acc (abs (car args))) (rest (cdr args)))
        (if (null? rest) acc
          (loop (%gcd2 acc (abs (car rest))) (cdr rest))))))
  (define (%lcm2 a b)
    (if (zero? b) 0
      (abs (* (quotient a (%gcd2 a b)) b))))
  (define (lcm . args)
    (if (null? args) 1
      (let loop ((acc (abs (car args))) (rest (cdr args)))
        (if (null? rest) acc
          (loop (%lcm2 acc (abs (car rest))) (cdr rest))))))

  ; --- R5RS math with float support ---
  (define (floor x)
    (if (float? x) (inexact->exact (ffloor x)) x))
  (define (ceiling x)
    (if (float? x) (inexact->exact (fceil x)) x))
  (define (truncate x)
    (if (float? x) (inexact->exact (ftrunc x)) x))
  (define (round x)
    (if (float? x) (inexact->exact (frint x)) x))
  (define (sqrt x)
    (if (and (%int-number? x) (>= x 0))
      (let ((s (inexact->exact (fsqrt (exact->inexact x)))))
        (if (= (* s s) x) s (fsqrt (exact->inexact x))))
      (fsqrt (if (float? x) x (exact->inexact x)))))
  (define sin (lambda (x) (fsin (if (float? x) x (exact->inexact x)))))
  (define cos (lambda (x) (fcos (if (float? x) x (exact->inexact x)))))
  (define tan (lambda (x) (ftan (if (float? x) x (exact->inexact x)))))
  (define asin (lambda (x) (fasin (if (float? x) x (exact->inexact x)))))
  (define acos (lambda (x) (facos (if (float? x) x (exact->inexact x)))))
  (define atan (lambda (x . rest)
    (if (null? rest)
      (fatan (if (float? x) x (exact->inexact x)))
      (fatan2 (if (float? x) x (exact->inexact x))
              (if (float? (car rest)) (car rest) (exact->inexact (car rest)))))))
  (define (exp x) (fexp (if (float? x) x (exact->inexact x))))
  (define (log x) (flog (if (float? x) x (exact->inexact x))))

  ; --- Generic number->string / string->number ---
  (define %int-number->string number->string)
  (define %int-string->number string->number)

  (define (number->string n . radix)
    (if (float? n)
      (float->string (first n))
      (if (null? radix)
        (%int-number->string n)
        (%int-number->string n (car radix)))))

  (define (string->number s . radix)
    (if (null? radix)
      (let ((has-dot (let loop ((i 0))
                       (cond ((= i (string-length s)) #f)
                             ((char=? (string-ref s i) #\.) #t)
                             (#t (loop (+ i 1)))))))
        (if has-dot
          (make-instance %float (string->float s))
          (%int-string->number s)))
      (%int-string->number s (car radix))))

  ; --- Generic expt (supports float exponents) ---
  (define (expt base exp)
    (cond ((and (%int-number? base) (%int-number? exp) (>= exp 0))
           (cond ((zero? exp) 1)
                 ((even? exp) (expt (* base base) (quotient exp 2)))
                 (#t (* base (expt base (- exp 1))))))
          (#t (fpow (if (float? base) base (exact->inexact base))
                    (if (float? exp) exp (exact->inexact exp))))))

  ; --- Multiple values ---
  (define %values (make-type (lit VALUES)
    (list
      (pair (lit write) (lambda (self)
        (for-each (lambda (v) (display " ") (write v))
                  (first self)))))))
  (define (values . args)
    (if (= (length args) 1) (car args)
      (make-instance %values args)))
  (define (call-with-values producer consumer)
    (let ((result (producer)))
      (if (type? result %values)
        (apply consumer (first result))
        (consumer result))))

  ; --- Character classification ---
  (define (char-alphabetic? c)
    (let ((n (char->integer c)))
      (or (and (>= n 65) (<= n 90))
          (and (>= n 97) (<= n 122)))))

  (define (char-numeric? c)
    (let ((n (char->integer c)))
      (and (>= n 48) (<= n 57))))

  (define (char-whitespace? c)
    (let ((n (char->integer c)))
      (or (= n 32) (= n 9) (= n 10) (= n 13) (= n 12))))

  (define (char-upper-case? c)
    (let ((n (char->integer c)))
      (and (>= n 65) (<= n 90))))

  (define (char-lower-case? c)
    (let ((n (char->integer c)))
      (and (>= n 97) (<= n 122))))

  ; --- Character case conversion ---
  (define (char-upcase c)
    (if (char-lower-case? c)
      (integer->char (- (char->integer c) 32))
      c))

  (define (char-downcase c)
    (if (char-upper-case? c)
      (integer->char (+ (char->integer c) 32))
      c))

  ; --- Case-insensitive character comparison ---
  (define (char-ci=? a b) (char=? (char-downcase a) (char-downcase b)))
  (define (char-ci<? a b) (char<? (char-downcase a) (char-downcase b)))
  (define (char-ci>? a b) (char>? (char-downcase a) (char-downcase b)))
  (define (char-ci<=? a b) (char<=? (char-downcase a) (char-downcase b)))
  (define (char-ci>=? a b) (char>=? (char-downcase a) (char-downcase b)))

  ; --- Case-insensitive string comparison ---
  (define (%string-downcase s)
    (list->string (map char-downcase (string->list s))))

  (define (string-ci=? a b) (string=? (%string-downcase a) (%string-downcase b)))
  (define (string-ci<? a b) (string<? (%string-downcase a) (%string-downcase b)))
  (define (string-ci>? a b) (string>? (%string-downcase a) (%string-downcase b)))
  (define (string-ci<=? a b) (string<=? (%string-downcase a) (%string-downcase b)))
  (define (string-ci>=? a b) (string>=? (%string-downcase a) (%string-downcase b)))

  ; --- Quote shorthand: 'expr -> (lit expr) ---

  (def %quote-reader (fn args
    (pair (lit lit) (pair (read) ()))))

  (make-type "QUOTE"
    (list
      (pair (lit analyse) (fn (buffer score chr)
        (if (= chr (char->integer #\'))
          (score-set score 1 buffer)
          ())))
      (pair (lit read) %quote-reader)
      (pair (lit delimit) (fn (buffer score chr)
        (if (= chr (char->integer #\'))
          (%seq (buffer-unread buffer) buffer)
          ())))))

  ; --- Quasiquote shorthand: `expr -> (quasiquote expr) ---

  (def %quasiquote-reader (fn args
    (pair (lit quasiquote) (pair (read) ()))))

  (make-type "QUASIQUOTE"
    (list
      (pair (lit analyse) (fn (buffer score chr)
        (if (= chr (char->integer #\`))
          (score-set score 1 buffer)
          ())))
      (pair (lit read) %quasiquote-reader)
      (pair (lit delimit) (fn (buffer score chr)
        (if (= chr (char->integer #\`))
          (%seq (buffer-unread buffer) buffer)
          ())))))

  ; --- Unquote shorthand: ,expr -> (unquote expr)
  ;                         ,@expr -> (unquote-splicing expr) ---

  (def %unquote-reader (fn args
    (pair (lit unquote) (pair (read) ()))))

  (def %unquote-splicing-reader (fn args
    (pair (lit unquote-splicing) (pair (read) ()))))

  (make-type "UNQUOTE"
    (list
      (pair (lit analyse) (fn (buffer score chr)
        (if (= chr (char->integer #\,))
          (score-set score 1 buffer)
          ())))
      (pair (lit read) %unquote-reader)
      (pair (lit delimit) (fn (buffer score chr)
        (if (= chr (char->integer #\,))
          (%seq (buffer-unread buffer) buffer)
          ())))))

  (make-type "UNQUOTE-SPLICING"
    (list
      (pair (lit analyse) (fn (buffer score chr)
        (if (= chr (char->integer #\,))
          (fn (buffer score chr)
            (if (= chr (char->integer #\@))
              (score-set score 1 buffer)
              ()))
          ())))
      (pair (lit read) %unquote-splicing-reader)
      (pair (lit delimit) (fn (buffer score chr)
        (if (= chr (char->integer #\,))
          (%seq (buffer-unread buffer) buffer)
          ())))))

  ; --- Ellipsis tokenizer type ---
  ; Register '...' as a token so it parses as a symbol, not as dot-pair
  (define %ellipsis-sym (string->symbol "..."))

  ; State machine: dot1 → dot2 → dot3 → lookahead check
  (define %ellipsis-check (lambda (buffer score chr)
    (if (= chr 46)
      ()
      (%seq (buffer-unread buffer) (score-set score 1 buffer)))))

  (define %ellipsis-dot3 (lambda (buffer score chr)
    (if (= chr 46)
      (%seq (score-set score 1 buffer) %ellipsis-check)
      ())))

  (define %ellipsis-dot2 (lambda (buffer score chr)
    (if (= chr 46) %ellipsis-dot3 ())))

  (make-type "ELLIPSIS"
    (list
      (pair (lit analyse) (lambda (buffer score chr)
        (if (= chr 46) %ellipsis-dot2 ())))
      (pair (lit read) (lambda args %ellipsis-sym))))

  ; --- Hygienic Macros (define-syntax, syntax-rules, let-syntax) ---

  ; Gensym: generate unique symbols for hygiene
  (define %gensym-counter 0)
  (define (gensym)
    (set! %gensym-counter (+ %gensym-counter 1))
    (string->symbol (string-append "%g" (number->string %gensym-counter))))

  ; Safe eval: returns (t . value) if bound, () if unbound
  (define (%sr-safe-eval sym env)
    (guard (e ()) (pair (lit t) (eval sym env))))

  ; Sentinel for pattern match failure (unique identity)
  (define %sr-no-match (pair (lit no) (lit match)))

  ; Remove duplicates (eq?)
  (define (%sr-unique lst)
    (let loop ((in lst) (out ()))
      (if (null? in)
        (reverse out)
        (if (memq (car in) out)
          (loop (cdr in) out)
          (loop (cdr in) (pair (car in) out))))))

  ; --- Ellipsis helpers ---

  ; Count fixed elements in a pattern tail (after ...)
  (define (%sr-tail-length pat)
    (if (pair? pat) (+ 1 (%sr-tail-length (cdr pat))) 0))

  ; Collect pattern variable names from a sub-pattern
  (define (%sr-pattern-pvars pat literals)
    (if (symbol? pat)
      (if (or (eq? pat (lit _)) (memq pat literals)) () (list pat))
      (if (pair? pat)
        (append (%sr-pattern-pvars (car pat) literals)
                (%sr-pattern-pvars (cdr pat) literals))
        ())))

  ; Find pvars in template that have ellipsis bindings
  (define (%sr-ellipsis-pvars template bindings)
    (if (symbol? template)
      (let ((b (assq template bindings)))
        (if (and b (pair? (cdr b)) (eq? (cadr b) %ellipsis-sym))
          (list template)
          ()))
      (if (pair? template)
        (append (%sr-ellipsis-pvars (car template) bindings)
                (%sr-ellipsis-pvars (cdr template) bindings))
        ())))

  ; Forward declaration for mutual recursion
  (define %sr-match ())

  ; Match (sub-pat ... . tail-pat) against form list
  (define (%sr-ellipsis-match sub-pat tail-pat form literals bindings)
    (let* ((pvars (%sr-unique (%sr-pattern-pvars sub-pat literals)))
           (tail-len (%sr-tail-length tail-pat))
           (form-len (length form))
           (rep-count (- form-len tail-len)))
      (if (< rep-count 0)
        %sr-no-match
        (let loop ((i 0) (f form)
                   (collected (map (lambda (v) (list v)) pvars)))
          (if (= i rep-count)
            ; Match tail, then add ellipsis bindings
            (let ((tb (%sr-match tail-pat f literals bindings)))
              (if (eq? tb %sr-no-match)
                %sr-no-match
                (let add ((cs collected) (bs tb))
                  (if (null? cs)
                    bs
                    (add (cdr cs)
                      (pair (pair (caar cs)
                                  (pair %ellipsis-sym (reverse (cdar cs))))
                            bs))))))
            ; Match next repeated element
            (let ((b (%sr-match sub-pat (car f) literals ())))
              (if (eq? b %sr-no-match)
                %sr-no-match
                (loop (+ i 1) (cdr f)
                  (map (lambda (cv)
                         (let ((found (assq (car cv) b)))
                           (if found
                             (pair (car cv) (pair (cdr found) (cdr cv)))
                             cv)))
                       collected)))))))))

  ; Pattern matching for syntax-rules
  ; Returns bindings alist on success, %sr-no-match on failure
  ; Ellipsis bindings stored as (pvar . (... val1 val2 ...))
  (set! %sr-match (lambda (pattern form literals bindings)
    (if (eq? pattern (lit _))
      bindings
      (if (symbol? pattern)
        (if (memq pattern literals)
          (if (and (symbol? form) (eq? pattern form)) bindings %sr-no-match)
          (pair (pair pattern form) bindings))
        (if (null? pattern)
          (if (null? form) bindings %sr-no-match)
          (if (pair? pattern)
            ; Check for ellipsis: (sub-pat ... . tail)
            (if (and (pair? (cdr pattern)) (eq? (cadr pattern) %ellipsis-sym))
              (%sr-ellipsis-match (car pattern) (cddr pattern) form literals bindings)
              ; Normal pair matching
              (if (pair? form)
                (let ((b (%sr-match (car pattern) (car form) literals bindings)))
                  (if (eq? b %sr-no-match)
                    %sr-no-match
                    (%sr-match (cdr pattern) (cdr form) literals b)))
                %sr-no-match))
            (if (equal? pattern form) bindings %sr-no-match)))))))

  ; Collect non-pvar symbols from template (excludes ... marker)
  (define (%sr-introduced template pvars)
    (if (symbol? template)
      (if (or (memq template pvars) (eq? template %ellipsis-sym))
        () (list template))
      (if (pair? template)
        (append (%sr-introduced (car template) pvars)
                (%sr-introduced (cdr template) pvars))
        ())))

  ; Substitute pattern variables in template
  ; Handles (tmpl ... . rest) by expanding ellipsis-bound vars
  (define (%sr-subst template bindings)
    (if (symbol? template)
      (let ((b (assq template bindings)))
        (if b (cdr b) template))
      (if (pair? template)
        ; Check for ellipsis: (tmpl ... . rest)
        (if (and (pair? (cdr template)) (eq? (cadr template) %ellipsis-sym))
          (let* ((sub-tmpl (car template))
                 (rest-tmpl (cddr template))
                 (epvars (%sr-unique (%sr-ellipsis-pvars sub-tmpl bindings)))
                 (count (if (null? epvars) 0
                           (length (cddr (assq (car epvars) bindings))))))
            (let loop ((i 0) (acc ()))
              (if (= i count)
                (append (reverse acc) (%sr-subst rest-tmpl bindings))
                (let ((slice (map (lambda (pv)
                                    (pair pv (list-ref (cddr (assq pv bindings)) i)))
                                  epvars)))
                  (loop (+ i 1)
                    (pair (%sr-subst sub-tmpl (append slice bindings))
                          acc))))))
          ; Normal pair
          (pair (%sr-subst (car template) bindings)
                (%sr-subst (cdr template) bindings)))
        template)))

  ; Rename symbols in template
  (define (%sr-rename template renames)
    (if (symbol? template)
      (let ((r (assq template renames)))
        (if r (cdr r) template))
      (if (pair? template)
        (pair (%sr-rename (car template) renames)
              (%sr-rename (cdr template) renames))
        template)))

  ; Instantiate template with bindings and hygiene
  ; 1. Find introduced symbols (in template, not pattern vars)
  ; 2. For those bound in def-env: rename to gensyms, wrap in let
  ; 3. Substitute pattern variables
  (define (%sr-instantiate template bindings def-env)
    (let* ((pvars (map car bindings))
           (introduced (%sr-unique (%sr-introduced template pvars)))
           (rn-lets
             (let loop ((syms introduced) (renames ()) (lets ()))
               (if (null? syms)
                 (pair renames lets)
                 (let ((v (%sr-safe-eval (car syms) def-env)))
                   (if (pair? v)
                     (let ((g (gensym)))
                       (loop (cdr syms)
                             (pair (pair (car syms) g) renames)
                             (pair (list g (cdr v)) lets)))
                     (loop (cdr syms) renames lets))))))
           (renames (car rn-lets))
           (lets (cdr rn-lets))
           (renamed (%sr-rename template renames))
           (expanded (%sr-subst renamed bindings)))
      (if (null? lets)
        expanded
        (list (lit let) lets expanded))))

  ; Try each clause, return first match's expansion
  (define (%sr-expand form literals clauses def-env)
    (if (null? clauses)
      (error "syntax-rules: no matching pattern")
      (let* ((clause (car clauses))
             (pattern (car clause))
             (template (if (pair? (cdr clause)) (cadr clause) (lit (begin))))
             (bindings (%sr-match (cdr pattern) (cdr form) literals ())))
        (if (eq? bindings %sr-no-match)
          (%sr-expand form literals (cdr clauses) def-env)
          (%sr-instantiate template bindings def-env)))))

  ; syntax-rules: returns a transformer fn (lexically scoped closure)
  ; Captures literals, clauses, and def-env for hygiene
  (define syntax-rules
    (op (literals . clauses) sr-env
      (fn (form)
        (%sr-expand form literals clauses sr-env))))

  ; define-syntax: bind name to a syntax transformer
  ; Strategy: store transformer fn under a gensym, bind name to an op
  ; that calls it. The op is dynamically scoped so it finds the gensym
  ; in the env at call time.
  (define define-syntax
    (op (name transformer-expr) e
      (def %ds-xfm (eval transformer-expr e))
      (def %ds-xfm-name (string->symbol (string-append "%xfm-" (symbol->string name))))
      (eval (list (lit begin)
        (list (lit def) %ds-xfm-name %ds-xfm)
        (list (lit def) name
          (list (lit op) (lit %sr-args) (lit %sr-env)
            (list (lit eval)
              (list %ds-xfm-name
                (list (lit pair) (list (lit lit) name) (lit %sr-args)))
              (lit %sr-env))))))))

  ; let-syntax: local syntax bindings
  ; Processes one binding at a time, wrapping in let + recursing
  ; Uses %ls- prefixed params to avoid shadowing by let*/let (which also
  ; use 'bindings'/'body'/'e' as op params in dynamic scope).
  (define let-syntax
    (op (%ls-bindings . %ls-body) %ls-e
      (if (null? %ls-bindings)
        (eval (pair (lit begin) %ls-body) %ls-e)
        (begin
          (def %ls-b (car %ls-bindings))
          (def %ls-name (car %ls-b))
          (def %ls-xfm (eval (cadr %ls-b) %ls-e))
          (def %ls-xfm-name (string->symbol (string-append "%xfm-" (symbol->string %ls-name))))
          (eval (list (lit begin)
            (list (lit def) %ls-xfm-name %ls-xfm)
            (list (lit let)
              (list (list %ls-name
                (list (lit op) (lit %sr-args) (lit %sr-env)
                  (list (lit eval)
                    (list %ls-xfm-name
                      (list (lit pair) (list (lit lit) %ls-name) (lit %sr-args)))
                    (lit %sr-env)))))
              (pair (lit let-syntax) (pair (cdr %ls-bindings) %ls-body))))
            %ls-e)))))

  ; letrec-syntax: like let-syntax but transformers can see each other
  ; We achieve this by evaluating all transformers first, then binding them all
  ; Uses same strategy as define-syntax: def gensym names, then let-bind macro ops
  (define letrec-syntax
    (op (%lrs-bindings . %lrs-body) %lrs-e
      (if (null? %lrs-bindings)
        (eval (pair (lit begin) %lrs-body) %lrs-e)
        (begin
          ; Build defs + let-bindings for all transformers
          (def %lrs-defs ())
          (def %lrs-let-bindings ())
          (for-each (lambda (b)
            (def %lrs-n (car b))
            (def %lrs-xfm (eval (cadr b) %lrs-e))
            (def %lrs-xn (string->symbol (string-append "%xfm-" (symbol->string %lrs-n))))
            (set! %lrs-defs (cons (list (lit def) %lrs-xn %lrs-xfm) %lrs-defs))
            (set! %lrs-let-bindings
              (cons (list %lrs-n
                      (list (lit op) (lit %sr-args) (lit %sr-env)
                        (list (lit eval)
                          (list %lrs-xn
                            (list (lit pair) (list (lit lit) %lrs-n) (lit %sr-args)))
                          (lit %sr-env))))
                    %lrs-let-bindings)))
            %lrs-bindings)
          (eval (append (list (lit begin))
                        (reverse %lrs-defs)
                        (list (pair (lit let) (pair (reverse %lrs-let-bindings) %lrs-body))))
                %lrs-e)))))

)

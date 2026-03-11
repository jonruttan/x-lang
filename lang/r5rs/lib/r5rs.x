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
(do
  (include "lib/x-core.x")

  ; --- Aliases ---
  (def lambda fn)
  (def begin do)
  (def set! set)
  (def modulo %)
  (def cons pair)
  (def car first)
  (def cdr rest)
  (def quote lit)
  (def quasiquote quasi)
  (def cond match)

  ; --- Boolean constants ---
  (def #t t)
  (def #f ())
  (def else t)

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

  ; --- R5RS cond (multi-expression clause bodies) ---
  (define cond (op clauses e
    (let %cond-loop ((cls clauses))
      (if (null? cls) ()
        (let ((clause (first cls)))
          (if (or (eq? (first clause) (lit else))
                  (eval (first clause) e))
            (eval (pair (lit begin) (rest clause)) e)
            (%cond-loop (rest cls))))))))

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

  ; --- case ---
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
          (eval (cadr (first cls)) e))
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
  (define (gcd a b) (if (zero? b) (abs a) (gcd b (remainder a b))))
  (define (lcm a b) (if (or (zero? a) (zero? b)) 0
    (abs (* (quotient a (gcd a b)) b))))
  (define (expt base exp)
    (cond ((zero? exp) 1)
          ((even? exp) (expt (* base base) (quotient exp 2)))
          (#t (* base (expt base (- exp 1))))))

  ; --- String to list ---
  (define (string->list s)
    (let loop ((i (- (string-length s) 1)) (acc ()))
      (if (< i 0) acc (loop (- i 1) (cons (string-ref s i) acc)))))

  ; --- String constructor ---
  (define (string . chars) (list->string chars))

  ; --- Quote shorthand: 'expr -> (lit expr) ---

  (def %quote-reader (fn args
    (pair (lit lit) (pair (read) ()))))

  (make-type "QUOTE"
    (list
      (pair (lit analyse) (fn (buffer score chr)
        (if (= chr (char->integer #\'))
          (score-set score 1 buffer %quote-reader)
          ())))
      (pair (lit delimit) (fn (buffer score chr)
        (if (= chr (char->integer #\'))
          (do (buffer-unread buffer) buffer)
          ())))))

  ; --- Quasiquote shorthand: `expr -> (quasiquote expr) ---

  (def %quasiquote-reader (fn args
    (pair (lit quasiquote) (pair (read) ()))))

  (make-type "QUASIQUOTE"
    (list
      (pair (lit analyse) (fn (buffer score chr)
        (if (= chr (char->integer #\`))
          (score-set score 1 buffer %quasiquote-reader)
          ())))
      (pair (lit delimit) (fn (buffer score chr)
        (if (= chr (char->integer #\`))
          (do (buffer-unread buffer) buffer)
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
          (fn (buffer score chr)
            (if (= chr (char->integer #\@))
              (score-set score 1 buffer %unquote-splicing-reader)
              (do (buffer-unread buffer) (score-set score 1 buffer %unquote-reader))))
          ())))
      (pair (lit delimit) (fn (buffer score chr)
        (if (= chr (char->integer #\,))
          (do (buffer-unread buffer) buffer)
          ())))))

  (repl)
)

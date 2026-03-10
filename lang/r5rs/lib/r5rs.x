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

  ; --- Deep structural equality (override x-lib equal? for pairs) ---
  (define (equal? a b)
    (cond ((and (pair? a) (pair? b))
           (and (equal? (car a) (car b)) (equal? (cdr a) (cdr b))))
          ((and (number? a) (number? b)) (= a b))
          ((and (string? a) (string? b)) (string=? a b))
          ((and (char? a) (char? b)) (= (char->integer a) (char->integer b)))
          (#t (eq? a b))))

  ; --- Equivalence ---
  (define (eqv? a b) (equal? a b))

  ; --- List predicate ---
  (define (list? x)
    (if (null? x) #t
      (if (pair? x) (list? (cdr x)) #f)))

  ; --- Membership with eq? ---
  (define (memq x lst)
    (cond ((null? lst) #f)
          ((eq? x (car lst)) lst)
          (#t (memq x (cdr lst)))))
  (define (memv x lst) (memq x lst))

  ; --- Association with eq? ---
  (define (assq key alist)
    (cond ((null? alist) #f)
          ((eq? key (caar alist)) (car alist))
          (#t (assq key (cdr alist)))))
  (define (assv key alist) (assq key alist))

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

  (lit r5rs)
)

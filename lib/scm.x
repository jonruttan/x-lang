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
  ; Uses plain eval (no env arg) so def extends the current env persistently.
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

  ; --- Number predicates ---
  (define (zero? n) (= n 0))
  (define (positive? n) (> n 0))
  (define (negative? n) (< n 0))
  (define (even? n) (= (% n 2) 0))
  (define (odd? n) (not (= (% n 2) 0)))

  ; --- Numeric operations ---
  (define (abs n) (if (< n 0) (- 0 n) n))
  (define (min a b) (if (< a b) a b))
  (define (max a b) (if (> a b) a b))

  ; --- Boolean ---
  (define (boolean? x) (or (eq? x t) (null? x)))

  ; --- List operations ---
  (define (length lst)
    (if (null? lst) 0
      (+ 1 (length (rest lst)))))

  (define (append a b)
    (if (null? a) b
      (pair (first a) (append (rest a) b))))

  (define (reverse lst)
    (def rev-helper (fn (lst acc)
      (if (null? lst) acc
        (rev-helper (rest lst) (pair (first lst) acc)))))
    (rev-helper lst ()))

  (define (list-ref lst n)
    (if (= n 0) (first lst)
      (list-ref (rest lst) (- n 1))))

  (define (list-tail lst n)
    (if (= n 0) lst
      (list-tail (rest lst) (- n 1))))

  (define (map f lst)
    (if (null? lst) ()
      (pair (f (first lst)) (map f (rest lst)))))

  (define (for-each f lst)
    (if (null? lst) ()
      (do (f (first lst)) (for-each f (rest lst)))))

  (define (filter pred lst)
    (if (null? lst) ()
      (if (pred (first lst))
        (pair (first lst) (filter pred (rest lst)))
        (filter pred (rest lst)))))

  (define (member x lst)
    (if (null? lst) #f
      (if (eq? x (first lst)) lst
        (member x (rest lst)))))

  (define (assoc key alist)
    (if (null? alist) #f
      (if (eq? key (caar alist)) (first alist)
        (assoc key (rest alist)))))

  ; --- String operations (R5RS aliases) ---
  (define (string-copy s) (substring s 0 (string-length s)))

  ; --- letrec ---
  ; Mutual recursion within let bindings.
  ; Expands to: (let ((v1 ()) ...) (set! v1 e1) ... body...)
  (def letrec (op (bindings . body) e
    (eval (pair (lit let)
      (pair (map (lambda (b) (list (first b) ())) bindings)
        (append (map (lambda (b) (list (lit set!) (first b) (cadr b))) bindings)
                body)))
      e)))

  ; --- Named let ---
  ; Save original let, then override with a version that detects named let.
  ; (let name ((var val)...) body...) -> recursive loop
  ; (let ((var val)...) body...) -> original let
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
  ; (case expr ((datum...) body) ... (else body))
  (def case (op (key . clauses) e
    (def case-val (eval key e))
    (def case-match? (fn (datum)
      (if (number? case-val) (= case-val datum) (eq? case-val datum))))
    (def case-check-datums (fn (datums)
      (if (null? datums) ()
        (if (case-match? (first datums)) t
          (case-check-datums (rest datums))))))
    (def case-loop (fn (cls)
      (if (null? cls) ()
        (if (or (eq? (first (first cls)) (lit else))
                (case-check-datums (first (first cls))))
          (eval (cadr (first cls)) e)
          (case-loop (rest cls))))))
    (case-loop clauses)))

  (lit scm)
)

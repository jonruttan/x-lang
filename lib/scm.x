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

  ; --- Boolean constants ---
  (def #t t)
  (def #f ())

  ; --- define: (define x val) or (define (f args...) body...) ---
  ; Uses plain eval (no env arg) so def extends the current env persistently.
  (def define (op (name-or-form . body) e
    (if (pair? name-or-form)
      (eval (list (quote def) (car name-or-form)
                  (cons (quote fn) (cons (cdr name-or-form) body))))
      (eval (list (quote def) name-or-form (car body))))))

  ; --- Conditional forms ---
  (def when (op (test . body) e
    (if (eval test e)
      (eval (cons (quote do) body) e))))

  (def unless (op (test . body) e
    (if (not (eval test e))
      (eval (cons (quote do) body) e))))

  ; --- let* ---
  (def let* (op (bindings . body) e
    (if (null? bindings)
      (eval (cons (quote do) body) e)
      (eval (list (quote let) (list (car bindings))
                  (cons (quote let*) (cons (cdr bindings) body))) e))))

  ; --- Composition accessors ---
  (define (caar x) (car (car x)))
  (define (cadr x) (car (cdr x)))
  (define (cdar x) (cdr (car x)))
  (define (cddr x) (cdr (cdr x)))
  (define (caaar x) (car (car (car x))))
  (define (caadr x) (car (car (cdr x))))
  (define (caddr x) (car (cdr (cdr x))))
  (define (cdddr x) (cdr (cdr (cdr x))))

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
      (+ 1 (length (cdr lst)))))

  (define (append a b)
    (if (null? a) b
      (cons (car a) (append (cdr a) b))))

  (define (reverse lst)
    (def rev-helper (fn (lst acc)
      (if (null? lst) acc
        (rev-helper (cdr lst) (cons (car lst) acc)))))
    (rev-helper lst ()))

  (define (list-ref lst n)
    (if (= n 0) (car lst)
      (list-ref (cdr lst) (- n 1))))

  (define (list-tail lst n)
    (if (= n 0) lst
      (list-tail (cdr lst) (- n 1))))

  (define (map f lst)
    (if (null? lst) ()
      (cons (f (car lst)) (map f (cdr lst)))))

  (define (for-each f lst)
    (if (null? lst) ()
      (do (f (car lst)) (for-each f (cdr lst)))))

  (define (filter pred lst)
    (if (null? lst) ()
      (if (pred (car lst))
        (cons (car lst) (filter pred (cdr lst)))
        (filter pred (cdr lst)))))

  (define (member x lst)
    (if (null? lst) #f
      (if (eq? x (car lst)) lst
        (member x (cdr lst)))))

  (define (assoc key alist)
    (if (null? alist) #f
      (if (eq? key (caar alist)) (car alist)
        (assoc key (cdr alist)))))

  (quote scm)
)

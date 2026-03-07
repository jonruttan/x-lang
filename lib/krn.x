; # Computational Expressions in C
;
; ## krn.x -- Kernel Personality
;
; @description Kernel language built on x-lang
;   Operatives are first-class; applicatives derived via wrap.
;   Same s-expression syntax, opposite evaluation model from Scheme.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2024 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
(do
  ; --- Core operative forms ---
  ; $vau is the fundamental abstraction (= op)
  (def $vau op)

  ; --- $define! ---
  ; Uses plain eval so def extends the current env persistently.
  (def $define! (op (name-or-form . body) e
    (if (pair? name-or-form)
      (eval (list (quote def) (car name-or-form)
                  (cons (quote $lambda) (cons (cdr name-or-form) body))))
      (eval (list (quote def) name-or-form (car body))))))

  ; --- Core aliases ---
  (def $if if)
  (def $cond cond)
  (def $let let)
  (def $sequence do)

  ; --- Boolean constants ---
  (def #t t)
  (def #f ())
  (def #ignore ())
  (def #inert ())

  ; --- $lambda: create applicative from operative ---
  ($define! $lambda (op (formals . body) e
    (wrap (eval (cons (quote $vau)
                  (cons formals
                    (cons (quote #ignore) body))) e))))

  ; --- Applicative wrappers for arithmetic ---
  ; In Kernel, standard combiners are applicatives (args evaluated).
  ; x-lang primitives are already fexprs that eval their args,
  ; so we just alias them directly.

  ; --- Derived operative forms ---
  ($define! $when (op (test . body) e
    ($if (eval test e)
      (eval (cons (quote $sequence) body)))))

  ($define! $unless (op (test . body) e
    ($if (not (eval test e))
      (eval (cons (quote $sequence) body)))))

  ; --- $let* ---
  ($define! $let* (op (bindings . body) e
    ($if (null? bindings)
      (eval (cons (quote $sequence) body) e)
      (eval (list (quote $let) (list (car bindings))
                  (cons (quote $let*) (cons (cdr bindings) body))) e))))

  ; --- Kernel-style predicates ---
  ($define! operative? ($lambda (x)
    (and (not (null? x))
         (not (procedure? x))
         (not (number? x))
         (not (string? x))
         (not (symbol? x))
         (not (pair? x)))))

  ($define! applicative? ($lambda (x) (procedure? x)))
  ($define! boolean? ($lambda (x) (or (eq? x t) (null? x))))
  ($define! inert? ($lambda (x) (null? x)))

  ; --- List operations (as applicatives via $lambda) ---
  ($define! (length lst)
    ($if (null? lst) 0
      (+ 1 (length (cdr lst)))))

  ($define! (append a b)
    ($if (null? a) b
      (cons (car a) (append (cdr a) b))))

  ($define! (reverse lst)
    (def rev-helper ($lambda (l acc)
      ($if (null? l) acc
        (rev-helper (cdr l) (cons (car l) acc)))))
    (rev-helper lst ()))

  ($define! (list-ref lst n)
    ($if (= n 0) (car lst)
      (list-ref (cdr lst) (- n 1))))

  ($define! (map f lst)
    ($if (null? lst) ()
      (cons (f (car lst)) (map f (cdr lst)))))

  ($define! (filter pred lst)
    ($if (null? lst) ()
      ($if (pred (car lst))
        (cons (car lst) (filter pred (cdr lst)))
        (filter pred (cdr lst)))))

  ($define! (for-each f lst)
    ($if (null? lst) ()
      ($sequence (f (car lst)) (for-each f (cdr lst)))))

  ; --- Composition accessors ---
  ($define! (caar x) (car (car x)))
  ($define! (cadr x) (car (cdr x)))
  ($define! (cdar x) (cdr (car x)))
  ($define! (cddr x) (cdr (cdr x)))
  ($define! (caddr x) (car (cdr (cdr x))))

  ; --- Number operations ---
  ($define! (zero? n) (= n 0))
  ($define! (positive? n) (> n 0))
  ($define! (negative? n) (< n 0))
  ($define! (even? n) (= (% n 2) 0))
  ($define! (odd? n) (not (= (% n 2) 0)))
  ($define! (abs n) ($if (< n 0) (- 0 n) n))
  ($define! (min a b) ($if (< a b) a b))
  ($define! (max a b) ($if (> a b) a b))

  ; --- Member / Assoc ---
  ($define! (member x lst)
    ($if (null? lst) #f
      ($if (eq? x (car lst)) lst
        (member x (cdr lst)))))

  ($define! (assoc key alist)
    ($if (null? alist) #f
      ($if (eq? key (caar alist)) (car alist)
        (assoc key (cdr alist)))))

  (quote krn)
)

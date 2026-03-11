; # Computational Expressions in C
;
; ## krn.x -- Kernel Personality
;
; @description Kernel language built on x-lang
;   Operatives are first-class; applicatives derived via wrap.
;   Same s-expression syntax, opposite evaluation model from Scheme.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
(do
  (include "lib/x-core.x")

  ; --- Core operative forms ---
  ; $vau is the fundamental abstraction (= op)
  (def $vau op)

  ; --- Aliases ---
  (def cons pair)
  (def car first)
  (def cdr rest)
  (def quote lit)
  (def $cond match)

  ; --- $define! ---
  ; Uses plain eval so def extends the current env persistently.
  (def $define! (op (name-or-form . body) e
    (if (pair? name-or-form)
      (eval (list (lit def) (first name-or-form)
                  (pair (lit $lambda) (pair (rest name-or-form) body))))
      (eval (list (lit def) name-or-form (first body))))))

  ; --- Core aliases ---
  (def $if if)
  (def $let let)
  (def $sequence do)

  ; --- Boolean constants ---
  (def #t t)
  (def #f ())
  (def #ignore ())
  (def #inert ())

  ; --- $lambda: create applicative from operative ---
  ($define! $lambda (op (formals . body) e
    (wrap (eval (pair (lit $vau)
                  (pair formals
                    (pair (lit #ignore) body))) e))))

  ; --- Applicative wrappers for arithmetic ---
  ; In Kernel, standard combiners are applicatives (args evaluated).
  ; x-lang primitives are already fexprs that eval their args,
  ; so we just alias them directly.

  ; --- Derived operative forms ---
  ($define! $when (op (test . body) e
    ($if (eval test e)
      (eval (pair (lit $sequence) body)))))

  ($define! $unless (op (test . body) e
    ($if (not (eval test e))
      (eval (pair (lit $sequence) body)))))

  ; --- $let* ---
  ($define! $let* (op (bindings . body) e
    ($if (null? bindings)
      (eval (pair (lit $sequence) body) e)
      (eval (list (lit $let) (list (first bindings))
                  (pair (lit $let*) (pair (rest bindings) body))) e))))

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
      (+ 1 (length (rest lst)))))

  ($define! (append a b)
    ($if (null? a) b
      (pair (first a) (append (rest a) b))))

  ($define! (reverse lst)
    (def rev-helper ($lambda (l acc)
      ($if (null? l) acc
        (rev-helper (rest l) (pair (first l) acc)))))
    (rev-helper lst ()))

  ($define! (list-ref lst n)
    ($if (= n 0) (first lst)
      (list-ref (rest lst) (- n 1))))

  ($define! (map f lst)
    ($if (null? lst) ()
      (pair (f (first lst)) (map f (rest lst)))))

  ($define! (filter pred lst)
    ($if (null? lst) ()
      ($if (pred (first lst))
        (pair (first lst) (filter pred (rest lst)))
        (filter pred (rest lst)))))

  ($define! (for-each f lst)
    ($if (null? lst) ()
      ($sequence (f (first lst)) (for-each f (rest lst)))))

  ; --- Composition accessors ---
  ($define! (caar x) (first (first x)))
  ($define! (cadr x) (first (rest x)))
  ($define! (cdar x) (rest (first x)))
  ($define! (cddr x) (rest (rest x)))
  ($define! (caddr x) (first (rest (rest x))))

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
      ($if (eq? x (first lst)) lst
        (member x (rest lst)))))

  ($define! (assoc key alist)
    ($if (null? alist) #f
      ($if (eq? key (caar alist)) (first alist)
        (assoc key (rest alist)))))

  ; --- $letrec ---
  ; Mutual recursion within $let bindings.
  ; Expands to: ($let ((v1 ()) ...) (set v1 e1) ... body...)
  ; NOTE: Param names use lr- prefix to avoid dynamic scoping collisions
  ; with $lambda's internal params (body, e, formals).
  ($define! $letrec (op (lr-binds . lr-body) lr-e
    (eval (pair (lit $let)
      (pair (map ($lambda (b) (list (first b) ())) lr-binds)
        (append (map ($lambda (b) (list (lit set) (first b) (cadr b))) lr-binds)
                lr-body)))
      lr-e)))

  ; --- get-current-environment ---
  ; Returns the caller's environment as a first-class value.
  ($define! get-current-environment (op () e e))

  ; --- make-environment ---
  ; Creates a fresh empty environment (an empty alist).
  ($define! (make-environment) ())

  (repl)
)

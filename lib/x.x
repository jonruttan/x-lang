; # Computational Expressions in C
;
; ## x.x -- x Standard Library
;
; @description Computational Expressions in C
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2021 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
(do (def x-lib-version "0.2.0")

  ; --- Derived from C primitives ---
  (def not null?)
  (def atom? (fn (x) (not (pair? x))))
  (def list (fn args args))
  (def %do do)
  (def %expanded (pair () ()))

  ; --- Core forms as operatives ---
  ; Compile-on-first-use: expand to if-tree, cache in source form via %rewrite.
  ; First call: expand + rewrite + eval. Subsequent calls: eq? + eval.

  (def %and-expand (fn (args)
    (if (null? args) (lit t)
      (if (null? (rest args))
        (first args)
        (list (lit if) (first args)
          (%and-expand (rest args))
          ())))))
  (def and (op args e
    (if (null? args) (lit t)
      (if (eq? (first args) %expanded)
        (eval (first (rest args)))
        (%do (def %t (%and-expand args))
             (%rewrite args %expanded (pair %t ()))
             (eval %t))))))

  (def %or-expand (fn (args)
    (if (null? args) ()
      (if (null? (rest args))
        (first args)
        (list (lit %do)
          (list (lit def) (lit %or-v) (first args))
          (list (lit if) (lit %or-v) (lit %or-v)
            (%or-expand (rest args))))))))
  (def or (op args e
    (if (null? args) ()
      (if (eq? (first args) %expanded)
        (eval (first (rest args)))
        (%do (def %t (%or-expand args))
             (%rewrite args %expanded (pair %t ()))
             (eval %t))))))

  (def %match-expand (fn (clauses)
    (if (null? clauses) ()
      (list (lit if) (first (first clauses))
        (first (rest (first clauses)))
        (%match-expand (rest clauses))))))
  (def match (op clauses e
    (if (null? clauses) ()
      (if (eq? (first clauses) %expanded)
        (eval (first (rest clauses)))
        (%do (def %t (%match-expand clauses))
             (%rewrite clauses %expanded (pair %t ()))
             (eval %t))))))

  ; --- Derived comparisons ---
  (def > (fn (a b) (< b a)))
  (def <= (fn (a b) (or (< a b) (= a b))))
  (def >= (fn (a b) (or (< b a) (= a b))))

  (include "lib/x/fn.x")
  (include "lib/x/math.x")
  (include "lib/x/logic.x")
  (include "lib/x/list.x")
  (include "lib/x/alist.x")
  (include "lib/x/string.x")
  (include "lib/x/vector.x")
  (include "lib/x/float.x")
  (include "lib/x/regex.x")

  ; --- quasi (needs append from list.x) ---
  ; Compile template to a pair/lit/append tree that, when eval'd,
  ; constructs the result with current bindings.
  (def %quasi-compile (fn (t)
    (if (or (null? t) (atom? t))
      (list (lit lit) t)
      (if (eq? (first t) (lit unquote))
        (first (rest t))
        (if (and (pair? (first t))
                 (eq? (first (first t)) (lit unquote-splicing)))
          (list (lit append)
                (first (rest (first t)))
                (%quasi-compile (rest t)))
          (list (lit pair)
                (%quasi-compile (first t))
                (%quasi-compile (rest t))))))))
  (def quasi (op args e
    (if (eq? (first args) %expanded)
      (eval (first (rest args)))
      (%do (def %t (%quasi-compile (first args)))
           (%rewrite args %expanded (pair %t ()))
           (eval %t)))))

  ()
)

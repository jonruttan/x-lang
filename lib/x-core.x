; # Computational Expressions in C
;
; ## x-core.x -- x Core Standard Library (without regex/float)
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

  ; match is now a C primitive in core.c

  ; --- Derived comparisons ---
  (def > (fn (a b) (< b a)))
  (def <= (fn (a b) (or (< a b) (= a b))))
  (def >= (fn (a b) (or (< b a) (= a b))))

  ; --- Profiling ---
  (def time (op args e
    (let ((t0 (clock)))
      (let ((result (eval (first args) e)))
        (display (- (clock) t0))
        (display " us\n")
        result))))

  (include "lib/x/fn.x")
  (include "lib/x/math.x")
  (include "lib/x/logic.x")
  (include "lib/x/list.x")

  ; --- Save integer primitives and make arithmetic variadic ---
  ; fold (from list.x) enables variadic wrappers. float.x later overrides
  ; these with float-aware versions, reusing the saved %int* primitives.
  (def %int+ +)
  (def %int- -)
  (def %int* *)
  (def %int/ /)
  (def %int< <)
  (def %int= =)
  (def %int-number? number?)

  (set + (fn args
    (if (null? args) 0
      (fold %int+ (first args) (rest args)))))

  (set * (fn args
    (if (null? args) 1
      (fold %int* (first args) (rest args)))))

  (set / (fn args
    (if (null? args) 1
      (fold %int/ (first args) (rest args)))))

  (set - (fn args
    (if (null? args) 0
      (if (null? (rest args))
        (%int- 0 (first args))
        (fold %int- (first args) (rest args))))))

  ; --- Intrinsic scoring helpers for custom type analysers ---
  (def buffer-len (fn (buffer)
    (- (first-int (rest buffer)) (first-int buffer))))
  (def buffer-unread (fn (buffer)
    (set-first-int (rest buffer) (- (first-int (rest buffer)) 1))))
  (def score-set (fn (score sign buffer reader)
    (do (set-first-int score (* sign (buffer-len buffer)))
        (set-rest score reader))))

  (include "lib/x/alist.x")
  (include "lib/x/string.x")
  (include "lib/x/vector.x")

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

  ; --- REPL ---
  (def %repl-prompt "> ")
  (def %repl-print (fn (result) (if (null? result) () (write result)) (newline)))

  (def repl (op ()
    (display %repl-prompt)
    (def %r (read))
    (if (null? %r) ()
      (%do (guard (err (display err) (newline))
             (%repl-print (eval! %r)))
           (repl)))))

  (repl)
)

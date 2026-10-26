; control.x -- Core control flow forms
;
; Defines if and let as operatives built on match.

(import x/core/predicates)

(def if
  (op (test then . else)
    e
    (match
      ((eval test e) (tail-eval then e))
      ((null? else) ())
      (#t (tail-eval (first else) e)))))

; let is the application of the fn it names, built once a run and handed to
; tail-eval: (let ((a 1) (b 2)) body) is ((fn (_ a b) body) 1 2), and the
; named form (let go ((i 0)) body) is ((fn (go i) body) 0) -- fn's arg 0 IS
; the closure, so go recurses with no letrec.  Inits evaluate in the OUTER
; env, as application arguments.  One binding costs 58 objects a run, three
; 96; the fn it builds costs 10 and 16 called in place, and the rest is the
; two walks below.  (The plain form used to go through a second operative
; that evaluated the fn into a closure and applied it to a list of values:
; 120 and 192.)
(def %let-params
  (fn (self bindings)
    (match
      ((eq? bindings ()) ())
      (#t (pair (first (first bindings)) (self (rest bindings)))))))
(def %let-inits
  (fn (self bindings)
    (match
      ((eq? bindings ()) ())
      (#t (pair (first (rest (first bindings))) (self (rest bindings)))))))
(def let
  (op (first-arg . rest-args)
    e
    (match
      ((symbol? first-arg)
        (tail-eval
          (pair
            (pair (lit fn)
              (pair (pair first-arg (%let-params (first rest-args))) (rest rest-args)))
            (%let-inits (first rest-args)))
          e))
      (#t
        (tail-eval
          (pair
            (pair (lit fn) (pair (pair (lit _) (%let-params first-arg)) rest-args))
            (%let-inits first-arg))
          e)))))

; NOTE: this module loads before the doc system (x/doc/doc.x), so it cannot
; wrap its provide in (doc ...). Its module description is registered
; retroactively in x/doc/doc-prims.x.
(provide x/core/control if let)

; control.x -- Core control flow forms
;
; Defines if and let as operatives built on match.

(import x/core/predicates)

; The engine's apply, kept under a fixed name.  lib/x/core/fn.x binds the
; library's apply over the bare one -- a value applies through its type's
; call handler there -- and let, a derived form over fn, applies the closure
; it just built: it has nothing for that door to look at, and a lang that
; binds apply over the library's, as the library binds it over the engine's,
; must not retarget every let.
(def %apply apply)

(def if
  (op (test then . else)
    e
    (match
      ((eval test e) (tail-eval then e))
      ((null? else) ())
      (#t (tail-eval (first else) e)))))

(def %let-params
  (fn (self bindings)
    (match
      ((null? bindings) ())
      (#t
        (pair
          (first (first bindings))
          (self (rest bindings)))))))

(def %let-vals
  (fn (self bindings e)
    (match
      ((null? bindings) ())
      (#t
        (pair
          (eval (first (rest (first bindings))) e)
          (self (rest bindings) e))))))

(def let
  (op (bindings . body)
    e
    (%apply
      (eval (pair (lit fn) (pair (pair (lit _) (%let-params bindings)) body)) e)
      (%let-vals bindings e))))

; NOTE: this module loads before the doc system (x/doc/doc.x), so it cannot
; wrap its provide in (doc ...). Its module description is registered
; retroactively in x/doc/doc-prims.x.
(provide x/core/control if let)

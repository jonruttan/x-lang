; control.x -- Core control flow forms
;
; Defines if and let as operatives built on match.

; Ensure null? is available
(match
  ((guard (e ()) (eval (lit null?))) ())
  (#t (include "lib/x/boot/predicates.x")))

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
    (apply
      (eval (pair (lit fn) (pair (pair (lit _) (%let-params bindings)) body)) e)
      (%let-vals bindings e))))

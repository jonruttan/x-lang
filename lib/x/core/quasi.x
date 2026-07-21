; quasi.x -- Quasiquote template system
;
; Compile-on-first-use: expands template to pair/lit/append tree,
; caches in source form via %rewrite.
; Requires: and/or (and), predicates (atom?, pair?), data (%rewrite, %expanded)

; Depth-tracked (#55 ruled): a nested (quasi ...) head DEEPENS by one, and
; unquote / unquote-splicing return one level -- only a depth-1 payload
; evaluates. A form at depth > 1 is REBUILT as syntax with its payload
; compiled one level shallower, so each surrounding quasi strips exactly
; one unquote: (quasi (quasi (unquote (unquote x)))) -> ('quasi ('unquote
; <x evaluated>)). Without the counter the inner unquote leaked into the
; expansion and was EVALUATED -- a call to the unbound symbol `unquote`,
; surfacing as the raw-atom error the example runner caught.
(def %quasi-compile
  (fn (self t d)
    (match
      ((or (null? t) (atom? t)) (list (lit lit) t))
      ((eq? (first t) (lit quasi))
        (list (lit pair) (list (lit lit) (lit quasi))
          (list (lit pair) (self (first (rest t)) (+ d 1)) ())))
      ((eq? (first t) (lit unquote))
        (match
          ((eq? d 1) (first (rest t)))
          (#t
            (list (lit pair) (list (lit lit) (lit unquote))
              (list (lit pair) (self (first (rest t)) (- d 1)) ())))))
      ((and (pair? (first t)) (eq? (first (first t)) (lit unquote-splicing)))
        (match
          ((eq? d 1)
            (list (lit append) (first (rest (first t))) (self (rest t) d)))
          (#t
            (list (lit pair)
              (list (lit pair) (list (lit lit) (lit unquote-splicing))
                (list (lit pair) (self (first (rest (first t))) (- d 1)) ()))
              (self (rest t) d)))))
      (#t (list (lit pair) (self (first t) d) (self (rest t) d))))))

(doc (def quasi
  (op args
    e
    (if (eq? (first args) %expanded)
      ; tail-eval (not eval) in e: ops are lexically scoped, so the
      ; quasi expansion must be evaluated in the caller's env to resolve
      ; unquoted references.  eval-with-env save/restores env around its
      ; eval and does not propagate to TCO continuations.
      (tail-eval (first (rest args)) e)
      (%seq
        (def %t (%quasi-compile (first args) 1))
        (%seq (%rewrite args %expanded (pair %t ())) (tail-eval %t e))))))
  (param args ANY "Template expression with optional unquote/unquote-splicing")
  (returns ANY "Expanded template with substitutions")
  (note "Compile-on-first-use: the template is compiled to a pair/lit/append tree on first evaluation, then cached.")
  (example "(def x 1) (quasi (a ,x b))" "('a 1 'b)")
  "Quasiquote: template with unquote and splicing.")

(doc (provide x/core/quasi quasi)
  "Quasiquote: template with unquote and splicing.")

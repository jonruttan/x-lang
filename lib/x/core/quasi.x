; quasi.x -- Quasiquote template system
;
; Compile-on-first-use: expands template to pair/lit/append tree,
; caches in source form via %rewrite.
; Requires: and/or (and), predicates (atom?, pair?), data (%rewrite, %expanded)

(def %quasi-compile
  (fn (self t)
    (if (or (null? t) (atom? t))
      (list (lit lit) t)
      (if (eq? (first t) (lit unquote))
        (first (rest t))
        (if (and
              (pair? (first t))
              (eq? (first (first t)) (lit unquote-splicing)))
          (list
            (lit append)
            (first (rest (first t)))
            (self (rest t)))
          (list
            (lit pair)
            (self (first t))
            (self (rest t))))))))

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
        (def %t (%quasi-compile (first args)))
        (%seq (%rewrite args %expanded (pair %t ())) (tail-eval %t e))))))
  (param args ANY "Template expression with optional unquote/unquote-splicing")
  (returns ANY "Expanded template with substitutions")
  (note "Compile-on-first-use: the template is compiled to a pair/lit/append tree on first evaluation, then cached.")
  (example "(def x 1) (quasi (a ,x b))" "('a 1 'b)")
  "Quasiquote: template with unquote and splicing.")

(doc (provide x/core/quasi quasi)
  "Quasiquote: template with unquote and splicing.")

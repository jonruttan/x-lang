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

(def quasi
  (op args
    e
    (if (eq? (first args) %expanded)
      (eval (first (rest args)))
      (%seq
        (def %t (%quasi-compile (first args)))
        (%seq (%rewrite args %expanded (pair %t ())) (eval %t))))))

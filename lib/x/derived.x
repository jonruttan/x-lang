; --- Derived expression types ---
;
; General-purpose constructs built from x-lang primitives.
; Loaded after list.x (letrec needs map/append).
(import x/list)

; --- when / unless ---

(def when
  (op (test . body)
    e
    (if (eval test e) (tail-eval (pair (lit do) body) e))))
(def unless
  (op (test . body)
    e
    (if (not (eval test e)) (tail-eval (pair (lit do) body) e))))

; --- let* (sequential binding) ---

(def let*
  (op (bindings . body)
    e
    (if (null? bindings)
      (tail-eval (pair (lit do) body) e)
      (tail-eval
        (list
          (lit let)
          (list (first bindings))
          (pair (lit let*) (pair (rest bindings) body)))
        e))))

; --- letrec (recursive binding) ---

(def letrec
  (op (bindings . body)
    e
    (tail-eval
      (pair
        (lit let)
        (pair
          (map (fn (b) (list (first b) ())) bindings)
          (append
            (map
              (fn (b) (list (lit set!) (first b) (first (rest b))))
              bindings)
            body)))
      e)))

; --- Named let: (let name ((var init) ...) body...) ---

(def %let let)
(def let
  (op (first-arg . rest-args)
    e
    (if (symbol? first-arg)
      (tail-eval
        (list
          (lit letrec)
          (list
            (list
              first-arg
              (pair
                (lit fn)
                (pair (map first (first rest-args)) (rest rest-args)))))
          (pair first-arg (map (fn (b) (first (rest b))) (first rest-args))))
        e)
      (tail-eval (pair (lit %let) (pair first-arg rest-args)) e))))

; --- cond (multi-expression clause bodies + else + => syntax) ---

(def cond
  (op clauses
    e
    (let %cond-loop
      ((cls clauses))
      (if (null? cls)
        ()
        (let ((clause (first cls)))
          (if (eq? (first clause) (lit else))
            (tail-eval (pair (lit do) (rest clause)) e)
            (let ((test-val (eval (first clause) e)))
              (if test-val
                (if (and (pair? (rest clause))
                         (eq? (first (rest clause)) (lit =>)))
                  ((eval (first (rest (rest clause))) e) test-val)
                  (tail-eval (pair (lit do) (rest clause)) e))
                (%cond-loop (rest cls))))))))))

; --- case (value dispatch with multi-expression clause bodies) ---

(def case
  (op (key . clauses)
    e
    (def case-val (eval key e))
    (def case-match?
      (fn (datum)
        (if (number? case-val)
          (= case-val datum)
          (eq? case-val datum))))
    (def case-check-datums
      (fn (datums)
        (match
          ((null? datums) ())
          ((case-match? (first datums)) #t)
          (#t (case-check-datums (rest datums))))))
    (def case-loop
      (fn (cls)
        (match
          ((null? cls) ())
          ((or
             (eq? (first (first cls)) (lit else))
             (case-check-datums (first (first cls))))
            (tail-eval (pair (lit do) (rest (first cls))) e))
          (#t (case-loop (rest cls))))))
    (case-loop clauses)))

(provide x/derived when unless let* letrec cond case)

; --- Derived expression types ---
;
; General-purpose constructs built from x-lang primitives.
; Loaded after list.x (letrec needs map/append).
(import x/list)

; --- when / unless ---

(doc when "Evaluate body forms when test is true."
  (param test ANY "Expression to evaluate as a boolean")
  (param body ANY "One or more body expressions"))
(def when
  (op (_ test . body)
    e
    (if (eval test e) (tail-eval (pair (lit do) body) e))))
(doc unless "Evaluate body forms when test is false."
  (param test ANY "Expression to evaluate as a boolean")
  (param body ANY "One or more body expressions"))
(def unless
  (op (_ test . body)
    e
    (if (not (eval test e)) (tail-eval (pair (lit do) body) e))))

; --- let* (sequential binding) ---

(doc let* "Sequential let: bindings are evaluated left to right, each visible to the next."
  (param bindings LIST "List of (name value) binding pairs")
  (param body ANY "One or more body expressions"))
(def let*
  (op (_ bindings . body)
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

(doc letrec "Recursive let: all bindings are visible to each other, enabling mutual recursion."
  (param bindings LIST "List of (name value) binding pairs")
  (param body ANY "One or more body expressions"))
(def letrec
  (op (_ bindings . body)
    e
    (tail-eval
      (pair
        (lit let)
        (pair
          (map (fn (_ b) (list (first b) ())) bindings)
          (append
            (map
              (fn (_ b) (list (lit set!) (first b) (first (rest b))))
              bindings)
            body)))
      e)))

; --- Named let: (let name ((var init) ...) body...) ---

(def %let let)
(def let
  (op (_ first-arg . rest-args)
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
                (pair (pair (lit _) (map first (first rest-args))) (rest rest-args)))))
          (pair first-arg (map (fn (_ b) (first (rest b))) (first rest-args))))
        e)
      (tail-eval (pair (lit %let) (pair first-arg rest-args)) e))))

; --- cond (multi-expression clause bodies + else + => syntax) ---

(doc cond "Multi-way conditional: evaluates clauses in order, returning the body of the first true test. Supports else and => syntax."
  (param clauses LIST "List of (test body...) clauses; use else for default"))
(def cond
  (op (_ . clauses)
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

(doc case "Dispatch on a value: evaluates key, then matches against datum lists in each clause."
  (param key ANY "Expression to evaluate and match against")
  (param clauses LIST "List of ((datum ...) body...) clauses; use else for default"))
(def case
  (op (_ key . clauses)
    e
    (def case-val (eval key e))
    (def case-match?
      (fn (_ datum)
        (if (number? case-val)
          (= case-val datum)
          (eq? case-val datum))))
    (def case-check-datums
      (fn (_ datums)
        (match
          ((null? datums) ())
          ((case-match? (first datums)) #t)
          (#t (case-check-datums (rest datums))))))
    (def case-loop
      (fn (_ cls)
        (match
          ((null? cls) ())
          ((or
             (eq? (first (first cls)) (lit else))
             (case-check-datums (first (first cls))))
            (tail-eval (pair (lit do) (rest (first cls))) e))
          (#t (case-loop (rest cls))))))
    (case-loop clauses)))

(doc (provide x/derived when unless let* letrec cond case)
  (note "These are operatives that extend the core syntax.")
  "Derived syntax forms: cond, case, when, unless, let*, letrec.")

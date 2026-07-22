; --- Derived expression types ---
;
; General-purpose constructs built from x-lang primitives.
; Loaded after list.x (letrec needs map/append).
(import x/core/list)

; --- when / unless ---

(doc when "Evaluate body forms when test is true."
  (param test ANY "Expression to evaluate as a boolean")
  (param body ANY "One or more body expressions"))
(def when
  (op (test . body)
    e
    (if (eval test e) (tail-eval (pair (lit do) body) e))))
(doc unless "Evaluate body forms when test is false."
  (param test ANY "Expression to evaluate as a boolean")
  (param body ANY "One or more body expressions"))
(def unless
  (op (test . body)
    e
    (if (not (eval test e)) (tail-eval (pair (lit do) body) e))))


; let* was RETIRED (#45 R6, 2026-07-18): six historical uses migrated to
; nested let; sequential binding is spelled with nested let (in tails,
; where def would leak) or def-in-body (elsewhere). See docs/syntax.md.

; --- letrec (recursive binding) ---

(doc letrec "Recursive let: all bindings are visible to each other, enabling mutual recursion."
  (param bindings LIST "List of (name value) binding pairs")
  (param body ANY "One or more body expressions"))
(def letrec
  (op (bindings . body)
    e
    (tail-eval
      (pair
        (lit let)
        (pair
          (%map (fn (_ b) (list (first b) ())) bindings)
          (%append
            (%map
              (fn (_ b) (list (lit set!) (first b) (first (rest b))))
              bindings)
            body)))
      e)))

; --- Named let: (let name ((var init) ...) body...) ---

(def %let let)
; Named let compiles DIRECTLY to a self-passing fn application: fn's
; arg 0 IS the closure, so (let go ((i 0)) body) is exactly
; ((fn (go i) body) 0) -- no letrec/set! source-construction cascade
; (the old path built letrec -> let -> %let forms per EVALUATION,
; ~2,650 objects; the 2026-07-16 disease probes).  Init expressions
; still evaluate in the OUTER env, as application arguments.
(def %named-let-params
  (fn (self bindings)
    (match
      ((eq? bindings ()) ())
      (#t (pair (first (first bindings)) (self (rest bindings)))))))
(def %named-let-inits
  (fn (self bindings)
    (match
      ((eq? bindings ()) ())
      (#t (pair (first (rest (first bindings))) (self (rest bindings)))))))
(def let
  (op (first-arg . rest-args)
    e
    (if (symbol? first-arg)
      (tail-eval
        (pair
          (pair (lit fn)
            (pair (pair first-arg (%named-let-params (first rest-args)))
              (rest rest-args)))
          (%named-let-inits (first rest-args)))
        e)
      (tail-eval (pair (lit %let) (pair first-arg rest-args)) e))))

; --- cond (multi-expression clause bodies + else + => syntax) ---

(doc cond "Multi-way conditional: evaluates clauses in order, returning the body of the first true test. Supports else and => syntax."
  (param clauses LIST "List of (test body...) clauses; use else for default"))
; Param helpers, nested if, eq?-nil -- NO lets, named-lets, or `and`:
; the old body allocated ~3,000 objects per cond EVALUATION (a named-let
; + two lets + an and per clause walk; the 2026-07-16 disease probes),
; and cond runs everywhere in lib.
(def %cond-hit
  (fn (_ v clause cls e)
    (if v
      (if (pair? (rest clause))
        (if (eq? (first (rest clause)) (lit =>))
          ((eval (first (rest (rest clause))) e) v)
          (tail-eval (pair (lit do) (rest clause)) e))
        (tail-eval (pair (lit do) (rest clause)) e))
      (%cond-loop (rest cls) e))))
(def %cond-loop
  (fn (self cls e)
    (if (eq? cls ())
      ()
      (if (eq? (first (first cls)) (lit else))
        (tail-eval (pair (lit do) (rest (first cls))) e)
        (%cond-hit (eval (first (first cls)) e) (first cls) cls e)))))
(def cond
  (op clauses
    e
    (%cond-loop clauses e)))

; --- case (value dispatch with multi-expression clause bodies) ---

(doc case "Dispatch on a value: evaluates key, then matches against datum lists in each clause."
  (param key ANY "Expression to evaluate and match against")
  (param clauses LIST "List of ((datum ...) body...) clauses; use else for default"))
(def case
  (op (key . clauses)
    e
    (def case-val (eval key e))
    (def case-match?
      (fn (_ datum)
        (if (number? case-val)
          (= case-val datum)
          (eq? case-val datum))))
    (def case-check-datums
      (fn (self datums)
        (match
          ((null? datums) ())
          ((case-match? (first datums)) #t)
          (#t (self (rest datums))))))
    (def case-loop
      (fn (self cls)
        (match
          ((null? cls) ())
          ((or
             (eq? (first (first cls)) (lit else))
             (case-check-datums (first (first cls))))
            (tail-eval (pair (lit do) (rest (first cls))) e))
          (#t (self (rest cls))))))
    (case-loop clauses)))

(doc (provide x/core/syntax when unless letrec cond case)
  (note "These are operatives that extend the core syntax.")
  "Derived syntax forms: cond, case, when, unless, letrec.")

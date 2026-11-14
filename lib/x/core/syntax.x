; --- Derived expression types ---
;
; General-purpose constructs built from x-lang primitives.
; Loaded after list.x (letrec needs map/append).
(import x/core/list)

; --- when / unless ---

(doc when "Evaluate body forms when test is true."
  (param test ANY "Expression to evaluate as a boolean")
  (param body ANY "One or more body expressions")
  (example "(when (< 1 2) 'a 'b)" "'b"))
; `match`, not `if`: an `if` costs ~17 objects an evaluation and a `match`
; none, and these two run everywhere in lib.  A one-form body, nearly every
; one, is evaluated as it stands rather than wrapped in (do FORM).
(def when
  (op (test . body)
    e
    (match
      ((eval test e)
        (match
          ((eq? body ()) ())
          ((eq? (rest body) ()) (tail-eval (first body) e))
          (#t (tail-eval (pair (lit do) body) e)))))))
(doc unless "Evaluate body forms when test is false."
  (param test ANY "Expression to evaluate as a boolean")
  (param body ANY "One or more body expressions")
  (example "(unless (< 2 1) 'yes)" "'yes"))
(def unless
  (op (test . body)
    e
    (match
      ((eval test e) ())
      ((eq? body ()) ())
      ((eq? (rest body) ()) (tail-eval (first body) e))
      (#t (tail-eval (pair (lit do) body) e)))))


; let* was RETIRED (#45 R6, 2026-07-18): six historical uses migrated to
; nested let; sequential binding is spelled with nested let (in tails,
; where def would leak) or def-in-body (elsewhere). See docs/syntax.md.

; --- letrec (recursive binding) ---

(doc letrec "Recursive let: all bindings are visible to each other, enabling mutual recursion."
  (param bindings LIST "List of (name value) binding pairs")
  (param body ANY "One or more body expressions")
  (example "(letrec ((ev? (fn (_ n) (if (= n 0) #t (od? (- n 1))))) (od? (fn (_ n) (if (= n 0) #f (ev? (- n 1)))))) (ev? 10))" "#t"))
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

; --- cond (multi-expression clause bodies + else + => syntax) ---

(doc cond "Multi-way conditional: evaluates clauses in order, returning the body of the first true test. Supports else and => syntax."
  (param clauses LIST "List of (test body...) clauses; use else for default")
  (example "(cond ((< 3 1) 'a) ((< 1 3) 'b) (else 'c))" "'b")
  (example "(cond ((%assoc-get 'b '((a . 1) (b . 2))) => (fn (_ v) (* v 10))) (else 0))" "20"))
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
  (param clauses LIST "List of ((datum ...) body...) clauses; use else for default")
  (example "(case 3 ((1 2) 'low) ((3 4) 'mid) (else 'high))" "'mid")
  (example "(case 9 ((1 2) 'low) (else 'high))" "'high"))
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
  (example "(unless #f (cond ((< 1 2) 'ok)))" "'ok")
  "Derived syntax forms: cond, case, when, unless, letrec.")

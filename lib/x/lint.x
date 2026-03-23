; lint.x -- AST linter library (def/use analysis)
;
; Reports undefined symbol references and unused bindings.
; Uses x-lang's own env-alist for "known" symbols — no manual
; enumeration of C primitives or library defs needed.
(import x/list)
(import x/alist)
(import x/string)

; Snapshot the current env-alist — everything defined before
; the target file (C primitives + standard library).
(def %known-env
  (first (first (first (rest (rest (first (%base))))))))

; --- AST walking: collect symbol uses ---

; Forward declarations for mutual recursion
(def %walk ())
(def %walk-pair ())
(def %walk-list ())

(def %add-params (fn (_ params scope)
  (if (null? params) scope
    (if (symbol? params)
      (pair params scope)
      (if (pair? params)
        (%add-params (rest params) (pair (first params) scope))
        scope)))))

; Walk a list of sequential forms, accumulating defs into scope
(set! %walk-list (fn (_ forms scope uses)
  (if (null? forms) uses
    (if (pair? forms)
      (do (def form (first forms))
          (def new-uses (%walk form scope uses))
          ; If form is (def name ...), add name to scope for rest
          (def new-scope
            (if (if (pair? form) (eq? (first form) (lit def)) ())
              (pair (first (rest form)) scope)
              scope))
          (%walk-list (rest forms) new-scope new-uses))
      (%walk forms scope uses)))))

; (fn (_ params...) body...)
(def %walk-fn (fn (_ form scope uses)
  (def params (first (rest form)))
  (%walk-list (rest (rest form)) (%add-params params scope) uses)))

; (op (_ params env) body...)
(def %walk-op (fn (_ form scope uses)
  (def params (first (rest form)))
  (def env-param (first (rest (rest form))))
  (%walk-list (rest (rest (rest form)))
    (pair env-param (%add-params params scope)) uses)))

; (let ((name val) ...) body...) or (let name ((var init) ...) body...)
(def %walk-let-bindings (fn (_ bindings scope uses)
  (if (null? bindings)
    (list scope uses)
    (do (def b (first bindings))
        (def new-uses (%walk (first (rest b)) scope uses))
        (%walk-let-bindings (rest bindings)
          (pair (first b) scope) new-uses)))))

(def %walk-let (fn (_ form scope uses)
  (def first-arg (first (rest form)))
  (if (symbol? first-arg)
    ; Named let: (let name ((var init) ...) body...)
    (do (def result
          (%walk-let-bindings (first (rest (rest form)))
            (pair first-arg scope) uses))
        (%walk-list (rest (rest (rest form)))
          (first result) (first (rest result))))
    ; Regular let: (let ((var init) ...) body...)
    (do (def result (%walk-let-bindings first-arg scope uses))
        (%walk-list (rest (rest form))
          (first result) (first (rest result)))))))

; (def name val) or (define (name params...) body...)
(def %walk-def (fn (_ form scope uses)
  (def name-part (first (rest form)))
  (if (pair? name-part)
    ; Compound: (define (name params...) body...)
    (%walk-list (rest (rest form))
      (%add-params (rest name-part) (pair (first name-part) scope))
      uses)
    ; Simple: (def name val)
    (%walk (first (rest (rest form))) (pair name-part scope) uses))))

; (set! name val)
(def %walk-set (fn (_ form scope uses)
  (%walk (first (rest (rest form))) scope
    (%walk (first (rest form)) scope uses))))

; (guard (var handler) body...)
(def %walk-guard (fn (_ form scope uses)
  (def clause (first (rest form)))
  (%walk-list (rest (rest form)) scope
    (%walk (first (rest clause)) (pair (first clause) scope) uses))))

; Walk quasiquote -- only walk unquoted parts
(def %walk-quasi (fn (_ form scope uses)
  (if (null? form) uses
    (if (pair? form)
      (if (eq? (first form) (lit unquote))
        (%walk (first (rest form)) scope uses)
        (if (eq? (first form) (lit unquote-splicing))
          (%walk (first (rest form)) scope uses)
          (%walk-quasi (rest form) scope
            (%walk-quasi (first form) scope uses))))
      uses))))

; Walk a pair -- dispatches on %scope-table (overridable by tools)
; %walk-pair is forward-declared; callers can set! it after loading
; construct declarations for data-driven dispatch.

; Walk an AST form, collecting symbol uses
(set! %walk (fn (_ form scope uses)
  (if (null? form) uses
    (if (symbol? form)
      (if (includes? form scope) uses
        (if (assoc-has? form uses) uses
          (assoc-put form t uses)))
      (if (pair? form)
        (%walk-pair form scope uses)
        uses)))))

; --- Analysis entry points ---

(doc (def lint-forms (fn (_ forms defs uses)
  (if (null? forms) (list defs uses)
    (do (def form (first forms))
        (def new-defs
          (if (if (pair? form) (eq? (first form) (lit def)) ())
            (pair (first (rest form)) defs)
            defs))
        (def new-uses (%walk form () uses))
        (lint-forms (rest forms) new-defs new-uses)))))
  (param forms LIST "List of top-level forms to analyze")
  (param defs LIST "Accumulator for defined symbols")
  (param uses ALIST "Accumulator for used symbols")
  (returns LIST "(defs uses) pair")
  "Walk top-level forms, collecting definitions and symbol uses.")

(doc (def lint-undefined (fn (_ defs uses)
  (filter (fn (_ sym)
    (if (includes? sym defs) ()
      (if (assoc-has? sym %known-env) () t)))
    (assoc-keys uses))))
  (param defs LIST "Defined symbols from lint-forms")
  (param uses ALIST "Used symbols from lint-forms")
  (returns LIST "Symbols used but not defined")
  "Compute undefined symbols: used but not in env or file defs.")

(doc (def lint-unused (fn (_ defs uses lib-mode)
  (if lib-mode ()
    (filter (fn (_ sym)
      (if (string-starts? "%" (convert sym %string)) ()
        (if (assoc-has? sym uses) () t)))
      defs))))
  (param defs LIST "Defined symbols from lint-forms")
  (param uses ALIST "Used symbols from lint-forms")
  (param lib-mode BOOLEAN "If true, skip unused check")
  (returns LIST "Symbols defined but never used")
  "Compute unused symbols: defined but not referenced. Skips %-prefixed internals.")

(doc (provide x/lint
  lint-forms lint-undefined lint-unused)
  "AST linter: def/use analysis for x-lang source.")

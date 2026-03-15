; lint-lib.x -- x-lang AST linter library (def/use analysis)
;
; Reports undefined symbol references and unused bindings.
;
; Uses x-lang's own env-alist for "known" symbols — no manual
; enumeration of C primitives or library defs needed.

; Snapshot the current env-alist — everything defined before
; the target file (C primitives + standard library).
(def %known-env
  (first (first (first (rest (rest (first (%base))))))))

; --- AST walking: collect symbol uses ---

; Forward declarations for mutual recursion
(def %walk ())
(def %walk-pair ())
(def %walk-list ())

(def %add-params (fn (params scope)
  (if (null? params) scope
    (if (symbol? params)
      (pair params scope)
      (if (pair? params)
        (%add-params (rest params) (pair (first params) scope))
        scope)))))

; Walk a list of sequential forms, accumulating defs into scope
(set %walk-list (fn (forms scope uses)
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

; (fn (params...) body...)
(def %walk-fn (fn (form scope uses)
  (def params (first (rest form)))
  (%walk-list (rest (rest form)) (%add-params params scope) uses)))

; (op (params env) body...)
(def %walk-op (fn (form scope uses)
  (def params (first (rest form)))
  (def env-param (first (rest (rest form))))
  (%walk-list (rest (rest (rest form)))
    (pair env-param (%add-params params scope)) uses)))

; (let ((name val) ...) body...) or (let name ((var init) ...) body...)
(def %walk-let-bindings (fn (bindings scope uses)
  (if (null? bindings)
    (list scope uses)
    (do (def b (first bindings))
        (def new-uses (%walk (first (rest b)) scope uses))
        (%walk-let-bindings (rest bindings)
          (pair (first b) scope) new-uses)))))

(def %walk-let (fn (form scope uses)
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
; Handles compound definitions where name is a list (name params...).
(def %walk-def (fn (form scope uses)
  (def name-part (first (rest form)))
  (if (pair? name-part)
    ; Compound: (define (name params...) body...)
    (%walk-list (rest (rest form))
      (%add-params (rest name-part) (pair (first name-part) scope))
      uses)
    ; Simple: (def name val)
    (%walk (first (rest (rest form))) (pair name-part scope) uses))))

; (set name val)
(def %walk-set (fn (form scope uses)
  (%walk (first (rest (rest form))) scope
    (%walk (first (rest form)) scope uses))))

; (guard (var handler) body...)
(def %walk-guard (fn (form scope uses)
  (def clause (first (rest form)))
  (%walk-list (rest (rest form)) scope
    (%walk (first (rest clause)) (pair (first clause) scope) uses))))

; Walk quasiquote -- only walk unquoted parts
(def %walk-quasi (fn (form scope uses)
  (if (null? form) uses
    (if (pair? form)
      (if (eq? (first form) (lit unquote))
        (%walk (first (rest form)) scope uses)
        (if (eq? (first form) (lit unquote-splicing))
          (%walk (first (rest form)) scope uses)
          (%walk-quasi (rest form) scope
            (%walk-quasi (first form) scope uses))))
      uses))))

; Walk a pair -- dispatches on %scope-table (set by lint.x)
; %walk-pair is forward-declared; lint.x provides the real implementation
; after loading construct declarations.

; Walk an AST form, collecting symbol uses
(set %walk (fn (form scope uses)
  (if (null? form) uses
    (if (symbol? form)
      (if (includes? form scope) uses
        (if (ahas? form uses) uses
          (aset form t uses)))
      (if (pair? form)
        (%walk-pair form scope uses)
        uses)))))

; --- Analysis entry point ---

; Walk a list of top-level forms, collecting defs and uses
(def %lint-forms (fn (forms defs uses)
  (if (null? forms) (list defs uses)
    (do (def form (first forms))
        (def new-defs
          (if (if (pair? form) (eq? (first form) (lit def)) ())
            (pair (first (rest form)) defs)
            defs))
        (def new-uses (%walk form () uses))
        (%lint-forms (rest forms) new-defs new-uses)))))

; Compute undefined: used but not in env-alist and not in file defs
(def %lint-undefined (fn (defs uses)
  (filter (fn (sym)
    (if (includes? sym defs) ()
      (if (ahas? sym %known-env) () t)))
    (akeys uses))))

; Compute unused: defined but not used (skip %-prefixed internals)
(def %lint-unused (fn (defs uses lib-mode)
  (if lib-mode ()
    (filter (fn (sym)
      (if (string-starts? "%" (symbol->string sym)) ()
        (if (ahas? sym uses) () t)))
      defs))))

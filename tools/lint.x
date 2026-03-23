; lint.x -- x-lang AST linter (def/use analysis)
;
; Data-driven: reads construct declarations from XEON files
; to know how each form affects scope (bindings, params, etc.).
; No hardcoded form names -- each language ships its own declarations.
;
; Uses x-lang's own env-alist for "known" symbols -- no manual
; enumeration of C primitives or library defs needed.
;
; Input order on stdin: constructs.x, lang-constructs (or ()),
; then optional %lint-lib flag, then target file forms.

(do
  ; Import the linter library (defines %walk helpers, lint-forms, etc.)
  (import x/lint)

  ; --- Load construct declarations ---

  (def %constructs (read))
  (def %lang-constructs (read))
  (def %all-constructs
    (if (null? %lang-constructs) %constructs
      (append %constructs %lang-constructs)))

  ; Build lookup alist: ((name-string . props) ...)
  (def %build-lookup (fn (_ entries acc)
    (if (null? entries) acc
      (do (def entry (first entries))
          (def name (convert (first entry) %string))
          (def props (rest entry))
          (%build-lookup (rest entries)
            (pair (pair name props) acc))))))
  (def %scope-table (%build-lookup %all-constructs ()))

  ; Lookup helper using string=? for cross-base symbol comparison
  (def %scope-find (fn (_ key table)
    (if (null? table) ()
      (if (string=? key (first (first table)))
        (first table)
        (%scope-find key (rest table))))))
  (def %scope-lookup (fn (_ name)
    (def entry (%scope-find (convert name %string) %scope-table))
    (if (null? entry) ()
      (rest entry))))

  ; Get a property value from a property list
  (def %get-prop (fn (_ key props)
    (if (null? props) ()
      (if (pair? (first props))
        (if (eq? (first (first props)) key)
          (rest (first props))
          (%get-prop key (rest props)))
        (%get-prop key (rest props))))))

  ; --- Data-driven scope dispatch ---
  ; Override %walk-pair with construct-table-driven version.

  (set! %walk-pair (fn (_ form scope uses)
    (def head (first form))
    (if (not (symbol? head)) (%walk-list form scope uses)
      (do (def props (%scope-lookup head))
          (def scope-type
            (if (null? props) () (%get-prop (lit scope) props)))
          (if (eq? scope-type (lit bind))       (%walk-def form scope uses)
          (if (eq? scope-type (lit bind-set))   (%walk-set form scope uses)
          (if (eq? scope-type (lit params))     (%walk-fn form scope uses)
          (if (eq? scope-type (lit params-env)) (%walk-op form scope uses)
          (if (eq? scope-type (lit let))        (%walk-let form scope uses)
          (if (eq? scope-type (lit guard))      (%walk-guard form scope uses)
          (if (eq? scope-type (lit quasi))
            (%walk-quasi (first (rest form)) scope uses)
          (if (eq? scope-type (lit skip))       uses
            (%walk-list form scope uses)))))))))))))

  ; Override %walk-list to use data-driven binding detection.
  ; The version in lint-lib.x hardcodes (lit def); this one uses
  ; the construct table to detect any scope=bind form.
  (set! %walk-list (fn (_ forms scope uses)
    (if (null? forms) uses
      (if (pair? forms)
        (do (def form (first forms))
            (def new-uses (%walk form scope uses))
            (def new-scope
              (if (if (pair? form) (if (symbol? (first form))
                    (do (def p (%scope-lookup (first form)))
                        (if (null? p) ()
                          (eq? (%get-prop (lit scope) p) (lit bind))))
                    ()) ())
                (do (def np (first (rest form)))
                    (pair (if (pair? np) (first np) np) scope))
                scope))
            (%walk-list (rest forms) new-scope new-uses))
        (%walk forms scope uses)))))

  ; --- Check if a form creates a top-level binding ---
  ; Data-driven: any form with scope=bind creates a definition.

  (def %is-def? (fn (_ form)
    (if (not (pair? form)) ()
      (if (not (symbol? (first form))) ()
        (do (def props (%scope-lookup (first form)))
            (if (null? props) ()
              (eq? (%get-prop (lit scope) props) (lit bind))))))))

  ; Extract the bound name from a def form.
  ; Handles (def name val) and (define (name args...) body...).
  (def %def-name (fn (_ form)
    (def name-part (first (rest form)))
    (if (pair? name-part) (first name-part) name-part)))

  ; --- Main: read target file, analyze ---

  ; First form may be a mode flag: %lint-lib suppresses unused warnings
  (def %first-form (read))
  (def %lib-mode (eq? %first-form (lit %lint-lib)))

  (def %lint-file (fn (_ defs uses)
    (def form (read))
    (if (null? form) (list defs uses)
      (do (def new-defs
            (if (%is-def? form)
              (pair (%def-name form) defs)
              defs))
          (def new-uses (%walk form () uses))
          (%lint-file new-defs new-uses)))))

  ; If first form wasn't the mode flag, analyze it too
  (def %init-defs
    (if %lib-mode ()
      (if (%is-def? %first-form)
        (list (%def-name %first-form))
        ())))
  (def %init-uses
    (if %lib-mode ()
      (%walk %first-form () ())))

  (def %result (%lint-file %init-defs %init-uses))
  (def %defs (first %result))
  (def %uses (first (rest %result)))

  ; Undefined: used but not in env-alist and not in file defs
  (def %undefined (lint-undefined %defs %uses))

  ; Unused: defined but not used (skip %-prefixed internals)
  (def %unused (lint-unused %defs %uses %lib-mode))

  ; Output
  (if (null? %undefined) ()
    (do (%stderr "Undefined:\n")
        (for-each (fn (_ s) (%stderr "  ") (%stderr s) (%stderr "\n"))
          %undefined)))

  (if (null? %unused) ()
    (do (%stderr "Unused:\n")
        (for-each (fn (_ s) (%stderr "  ") (%stderr s) (%stderr "\n"))
          %unused)))

  (if (and (null? %undefined) (null? %unused))
    (display "ok\n")
    (error (lit lint-failed))))

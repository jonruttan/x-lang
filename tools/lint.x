; lint.x -- x-lang AST linter (def/use analysis)
;
; Reports undefined symbol references and unused bindings.
;
; Uses x-lang's own env-alist for "known" symbols — no manual
; enumeration of C primitives or library defs needed.
;
; Must be wrapped in (do ...) so the interpreter reads it as one
; form and internal (read) calls consume the target file that
; follows in the stream.

(do
  ; Include the linter library (defines %walk, %lint-forms, etc.)
  (include "tools/lint-lib.x")

  ; --- Main: read target file, analyze ---

  ; First form may be a mode flag: %lint-lib suppresses unused warnings
  (def %first-form (read))
  (def %lib-mode (eq? %first-form (lit %lint-lib)))

  (def %lint-file (fn (defs uses)
    (def form (read))
    (if (null? form) (list defs uses)
      (do (def new-defs
            (if (if (pair? form) (eq? (first form) (lit def)) ())
              (pair (first (rest form)) defs)
              defs))
          (def new-uses (%walk form () uses))
          (%lint-file new-defs new-uses)))))

  ; If first form wasn't the mode flag, analyze it too
  (def %init-defs
    (if %lib-mode ()
      (if (if (pair? %first-form) (eq? (first %first-form) (lit def)) ())
        (list (first (rest %first-form)))
        ())))
  (def %init-uses
    (if %lib-mode ()
      (%walk %first-form () ())))

  (def %result (%lint-file %init-defs %init-uses))
  (def %defs (first %result))
  (def %uses (first (rest %result)))

  ; Undefined: used but not in env-alist and not in file defs
  (def %undefined (%lint-undefined %defs %uses))

  ; Unused: defined but not used (skip %-prefixed internals)
  (def %unused (%lint-unused %defs %uses %lib-mode))

  ; Output
  (if (null? %undefined) ()
    (do (%stderr "Undefined:\n")
        (for-each (fn (s) (%stderr "  ") (%stderr s) (%stderr "\n"))
          %undefined)))

  (if (null? %unused) ()
    (do (%stderr "Unused:\n")
        (for-each (fn (s) (%stderr "  ") (%stderr s) (%stderr "\n"))
          %unused)))

  (if (and (null? %undefined) (null? %unused))
    (display "ok\n")
    (error (lit lint-failed))))

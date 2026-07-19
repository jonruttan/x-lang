; lint.x -- x-lang AST linter (def/use analysis), data-driven.
;
; Reads construct declarations (XEON) to know how each form affects scope --
; no hardcoded form names; each language ships its own declarations.  Built on
; the write-stack linter (x/tool/lint): it overrides that linter's swappable
; hooks (%lint-binds?, %lint-dispatch) with construct-table versions and reuses
; lint-forms, rather than re-implementing the walk.
;
; Uses x-lang's own env-alist for "known" symbols -- no manual enumeration of
; C primitives or library defs.
;
; Input order on stdin: constructs.x, lang-constructs (or ()), then optional
; %lint-lib flag, then target file forms.

; Fetch the io plumbing prims from the catalog (ns `io` partly de-registered, R5).
(def %read (prim-ref 'io 'read))
; The bare `convert` global was homed (the conversion surface is the Convert
; class); fetch the dispatcher directly -- same door lib/x/tool/lint.x uses.
(def %lint-cvt (prim-ref 'convert 'to))

(do
  (import x/tool/lint)

  ; --- Load construct declarations ---

  (def %constructs (%read))
  (def %lang-constructs (%read))
  (def %all-constructs
    (if (null? %lang-constructs) %constructs
      (append %constructs %lang-constructs)))

  ; Convert each prop's key AND value to a string at BUILD time -- the construct
  ; symbols are fresh here (just read), so this is safe; comparing them later by
  ; eq? would dereference GC-relocated pointers and crash (the x/tool/lint rule).
  (def %props->str (fn (self props)
    (unless (null? props)
      (if (pair? (first props))
        (pair (pair (if (symbol? (first (first props))) (%lint-cvt (first (first props)) %string) "")
                    (if (symbol? (rest (first props)))  (%lint-cvt (rest (first props)) %string)  ""))
              (self (rest props)))
        (self (rest props))))))

  ; Build lookup alist: ((name-string . string-props) ...)
  (def %build-lookup (fn (_ entries acc)
    (if (null? entries) acc
      (let () (def entry (first entries))   ; scoped: tail-position defs would leak
          (def name (%lint-cvt (first entry) %string))
          (def props (%props->str (rest entry)))
          (%build-lookup (rest entries)
            (pair (pair name props) acc))))))
  (def %scope-table (%build-lookup %all-constructs ()))

  ; Lookup helper using string=? for cross-base symbol comparison
  (def %scope-find (fn (_ key table)
    (unless (null? table)
      (if (str=? key (first (first table)))
        (first table)
        (%scope-find key (rest table))))))
  (def %scope-lookup (fn (_ name)
    (def entry (%scope-find (%lint-cvt name %string) %scope-table))
    (unless (null? entry)
      (rest entry))))

  ; Get a property value (string) by string key from a string-prop list.
  (def %get-prop (fn (_ key props)
    (unless (null? props)
      (if (pair? (first props))
        (if (str=? (first (first props)) key)
          (rest (first props))
          (%get-prop key (rest props)))
        (%get-prop key (rest props))))))

  ; --- Override the linter's hooks with construct-table-driven versions ---

  ; A form introduces a binding (for sequence/top-level scope) when its head
  ; declares scope=bind.  (Replaces the old hardcoded 'def detection.)
  (set! %lint-binds? (fn (_ form)
    (when (and (pair? form) (symbol? (first form)))
      (let ((p (%scope-lookup (first form))))
        (unless (null? p)
          (let ((st (%get-prop "scope" p)))
            (unless (null? st) (str=? st "bind"))))))))

  ; Look up the head's scope-type and route to the matching analyser from the
  ; library.  (Replaces the old %walk-pair override; same scope semantics, but
  ; driven through the write-stack handlers.)  first/rest still get the literal
  ; non-list check; unknown forms are treated as function calls.
  (set! %lint-dispatch (fn (_ form)
    (def head (first form))
    (if (not (symbol? head)) (%lint-seq form)
      (let ((h (%lint-cvt head %string))
            (props (%scope-lookup head)))
        (let ((st (if (null? props) ""
                    (let ((s (%get-prop "scope" props))) (if (null? s) "" s)))))
          (match
            ((str=? st "bind")       (%lint-def form))
            ((str=? st "bind-set")   (%lint-set form))
            ((str=? st "params")     (%lint-fn form))
            ((str=? st "params-env") (%lint-op form))
            ((str=? st "let")        (%lint-let form))
            ((str=? st "guard")      (%lint-guard form))
            ((str=? st "quasi")      (%lint-quasi (rest form)))
            ((str=? st "skip")       ())
            ((str=? h "first")       (%lint-first-rest form))
            ((str=? h "rest")        (%lint-first-rest form))
            (#t                      (%lint-seq form))))))))

  ; --- Read target forms, analyze via lint-forms ---

  ; First form may be a mode flag: %lint-lib suppresses unused warnings.
  (def %first-form (%read))
  (def %lib-mode (eq? %first-form '%lint-lib))

  ; Slurp remaining forms (order is irrelevant -- defs/uses are sets).
  (def %read-all (fn (self acc)
    (def form (%read))
    (if (null? form) acc (self (pair form acc)))))
  (def %forms-rev (%read-all ()))
  (def %forms
    (if %lib-mode %forms-rev (pair %first-form %forms-rev)))

  (def %result (lint-forms %forms () ()))
  (def %defs (first %result))
  (def %uses (first (rest %result)))

  ; Undefined: used but not in env-alist and not in file defs
  (def %undefined (lint-undefined %defs %uses))

  ; Unused: defined but not used (skip %-prefixed internals)
  (def %unused (lint-unused %defs %uses %lib-mode))

  ; Output
  (unless (null? %undefined)
    (do (%stderr "Undefined:\n")
        (for-each (fn (_ s) (%stderr "  ") (%stderr s) (%stderr "\n"))
          %undefined)))

  (unless (null? %unused)
    (do (%stderr "Unused:\n")
        (for-each (fn (_ s) (%stderr "  ") (%stderr s) (%stderr "\n"))
          %unused)))

  ; Pedantic warnings (advisory -- shown but do not fail the lint): arity,
  ; call-nonfn, dup-def, malformed, shadow (lexical), unused (local).  Grouped
  ; by kind, discovered from the results so a new kind needs no change here.
  (def %warnings (lint-warnings %result))
  (def %uniq-kinds (fn (self ws acc)
    (if (null? ws) acc
      (let ((k (first (first ws))))
        (self (rest ws) (if (lint-has? k acc) acc (pair k acc)))))))
  (def %show-kind (fn (_ k)
    (%stderr "  ") (%stderr k) (%stderr ": ")
    (for-each (fn (_ s) (%stderr s) (%stderr " ")) (lint-warnings-of k %result))
    (%stderr "\n")))
  (unless (null? %warnings)
    (do (%stderr "Warnings:\n")
        (for-each %show-kind (%uniq-kinds %warnings ()))))

  (if (and (null? %undefined) (null? %unused))
    (display "ok\n")
    (error 'lint-failed)))

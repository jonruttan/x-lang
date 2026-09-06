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
      (%append %constructs %lang-constructs)))

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
  ; Cross-base lookup: table keys are strings (built by %props->str), so
  ; the canonical str=? entry lookup (%assoc-str, core/alist.x) applies.
  ; The 90-entry scan is NOT the cost at this size (a Dict variant
  ; measured SLOWER -- see the adjudication note in x/tool/lint.x); the
  ; per-query CONVERSION was (#344).  The string-keyed twin serves
  ; callers already holding the converted head (the dispatch's cell).
  (def %scope-lookup (fn (_ name)
    (def entry (%assoc-str (%lint-cvt name %string) %scope-table))
    (unless (null? entry)
      (rest entry))))
  (def %scope-lookup-str (fn (_ h)
    (def entry (%assoc-str h %scope-table))
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
            (unless (null? st)
              ; def-class binds its NAME at top level too (scope "class")
              (if (str=? st "bind") #t (str=? st "class")))))))))

  ; Look up the head's scope-type and route to the matching analyser from the
  ; library.  (Replaces the old %walk-pair override; same scope semantics, but
  ; driven through the write-stack handlers.)  first/rest still get the literal
  ; non-list check; unknown forms are treated as function calls.
  (set! %lint-dispatch (fn (_ form)
    (def head (first form))
    (if (not (symbol? head)) (Lint %lint-computed-call form)
      ; The head string comes from the list handler's cell (#344); the
      ; old code re-converted here AND inside %scope-lookup -- two more
      ; catalog dispatches per node.  Parallel let (props cannot see h),
      ; so the cell read repeats; both arms are cheap.
      (let ((h (if (null? (first %lint-head-cell)) (%lint-cvt head %string) (first %lint-head-cell)))
            (props (%scope-lookup-str (if (null? (first %lint-head-cell)) (%lint-cvt head %string) (first %lint-head-cell)))))
        (let ((st (if (null? props) ""
                    (let ((s (%get-prop "scope" props))) (if (null? s) "" s)))))
          (match
            ((str=? st "bind")       (%lint-def form))
            ((str=? st "bind-set")   (%lint-set form))
            ((str=? st "params")     (%lint-fn form))
            ((str=? st "params-env") (%lint-op form))
            ((str=? st "let")        (%lint-let form))
            ((str=? st "guard")      (%lint-guard form))
            ((str=? st "class")      (Lint %lint-class form))
            ((str=? st "quasi")      (%lint-quasi (rest form)))
            ((str=? st "skip")       ())
            ((str=? h "first")       (%lint-first-rest form))
            ((str=? h "rest")        (%lint-first-rest form))
            ; match has no scope-type (its clauses bind nothing); route by
            ; name, like first/rest, so the one-body-expression check runs
            ; under the construct-table dispatcher too.
            ((str=? h "match")       (%lint-match form))
            ((str=? h "method-ref")  (%lint-method-ref form))
            ((str=? h "doc")         (Lint %lint-doc form))
            (#t                      (%lint-call form))))))))

  ; --- Read target forms, analyze via lint-forms ---

  ; First form may be a mode flag: %lint-lib suppresses unused warnings.
  (def %first-form (%read))
  (def %lib-mode (eq? %first-form '%lint-lib))

  ; Slurp remaining forms (order is irrelevant -- defs/uses are sets).
  (def %read-all (fn (self acc)
    (def form (%read))
    (if (null? form) acc (self (pair form acc)))))
  (def %forms-rev (%read-all ()))
  (def %all-forms
    (if %lib-mode %forms-rev (pair %first-form %forms-rev)))

  ; Lint ONE file's forms; emit its findings; return #t on pass.
  ; In batch mode every line rides `out` (stdout) so the per-file blocks
  ; stay ordered; single-file mode keeps the legacy stderr findings.
  (def %lint-one (fn (_ forms emit)
    (def %result (lint-forms forms () ()))
    (def %defs (first %result))
    (def %uses (first (rest %result)))

    ; Undefined: used but not in env-alist and not in file defs
    (def %undefined (lint-undefined %defs %uses))

    ; Unused: defined but not used (skip %-prefixed internals)
    (def %unused (lint-unused %defs %uses %lib-mode))

    (unless (null? %undefined)
      (do (emit "Undefined:\n")
          (%for-each (fn (_ s) (emit "  " s "\n"))
            %undefined)))

    (unless (null? %unused)
      (do (emit "Unused:\n")
          (%for-each (fn (_ s) (emit "  " s "\n"))
            %unused)))

    ; Pedantic warnings (advisory -- shown but do not fail the lint): arity,
    ; call-nonfn, dup-def, ladder, malformed, shadow (lexical), unused (local).
    ; Grouped
    ; by kind, discovered from the results so a new kind needs no change here.
    (def %warnings (lint-warnings %result))
    (def %uniq-kinds (fn (self ws acc)
      (if (null? ws) acc
        (let ((k (first (first ws))))
          (self (rest ws) (if (lint-has? k acc) acc (pair k acc)))))))
    (def %show-kind (fn (_ k)
      (emit "  " k ": ")
      (%for-each (fn (_ s) (emit s " ")) (lint-warnings-of k %result))
      (emit "\n")))
    (unless (null? %warnings)
      (do (emit "Warnings:\n")
          (%for-each %show-kind (%uniq-kinds %warnings ()))))

    ; match-multi fails (not advisory): a clause body past the first
    ; expression can never run -- every hit is dead code with no legitimate
    ; spelling (#166), so unlike arity/shadow there is nothing to tolerate.
    (if (null? %undefined) (if (null? %unused)
      (null? (lint-warnings-of "match-multi" %result)) #f) #f)))

  ; Batch protocol (#323): the stream may hold SEVERAL files, each
  ; introduced by a (%lint-next-file "NAME") marker form the shell
  ; injects between file bodies -- one engine boot lints the whole
  ; same-preload group.  Soundness rides on the SHELL grouping only
  ; files with IDENTICAL mode+preload (a union environment would mask
  ; missing-import bugs); this loop just resets analysis state per
  ; file, which lint-forms already does at entry.  No markers = the
  ; legacy single-file behaviour, byte-for-byte.
  (def %batch-marker? (fn (_ f)
    (if (pair? f) (if (symbol? (first f))
      (str=? (%lint-cvt (first f) %string) "%lint-next-file") #f) #f)))
  (def %emit-out (fn (_ . parts) (%for-each (fn (_ p) (display p)) parts)))
  (def %emit-err (fn (_ . parts) (%for-each (fn (_ p) (%stderr p)) parts)))

  ; Split %all-forms (REVERSED file order preserved within: %read-all
  ; prepends, so forms arrive newest-first; lint-forms treats them as a
  ; set, and the marker split keys on the markers regardless of order
  ; -- walk the REVERSED list so files come out in stream order).
  (def %split (fn (self forms cur groups)
    (if (null? forms)
      (%reverse (pair (%reverse cur) groups))
      (if (%batch-marker? (first forms))
        (self (rest forms) (list (first forms))
              (pair (%reverse cur) groups))
        (self (rest forms) (pair (first forms) cur) groups)))))

  (def %groups (%split (%reverse %all-forms) () ()))

  (if (null? (rest %groups))
    ; Single file, no markers: legacy output exactly.
    (if (%lint-one (first %groups) %emit-err)
      (display "ok\n")
      (error 'lint-failed))
    ; Batch: first group is pre-marker prologue (constructs already
    ; consumed upstream; normally empty).  Each marked group prints a
    ; %%LINT%% block; the shell reassembles per-file verdicts.
    (do
      (def %any-fail (list #f))
      ; Set once a file has been linted: the sweep below runs between
      ; files, never after the last one (a single-file child would pay
      ; ~5s to free a heap the exit is about to drop anyway).
      (def %linted (list #f))
      (%for-each
        (fn (_ g)
          (unless (null? g)
            (when (%batch-marker? (first g))
              (let ((name (first (rest (first g)))))
                (do
                  ; Sweep between files.  x has no automatic GC, so without
                  ; this a child's heap grows monotonically across the
                  ; group: the live-object count at the end of a batch is
                  ; the SUM of every file's analysis garbage (a 16GB
                  ; release runner OOM-killed four such children, #622).
                  ; %all-forms pins every file's AST for the run, but the
                  ; ASTs are ~100K objects against 2-117M of per-file
                  ; analysis state, so the sweep takes the heap back to
                  ; its floor -- measured figures in the commit.
                  (when (first %linted) (Heap collect))
                  (%emit-out "%%LINT%% " name "\n")
                  (if (%lint-one (rest g) %emit-out)
                    (%emit-out "%%OK%%\n")
                    (do (%set-first! %any-fail #t)
                        (%emit-out "%%FAIL%%\n")))
                  (%set-first! %linted #t))))))
        %groups)
      (if (first %any-fail) (error 'lint-failed) ()))))

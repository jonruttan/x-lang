; cov.x -- x-lang branch coverage reporter
;
; Data-driven: reads construct declarations from XEON files
; to know which forms have branches to track (if, match, cond, etc.).
; No hardcoded form names -- each language ships its own declarations.
;
; Uses the x-cov binary which marks every evaluated AST node with
; X_OBJ_FLAG_2 (0x2). After evaluating target code, walks the AST
; to report which branches were never taken.
;
; Input order on stdin: constructs.x, lang-constructs (or ()),
; then quoted source string.

(do
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
  (def %construct-table (%build-lookup %all-constructs ()))

  ; Lookup helper using string=? for cross-base symbol comparison
  (def %construct-find (fn (_ key table)
    (if (null? table) ()
      (if (string=? key (first (first table)))
        (first table)
        (%construct-find key (rest table))))))
  (def %construct-lookup (fn (_ name)
    (def entry (%construct-find (convert name %string) %construct-table))
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

  ; --- Derive word-size and define flag access ---

  (def word-size
    (if (> (convert (convert 4294967296 %ptr) %int) 0) 8 4))

  (def %flags-offset (* 2 word-size))
  (def %cov-bit 2)

  (def obj-flags (fn (_ obj)
    (ptr-ref-word (convert obj %ptr) %flags-offset)))

  (def obj-flag-set (fn (_ obj bit)
    (ptr-set-word! (convert obj %ptr) %flags-offset
      (| (obj-flags obj) bit))
    obj))

  (def %marked? (fn (_ obj)
    (if (null? obj) t
      (> (& (obj-flags obj) %cov-bit) 0))))

  ; --- Enable extra metadata for line tracking ---

  (obj-meta-count! 1)

  ; --- Tokenize input ---

  (def %input (read))
  (def %tokens (token-read-string (%base) %input))

  ; --- Evaluate all top-level forms ---

  (def %forms %tokens)
  (def %eval-loop ())
  (set! %eval-loop (op (_ ) %e
    (if (not (null? %forms))
      (do
        (guard (err ()) (eval! (first %forms)))
        (set! %forms (rest %forms))
        (%eval-loop)))))
  (%eval-loop)

  ; --- Walk AST and report uncovered branches ---

  (def %total-branches 0)
  (def %covered-branches 0)
  (def %uncovered ())

  (def %check-branch (fn (_ kind form)
    (set! %total-branches (+ %total-branches 1))
    (if (%marked? form)
      (set! %covered-branches (+ %covered-branches 1))
      (set! %uncovered
        (pair (list kind form (obj-meta-ref form 0)) %uncovered)))))

  ; --- Per-type branch evaluators ---

  ; cond: if-style then/else branches
  (def %cond-eval (fn (_ form walk)
    (def args (rest form))
    (if (null? args) ()
      (do
        (walk (first args))
        (def then-else (rest args))
        (if (null? then-else) ()
          (do
            (def then-form (first then-else))
            (%check-branch (lit if-then) then-form)
            (walk then-form)
            (def else-rest (rest then-else))
            (if (null? else-rest) ()
              (do
                (def else-form (first else-rest))
                (%check-branch (lit if-else) else-form)
                (walk else-form)))))))))

  ; clauses: each subform is a clause with a body
  (def %clause-eval (fn (_ form walk)
    (def %walk-clauses (fn (_ clauses)
      (if (null? clauses) ()
        (if (pair? clauses)
          (do (if (pair? (first clauses))
                (do (def body (rest (first clauses)))
                    (if (null? body) ()
                      (do (def body-form (first body))
                          (%check-branch (lit clause) body-form)
                          (walk body-form))))
                ())
              (%walk-clauses (rest clauses)))
          ()))))
    (%walk-clauses (rest form))))

  ; short: each arg is a short-circuit branch (and/or)
  (def %short-eval (fn (_ form walk)
    (def %walk-args (fn (_ args)
      (if (null? args) ()
        (if (pair? args)
          (do (%check-branch (lit short-circuit) (first args))
              (walk (first args))
              (%walk-args (rest args)))
          ()))))
    (%walk-args (rest form))))

  ; guard: handler is error path, body is normal path
  (def %guard-eval (fn (_ form walk)
    (def clause (first (rest form)))
    (if (null? clause) ()
      (do
        (def handler (first (rest clause)))
        (%check-branch (lit guard-handler) handler)
        (walk handler)))
    (def %walk-body (fn (_ body)
      (if (null? body) ()
        (if (pair? body)
          (do (walk (first body))
              (%walk-body (rest body)))
          ()))))
    (%walk-body (rest (rest form)))))

  ; --- Build dispatch table from constructs ---

  (def %build-dispatch (fn (_ entries acc)
    (if (null? entries) acc
      (do (def entry (first entries))
          (def name (convert (first entry) %string))
          (def props (rest entry))
          (def branch-type (%get-prop (lit branch) props))
          (def handler
            (if (eq? branch-type (lit cond))    %cond-eval
            (if (eq? branch-type (lit clauses)) %clause-eval
            (if (eq? branch-type (lit short))   %short-eval
            (if (eq? branch-type (lit guard))   %guard-eval
              ())))))
          (%build-dispatch (rest entries)
            (if (null? handler) acc
              (pair (pair name handler) acc)))))))
  (def %dispatch (%build-dispatch %all-constructs ()))

  ; Lookup in dispatch table (string keys)
  (def %lookup (fn (_ key table)
    (if (null? table) ()
      (if (string=? key (first (first table)))
        (first table)
        (%lookup key (rest table))))))

  ; --- Generic walker ---

  (def %safe-walk ())
  (set! %safe-walk (fn (_ walk forms)
    (if (pair? forms)
      (do (walk (first forms))
          (%safe-walk walk (rest forms)))
      ())))

  (def %cov-eval ())
  (set! %cov-eval (fn (_ form)
    (if (null? form) ()
      (if (not (pair? form)) ()
        (if (not (symbol? (first form)))
          (%safe-walk %cov-eval form)
          (do
            (def handler
              (%lookup (convert (first form) %string) %dispatch))
            (if handler
              ((rest handler) form %cov-eval)
              (%safe-walk %cov-eval form))))))))

  ; Walk all top-level forms
  (for-each %cov-eval %tokens)

  ; --- Report ---

  (if (> %total-branches 0)
    (do
      (display "Branch coverage: ")
      (display %covered-branches)
      (display "/")
      (display %total-branches)
      (display "\n")

      (if (null? %uncovered)
        (display "All branches covered.\n")
        (do
          (display "Uncovered branches:\n")
          (for-each (fn (_ entry)
            (def line (first (rest (rest entry))))
            (if (> line 0)
              (do (display "  line ")
                  (display line)
                  (display ": "))
              (display "  "))
            (display (first entry))
            (display ": ")
            (write (first (rest entry)))
            (display "\n"))
            %uncovered))))
    (display "No branches to cover.\n")))

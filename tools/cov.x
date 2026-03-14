; cov.x -- x-lang branch coverage reporter
;
; Uses the x-cov binary which marks every evaluated AST node with
; X_OBJ_FLAG_2 (0x2). After evaluating target code, walks the AST
; to report which if/match/cond branches were never taken.
;
; Input: the shell wrapper pipes the file content as a quoted string
; literal after the library+coverage tool on stdin.

(do
  ; --- Derive word-size and define flag access ---

  (def word-size
    (if (> (ptr->int (int->ptr 4294967296)) 0) 8 4))

  (def %flags-offset (* 2 word-size))
  (def %cov-bit 2)

  (def obj-flags (fn (obj)
    (ptr-ref-word (obj->ptr obj) %flags-offset)))

  (def obj-flag-set (fn (obj bit)
    (ptr-set-word! (obj->ptr obj) %flags-offset
      (| (obj-flags obj) bit))
    obj))

  (def %marked? (fn (obj)
    (if (null? obj) t
      (> (& (obj-flags obj) %cov-bit) 0))))

  ; --- Enable extra metadata for line tracking ---
  ; One extra slot per object to store source line numbers.
  ; The tokenizer stamps slot 0 with the line where each token starts.

  (obj-meta-extra! 1)

  ; --- Tokenize input ---
  ; Must use (%base) so parsed symbols are interned in the current
  ; symbol table — otherwise eval won't find if/def/fn etc.

  (def %input (read))
  (def %tokens (token-read-string (%base) %input))

  ; --- Evaluate all top-level forms ---
  ; This marks the AST objects in place via x-cov's eval hook.
  ; Must use an operative (not fn) — fn closures create a scoped env
  ; that's restored after return, so def effects are lost. Operatives
  ; use dynamic scoping, so defs persist across iterations.

  (def %forms %tokens)
  (def %eval-loop ())
  (set %eval-loop (op () %e
    (if (not (null? %forms))
      (do
        (guard (err ()) (eval! (first %forms)))
        (set %forms (rest %forms))
        (%eval-loop)))))
  (%eval-loop)

  ; --- Walk AST and report uncovered branches ---

  (def %total-branches 0)
  (def %covered-branches 0)
  (def %uncovered ())

  ; Forward declarations
  (def %walk-cov ())
  (def %walk-cov-list ())

  ; Walk a list of forms
  (set %walk-cov-list (fn (forms)
    (if (null? forms) ()
      (if (pair? forms)
        (do (%walk-cov (first forms))
            (%walk-cov-list (rest forms)))
        ()))))

  ; Walk a form, checking branch coverage
  (set %walk-cov (fn (form)
    (if (null? form) ()
      (if (not (pair? form)) ()
        (do
          (def head (first form))

          ; if: check then and else branches
          (if (eq? head (lit if))
            (do
              (def args (rest form))
              (if (null? args) ()
                (do
                  ; condition
                  (%walk-cov (first args))
                  (def then-else (rest args))
                  (if (null? then-else) ()
                    (do
                      (def then-form (first then-else))
                      (set %total-branches (+ %total-branches 1))
                      (if (%marked? then-form)
                        (set %covered-branches (+ %covered-branches 1))
                        (set %uncovered (pair (list (lit if-then) then-form (obj-meta-ref then-form 0)) %uncovered)))
                      (%walk-cov then-form)

                      (def else-rest (rest then-else))
                      (if (null? else-rest) ()
                        (do
                          (def else-form (first else-rest))
                          (set %total-branches (+ %total-branches 1))
                          (if (%marked? else-form)
                            (set %covered-branches (+ %covered-branches 1))
                            (set %uncovered (pair (list (lit if-else) else-form (obj-meta-ref else-form 0)) %uncovered)))
                          (%walk-cov else-form))))))))

            ; match/cond: check each clause body
            (if (or (eq? head (lit match)) (eq? head (lit cond)))
              (for-each (fn (clause)
                (if (pair? clause)
                  (do
                    (def body (rest clause))
                    (if (null? body) ()
                      (do
                        (def body-form (first body))
                        (set %total-branches (+ %total-branches 1))
                        (if (%marked? body-form)
                          (set %covered-branches (+ %covered-branches 1))
                          (set %uncovered (pair (list (lit clause) body-form (obj-meta-ref body-form 0)) %uncovered)))
                        (%walk-cov body-form))))
                  ()))
                (rest form))

              ; Default: walk all subforms
              (%walk-cov-list form))))))))

  ; Walk all top-level forms
  (%walk-cov-list %tokens)

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
          (for-each (fn (entry)
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

; cov.x -- x-lang branch coverage reporter
;
; Uses the x-cov binary which marks every evaluated AST node with
; X_OBJ_FLAG_2 (0x2). After evaluating target code, walks the AST
; to report which if/match/cond branches were never taken.
;
; Architecture: uses a handler-dispatch pattern inspired by the type
; evaluator dispatch. Each branch form type (if, match, cond) gets
; its own evaluator function, and a generic walker dispatches to the
; appropriate one via a lookup table. New branch forms can be added
; by extending the dispatch table.
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
  ;
  ; Handler-dispatch walker: each branch form type has its own
  ; evaluator in the dispatch table. The generic walker looks up
  ; the form head and delegates to the matching evaluator.

  (def %total-branches 0)
  (def %covered-branches 0)
  (def %uncovered ())

  ; Record a branch, checking if it was covered
  (def %check-branch (fn (kind form)
    (set %total-branches (+ %total-branches 1))
    (if (%marked? form)
      (set %covered-branches (+ %covered-branches 1))
      (set %uncovered
        (pair (list kind form (obj-meta-ref form 0)) %uncovered)))))

  ; --- Per-type evaluators ---

  ; if: check then and else branches
  (def %if-eval (fn (form walk)
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

  ; match/cond: check each clause body
  (def %clause-eval (fn (form walk)
    (for-each (fn (clause)
      (if (pair? clause)
        (do
          (def body (rest clause))
          (if (null? body) ()
            (do
              (def body-form (first body))
              (%check-branch (lit clause) body-form)
              (walk body-form))))
        ()))
      (rest form))))

  ; --- Dispatch table ---
  ; Maps form head symbols to their evaluator functions.
  ; Extend this list to track coverage for new branch forms.

  (def %dispatch (list
    (pair (lit if) %if-eval)
    (pair (lit match) %clause-eval)
    (pair (lit cond) %clause-eval)))

  ; Lookup helper
  (def %lookup (fn (key table)
    (if (null? table) ()
      (if (eq? key (first (first table)))
        (first table)
        (%lookup key (rest table))))))

  ; --- Generic walker ---
  ; Dispatches to per-type evaluator or recurses into subforms.
  ; Uses safe-walk instead of for-each to handle improper lists
  ; (e.g. dotted pairs like (fn (a . b) ...) in the AST).

  (def %safe-walk ())
  (set %safe-walk (fn (walk forms)
    (if (pair? forms)
      (do (walk (first forms))
          (%safe-walk walk (rest forms)))
      ())))

  (def %cov-eval ())
  (set %cov-eval (fn (form)
    (if (null? form) ()
      (if (not (pair? form)) ()
        (do
          (def handler (%lookup (first form) %dispatch))
          (if handler
            ((rest handler) form %cov-eval)
            (%safe-walk %cov-eval form)))))))

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

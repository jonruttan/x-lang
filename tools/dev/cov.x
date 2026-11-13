; cov.x -- x-lang branch coverage reporter
;
; Runs on x-bin-profile, which marks every evaluated AST node with
; X_OBJ_FLAG_2 (0x2).  Evaluates the target's forms, then asks
; x/tool/cov's cov-branches which branches were never taken.  Which forms
; have branches comes from the construct declarations, so each language
; brings its own.
;
; Input order on stdin: constructs.x, lang-constructs (or ()),
; then quoted source string.

(def %read (prim-ref 'io 'read))
(def %obj-meta-count! (prim-ref 'obj 'meta-count!))
(def %obj-meta-ref (prim-ref 'obj 'meta-ref))

(do
  (import x/codec/xon)
  (import x/tool/cov cov-branches)

  (def %constructs (%read))
  (def %lang-constructs (%read))

  ; One metadata word an object, for the line the reader stamps.
  (%obj-meta-count! 1)

  (def %forms (Xon parse (%read)))

  ; An operative, so each form's def binds where the program's would.
  (def %todo %forms)
  (def %eval-loop ())
  (set! %eval-loop (op (_ ) %e
    (unless (null? %todo)
      (do
        (guard (err ()) (eval! (first %todo)))
        (set! %todo (rest %todo))
        (%eval-loop)))))
  (%eval-loop)

  (def %result
    (cov-branches %forms
      (if (null? %lang-constructs) %constructs
        (%append %constructs %lang-constructs))))

  (if (> (first (rest %result)) 0)
    (do
      (display "Branch coverage: " (first %result) "/" (first (rest %result)) "\n")
      (if (null? (first (rest (rest %result))))
        (display "All branches covered.\n")
        (do
          (display "Uncovered branches:\n")
          (%for-each (fn (_ entry)
            (def line (%obj-meta-ref (first (rest entry)) 0))
            (if (> line 0)
              (display "  line " line ": ")
              (display "  "))
            (display (first entry) ": ")
            (write (first (rest entry)))
            (display "\n"))
            (first (rest (rest %result)))))))
    (display "No branches to cover.\n")))

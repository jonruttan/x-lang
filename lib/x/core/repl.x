; repl.x -- Interactive read-eval-print loop
;
; Requires: operatives.x (if, do), string.x (newline, display)

(def %repl-read read)
(def %repl-prompt "> ")
(def %repl-print
  (fn (_ result)
    (if (null? result) () (write result))
    (newline)))
(doc (def repl
  (op ()
    ()
    (display %repl-prompt)
    (def %r (%repl-read))
    (if (null? %r)
      ()
      (%seq
        (guard (err (display "Error: ") (display err) (newline))
          (%repl-print (eval! %r)))
        (repl)))))
  (note "Customizable via %repl-prompt (default \"> \") and %repl-print.")
  (note "Uses dynamic scoping so def persists across iterations.")
  (note "Uses eval! (no env save/restore) so definitions persist.")
  "Start the read-eval-print loop.")

(doc (provide x/core/repl repl)
  "Start the read-eval-print loop.")

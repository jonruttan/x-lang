; repl.x -- Interactive read-eval-print loop
;
; Requires: operatives.x (if, do), string.x (newline, display)

(def %repl-read read)
(def %repl-prompt "> ")
(def %repl-print
  (fn (_ result)
    (if (null? result) () (write result))
    (newline)))
(def repl
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

(provide x/core/repl repl)

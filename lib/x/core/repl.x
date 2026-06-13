; repl.x -- Interactive read-eval-print loop
;
; Requires: operatives.x (if, do), string.x (newline, display)

; repl-read resets the source-line counter before reading, so error lines are
; relative to the current input rather than the whole boot+session stream.
; Fetch the string prims from the catalog (ns `str` is de-registered, R5).
(def %str-append (prim-ref (lit str) (lit append)))
; Fetch the io plumbing prims from the catalog (ns `io` partly de-registered, R5).
(def %error-line (prim-ref (lit io) (lit error-line)))


; ns `io` is de-registered (R5): fetch the REPL reader from the catalog.
(def %repl-read (prim-ref (lit io) (lit repl-read)))
(def %repl-prompt "> ")
(def %repl-print
  (fn (_ result)
    (if (null? result) () (write result))
    (newline)))
(doc (def repl
  (op ()
    ()
    ; On first call, reclaim terminal stdin from fd 3 (saved by x.sh
    ; before the pipe, so stdin survives ctrl-c)
    (if (Sys isatty 3)
      (do (Sys dup2 3 0) (Sys close 3))
      ())
    (set-first-int! %sigint-flag 0)
    (display %repl-prompt)
    ; Restore default SIGINT so ctrl-c at the prompt exits cleanly
    (sigint-restore)
    (def %r (%repl-read))
    ; Reinstall handler so ctrl-c during eval breaks loops
    (sigint-install)
    (if (null? %r)
      (do (newline) (Sys exit 0))
      (%seq
        (guard (err
            (set-first-int! %sigint-flag 0)
            (if (if (atom? err) (str=? (symbol->str err) "STOP") #f)
              (display "\n")
              ; %seq is BINARY (it is the primitive `do` is built on), so a
              ; flat (%seq a b c ...) would silently run only the first two and
              ; drop the rest.  Build the whole line as one string and emit it
              ; with a single binary %seq (message + newline).
              ; repl-read numbers lines relative to this input (line 1 = first
              ; line), so only show [line N] for N > 1 -- i.e. a multi-line
              ; entry where the line helps locate the error.  A one-liner just
              ; says "Error: ...".
              (%seq
                (%stderr
                  (%str-append
                    (if (> (%error-line) 1)
                      (%str-append "Error [line "
                        (%str-append (number->str (%error-line)) "]: "))
                      "Error: ")
                    (if (str? err) err (symbol->str err))))
                (%stderr "\n"))))
          (%repl-print (eval! %r)))
        (repl)))))
  (note "Customizable via %repl-prompt (default \"> \") and %repl-print.")
  (note "Uses dynamic scoping so def persists across iterations.")
  (note "Uses eval! (no env save/restore) so definitions persist.")
  "Start the read-eval-print loop.")

(doc (provide x/core/repl repl)
  "Start the read-eval-print loop.")

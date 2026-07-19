; repl.x -- Interactive read-eval-print loop
;
; Requires: operatives.x (if, do), string.x (newline, display)

; repl-read resets the source-line counter before reading, so error lines are
; relative to the current input rather than the whole boot+session stream.
; Fetch the string prims from the catalog (ns `str` is de-registered, R5).
(def %str-append (prim-ref 'str 'append))
; Fetch the io plumbing prims from the catalog (ns `io` partly de-registered, R5).
(def %error-line (prim-ref 'io 'error-line))
(def %repl-write-to-str (prim-ref 'io 'write-to-str))


; ns `io` is de-registered (R5): fetch the REPL reader from the catalog.
(def %repl-read (prim-ref 'io 'repl-read))
; The turn sweep: collect at the TOP of every repl iteration, before
; the prompt/read -- the seat is quiet (the previous turn's eval
; finished and its print completed; no reader is mid-flight), so
; everything unreachable there is turn garbage.  The first iteration's
; sweep doubles as the boot sweep (~4.2M dead objects, ~98% of the
; boot heap); later sweeps keep a session's heap at its live set, so
; long-running interaction never grows past one turn's allocations.
(def %repl-collect (prim-ref 'heap 'collect))
(def %repl-prompt "> ")
(def %repl-print
  (fn (_ result)
    (unless (null? result) (write result))
    (newline)))
(doc (def repl
  (op ()
    ()
    ; On first call, reclaim terminal stdin from fd 3 (saved by x.sh
    ; before the pipe, so stdin survives ctrl-c)
    (when (Sys isatty 3)
      (do (Sys dup2 3 0) (Sys close 3)))
    ; Turn sweep (see the module-top note).
    (%repl-collect)
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
                    ; A bare-string error reads naturally raw; EVERYTHING
                    ; else renders through the universal writer.  The old
                    ; (symbol->str err) coercion read an Err instance's
                    ; memory as a symbol name -- jon's REPL printed garbage
                    ; bytes (or strings from other subsystems) for every
                    ; structured error (#46).
                    (if (str? err) err (%repl-write-to-str err))))
                (%stderr "\n"))))
          (%repl-print (eval! %r)))
        (repl)))))
  (note "Customizable via %repl-prompt (default \"> \") and %repl-print.")
  (note "Uses dynamic scoping so def persists across iterations.")
  (note "Uses eval! (no env save/restore) so definitions persist.")
  "Start the read-eval-print loop.")

(doc (provide x/core/repl repl)
  "Start the read-eval-print loop.")

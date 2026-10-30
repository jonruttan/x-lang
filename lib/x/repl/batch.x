; batch.x -- the batch loop behind -f, -c and a piped stdin
;
; x.sh emits (batch) ahead of the program, and this reads the rest of the
; stream the way repl does: one form at a time, each evaluated under a guard.
; A raise is reported in the library's own wording, with the raise site's
; file and line when it has one, and ends the run with status 1 -- what the
; engine's own loop did, minus the location and the wording.  Nothing is
; printed for a result; -c and -f never printed one.  A -f file arrives as
; (include "FILE"), which is what tags its forms with the file and line a
; raise reports.
;
; The op evaluates its forms through eval!, as repl does, so a def persists
; from one form to the next.
(module x/repl/batch)

(import x/core/doors obj-same? str-append)
(def %batch-error-file (prim-ref (lit io) (lit error-file)))

; The prefix for a raise while a form evaluates: the file and line when the
; raise site is in a file, else bare.  repl's [line N] for a one-liner read
; from stdin is relative to the form just read, which locates nothing in a
; program; a file is the only location worth printing here.
(def %batch-prefix
  (fn (_)
    (if (str=? (%batch-error-file) "") "Error: " (%error-loc-prefix))))

(def %batch-report
  (fn (_ prefix err)
    (%stderr (str-append prefix
      (if (str? err) err (Str8 str err))))
    (%stderr "\n")
    (Sys exit 1)))

(doc (def batch
  (op ()
    ()
    ; A raise from the reader (input ending mid-form) gets a bare prefix:
    ; no form was being evaluated, so the location cells hold whatever the
    ; last evaluation left and a file:line here would lie, as repl notes.
    (let ((form (guard (err (%batch-report "Error: " err)) (%repl-read))))
      (if (obj-same? form %token-eof)
        ()
        (do
          (guard (err (%batch-report (%batch-prefix) err)) (eval! form))
          (batch))))))
  (note "Evaluates through eval!, as repl does, so definitions persist across forms.")
  (note "Ends the run at the first raise, with status 1, as the engine's loop did.")
  "Evaluate the rest of the input, one form at a time, reporting a raise with its source location.")

(doc (provide x/repl/batch (global batch))
  "The batch loop behind -f, -c and a piped stdin: forms evaluated under a guard, a raise reported with its location.")

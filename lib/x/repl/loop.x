; repl.x -- Interactive read-eval-print loop
;
; Requires: operatives.x (if, do), string.x (newline, display)

; repl-read resets the source-line counter before reading, so error lines are
; relative to the current input rather than the whole boot+session stream.
; Fetch the string prims from the catalog (ns `str` is de-registered, R5).
(def %str-append (prim-ref 'str 'append))
; Fetch the io plumbing prims from the catalog (ns `io` partly de-registered, R5).
(def %error-line (prim-ref 'io 'error-line))
(def %error-file (prim-ref 'io 'error-file))
(def %repl-write-to-str (prim-ref 'io 'write-to-str))

; The "Error [...]: " prefix for a caught error.  Prefer file:line when the
; raise site is known to be in a file (error-file is "" for stdin/REPL input);
; fall back to [line N] for a multi-line REPL entry (N > 1, worth locating);
; otherwise a bare "Error: " for a one-liner where the line adds nothing.
; The prims are cheap, idempotent base-cell reads, so they are called inline
; rather than def'd into fn-local names (which bind dynamically here).
(def %error-loc-prefix
  (fn (_)
    (if (not (str=? (%error-file) ""))
      (%str-append "Error ["
        (%str-append (%error-file) (%str-append ":"
          (%str-append (%number->str (%error-line)) "]: "))))
      (if (> (%error-line) 1)
        (%str-append "Error [line "
          (%str-append (%number->str (%error-line)) "]: "))
        "Error: "))))


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
; Ctrl-c cancel plumbing (see the read in `repl` below): identity test
; for the clean-EOF sentinel (%token-eof, bound by the C io register;
; same? is pointer identity -- eq? compares value words and could
; conflate a satom with an integer), and the buffer flush.
(def %repl-same? (prim-ref 'obj 'same?))
(def %repl-buf-reset (prim-ref 'buf 'reset))
; Private cancel marker: a fresh pair, identity-compared, so it can
; never collide with anything a read returns.
(def %repl-cancel (pair () ()))
(def %repl-prompt "> ")
(def %repl-print
  (fn (_ result)
    (unless (null? result) (write result))
    (newline)))
; The audited gap: ctrl-d was the ONLY exit, documented nowhere -- a
; stranger who does not know the EOF convention was trapped in the
; session.  A callable spelling is discoverable from the banner and help.
(doc (def quit
  (fn (_ . args)
    (Sys exit (if (eq? args ()) 0 (first args)))))
  (param status INT "Optional exit status; default 0")
  (sample "(quit)" "end the session with status 0")
  (note "Never returns: exits the process, same as ctrl-d at the prompt.")
  "End the session.")
(doc (def repl
  (op ()
    ()
    ; On first call, reclaim terminal stdin from fd 3 (saved by x.sh
    ; before the pipe, so stdin survives ctrl-c)
    (when (Sys isatty 3)
      (do (Sys dup2 3 0) (Sys close 3)))
    ; Turn sweep (see the module-top note).
    (%repl-collect)
    (%set-cell-int! %sigint-flag 0)
    (display %repl-prompt)
    ; The SIGINT handler stays installed across the read (boot installed
    ; it; no SA_RESTART, so ctrl-c pops a blocking read as EOF with
    ; %sigint-flag set).  repl-read has THREE outcomes: a value (nil
    ; included -- `()` reads as nil and simply evaluates); the clean-EOF
    ; sentinel %token-eof (real EOF, and ctrl-c at the EMPTY prompt,
    ; which arrives as EINTR -> latch -> clean EOF) -> exit; and a raised
    ; "Unterminated input" (the reader hit end of input MID-FORM).  The
    ; guard below classifies the raise: ctrl-c -> cancel the pending
    ; form and reprompt; ctrl-d / truncated pipe -> report and exit 1.
    ; The interrupted read also trips the #90 EOF latch (buffer.c
    ; poisons the CURRENT filein cell to -1); snapshot the fd per read
    ; so the cancel branch can un-poison it.  Resolved per read: filein
    ; is a chain with a cell per include.
    (def %repl-filein-cell (%reflect-base-cell 'filein))
    (def %repl-filein-fd (%cell-int (first %repl-filein-cell)))
    (def %r
      (guard (err
          ; ctrl-c is visible on TWO channels: the raw flag (the read
          ; was interrupted), or a STOP error (the eval poll saw the
          ; flag while an x-level reader handler was mid-eval -- the
          ; poll CLEARS the flag before raising).
          (if (if (= 1 (%cell-int %sigint-flag)) #t
                (if (atom? err) (str=? (symbol->str err) "STOP") #f))
            (do
              (%set-cell-int! %sigint-flag 0)
              (%set-cell-int! (first %repl-filein-cell) %repl-filein-fd)
              ; Drop bytes the tokenizer had not consumed -- stale
              ; input must not leak into the next read.  Resolved
              ; inside the body: at load time the buffer-stack head is
              ; this file's include buffer, not the session's.
              (%repl-buf-reset (%reflect-base-cell 'buffer))
              (newline)
              %repl-cancel)
            ; Not ctrl-c: ctrl-d mid-form or a truncated pipe.  The
            ; input ended inside a form -- report and end, loudly.
            ; Bare "Error: " prefix: the loc snapshot cells hold stale
            ; boot metadata for an error raised from the C reader (no
            ; form was being evaluated), so a file:line here would lie.
            (do
              (%stderr $"Error: {(if (str? err) err (%repl-write-to-str err))}\n")
              (Sys exit 1))))
        (%repl-read)))
    (if (%repl-same? %r %token-eof)
      (do (newline) (Sys exit 0))
      (if (%repl-same? %r %repl-cancel)
        (repl)
      (%seq
        (guard (err
            (%set-cell-int! %sigint-flag 0)
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
                    (%error-loc-prefix)
                    ; A bare-string error reads naturally raw; EVERYTHING
                    ; else renders through the universal writer.  The old
                    ; (symbol->str err) coercion read an Err instance's
                    ; memory as a symbol name -- jon's REPL printed garbage
                    ; bytes (or strings from other subsystems) for every
                    ; structured error (#46).
                    (if (str? err) err (%repl-write-to-str err))))
                (%stderr "\n"))))
          (%repl-print (eval! %r)))
        (repl))))))
  (note "Customizable via %repl-prompt (default \"> \") and %repl-print.")
  (note "Uses dynamic scoping so def persists across iterations.")
  (note "Uses eval! (no env save/restore) so definitions persist.")
  "Start the read-eval-print loop.")

(doc (provide x/repl/loop repl quit)
  "Start the read-eval-print loop.")

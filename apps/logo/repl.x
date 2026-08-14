; repl.x -- Logo REPL over the streaming entry reader (#157), plus batch.
(import logo/types)
; Fetch the tokenizer prims from the catalog (ns `buf`/`tok` are de-registered, R5).
(def %token-read-string (prim-ref 'tok 'read-str))

(import logo/dispatch)
(import logo/indent)
(import logo/entry)
; Fetch the io plumbing prims from the catalog (ns `io` partly de-registered, R5).
(def %read-char (prim-ref 'io 'read-char))
; Fetch the char/int casts from the catalog (ns `char`/`int` utility members de-registered, R5).
(def %integer->char (prim-ref 'int '->char))



; ============================================================
; Line reader (batch mode only -- the interactive path reads through
; the entry reader, apps/logo/entry.x)
; ============================================================

(def %read-line
  (fn ()
    (def %rl
      (fn (self acc)
        (def ch (%read-char))
        ; bytes->str, not list->str: acc holds raw input BYTES; the utf8-aware
        ; list->str would re-encode bytes >= 128, corrupting UTF-8 input.
        (if (null? ch)
          (unless (null? acc) (bytes->str (List reverse acc)))
          (if (= ch 10)
            (bytes->str (List reverse acc))
            (self (pair (%integer->char ch) acc))))))
    (%rl ())))

; ============================================================
; REPL
; ============================================================

(def %logo-prompt "? ")
(def %logo-on-exit ())
(def %logo-on-command ())

; Cancel marker: fresh pair, identity-compared.
(def %logo-cancel (pair () ()))

; True when err is the STOP atom (the eval poll's ctrl-c raise; the
; poll CLEARS %sigint-flag before raising, so both channels are tested
; wherever ctrl-c is classified).
(def %logo-stop?
  (fn (_ err)
    (if (atom? err) (str=? (symbol->str err) "STOP") #f)))

(def logo-repl
  (op ()
    ()
    ; On first call, reclaim terminal stdin from fd 3 (saved by x.sh
    ; before the pipe, so stdin survives ctrl-c)
    (when (Sys isatty 3)
      (do (Sys dup2 3 0) (Sys close 3)))
    ; The SIGINT handler stays installed permanently (boot installed
    ; it): ctrl-c pops a blocking read as EOF with %sigint-flag set,
    ; and the entry reader turns that into %logo-eof (empty prompt) or
    ; an Unterminated-input raise (mid-entry) -- the guard below
    ; classifies.  During EXECUTION the eval poll raises STOP into the
    ; eval guard.  The old restore/install dance (default SIGINT while
    ; reading) is gone: every exit path now runs %logo-on-exit, so the
    ; viewer child is never orphaned.
    (%set-cell-int! %sigint-flag 0)
    (display %logo-prompt)
    ; Snapshot %logo-base's OWN filein fd -- the interrupted read
    ; poisons THAT base's #90 latch cell, not the session's.
    (def %lr-fd-cell (%logo-filein-cell))
    (def %lr-fd (%cell-int (first %lr-fd-cell)))
    (def %entry
      (guard (err
          (if (if (= 1 (%cell-int %sigint-flag)) #t (%logo-stop? err))
            ; ctrl-c mid-entry: discard the pending entry and the
            ; partial line, un-poison the latch, fresh prompt.
            (do
              (%set-cell-int! %sigint-flag 0)
              (%set-cell-int! (first %lr-fd-cell) %lr-fd)
              (%logo-entry-flush)
              (newline)
              %logo-cancel)
            ; ctrl-d mid-entry / truncated pipe: report, clean up, end.
            (do
              (%stderr "Error: " (if (str? err) err (%repl-write-to-str err))
                       "\n")
              (unless (null? %logo-on-exit) (%logo-on-exit))
              (Sys exit 1))))
        (%logo-read-entry)))
    (if (%logo-entry-same? %entry %logo-eof)
      ; Clean EOF: ctrl-d at the prompt, pipe end, AND ctrl-c at the
      ; EMPTY prompt (EINTR -> latch -> stream end with nothing
      ; pending).  Kill the server child, then exit.
      (do (unless (null? %logo-on-exit) (%logo-on-exit))
          (newline) (Sys exit 0))
      (if (%logo-entry-same? %entry %logo-cancel)
        (logo-repl)
        (do
          (guard (err
              (%set-cell-int! %sigint-flag 0)
              (if (%logo-stop? err)
                (display "\n")
                (do
                  (%stderr "Error: "
                           (if (str? err) err (%repl-write-to-str err)) "\n"))))
            ; The entry executes EXACTLY once, here (the old
            ; completeness probe that pre-executed entries is gone).
            (logo-process-tokens (%logo-indent-to-blocks %entry))
            (unless (null? %logo-on-command) (%logo-on-command)))
          (logo-repl))))))

; ============================================================
; Batch mode (-f)
; ============================================================
;
; x.sh -f cats the program after the entry, so stdin IS the Logo file --
; and it is Logo syntax, which the C read-eval loop that resumes after
; run.x cannot parse.  Slurp stdin to EOF and push it through the same
; pipeline as LOAD (dispatch.x): tokenize, indent-to-blocks, process.
; The exit hook must run on BOTH paths -- main.x kills the forked viewer
; server through %logo-on-exit, and a batch that skips it leaves an
; orphan server holding port 8080.
(def logo-batch
  (fn (_)
    (def %lines
      (fn (self acc)
        (def line (%read-line))
        (if (null? line) (List reverse acc) (self (pair line acc)))))
    (def content (Str join "\n" (%lines ())))
    ; Handler body is MULTI-FORM (x_eval_body) -- no %seq wrapper.  The
    ; old flat 5-arg (%seq ...) ran only its first two forms (%seq is
    ; BINARY, the primitive `do` is built on): the newline, the exit
    ; hook, and (Sys exit 1) were silently dropped, so an erroring
    ; batch exited 0 and orphaned the viewer.  Caught by check-logo-tty.
    (guard (err
        (%stderr "Error: ")
        ; loop.x's formatter, not logo-repl's str/number/symbol triple:
        ; dispatch raises Err INSTANCES, and only the C writer renders those
        (%stderr (if (str? err) err (%repl-write-to-str err)))
        (%stderr "\n")
        (unless (null? %logo-on-exit) (%logo-on-exit))
        (Sys exit 1))
      (def tokens (%token-read-string %logo-base (Str append content " ")))
      (logo-process-tokens (%logo-indent-to-blocks tokens))
      (unless (null? %logo-on-exit) (%logo-on-exit)))))

(provide logo/repl
  logo-repl logo-batch %logo-on-exit %logo-on-command)

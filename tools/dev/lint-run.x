; lint-run.x -- the linter's driver: read the input and lint it.
;
; tools/dev/lint.x defines the linter, and comes in ahead of this file either
; from source or inside a state image of the library (tools/dev/lint-image.x).
; This file is what reads: the construct declarations, the mode flag and the
; target files' forms, in that order on stdin (tools/dev/lint.sh writes it).
; Its names are local, so it adds no globals to the environment being linted.

(let ()
  ; --- Load construct declarations ---
  (def constructs (%read))
  (def lang-constructs (%read))
  (set! %scope-table
    (%build-lookup
      (if (null? lang-constructs) constructs (%append constructs lang-constructs))
      ()))

  ; --- Read target forms, analyze via lint-forms ---

  ; First form may be a mode flag: %lint-lib suppresses unused warnings.
  (def first-form (%read))
  (set! %lib-mode (eq? first-form '%lint-lib))
  (def forms-rev (%read-all ()))
  (def all-forms (if %lib-mode forms-rev (pair first-form forms-rev)))
  (def groups (%split (%reverse all-forms) () ()))

  (if (null? (rest groups))
    ; Single file, no markers: legacy output exactly.
    (if (%lint-one (first groups) %emit-err)
      (display "ok\n")
      (error 'lint-failed))
    ; Batch: first batch is pre-marker prologue (constructs already
    ; consumed upstream; normally empty).  Each marked batch prints a
    ; %%LINT%% block; the shell reassembles per-file verdicts.
    (do
      (def any-fail (list #f))
      (%for-each
        (fn (_ g)
          (unless (null? g)
            (when (%batch-marker? (first g))
              (let ((name (first (rest (first g)))))
                (do
                  ; Sweep before every file -- and never after the last
                  ; one (a single-file child would pay ~5s to free a heap
                  ; the exit is about to drop anyway).  x has no automatic
                  ; GC, so without this a child's heap grows monotonically
                  ; across the batch: the live-object count at the end of
                  ; a batch is the SUM of every file's analysis garbage (a
                  ; 16GB release runner OOM-killed four such children,
                  ; #622).  Before the FIRST file the sweep drops the boot
                  ; and reader residue (~17M objects) from under the
                  ; heaviest work.  all-forms pins every file's AST for
                  ; the run, but the ASTs are ~100K objects against
                  ; 2-117M of per-file analysis state, so the sweep takes
                  ; the heap back to its floor -- figures in the commits.
                  (Heap collect)
                  (%emit-out "%%LINT%% " name "\n")
                  (if (%lint-one (rest g) %emit-out)
                    (%emit-out "%%OK%%\n")
                    (do (%set-first! any-fail #t)
                        (%emit-out "%%FAIL%%\n"))))))))
        groups)
      (if (first any-fail) (error 'lint-failed) ()))))

; proc.x -- Proc: argv-based child processes over Sys (#226)
;
; The tree grew four incompatible ways to spawn a child: raw fork/execve
; with no wait (rn.x), libc system() over a whitespace-joined command
; line (compile.x), fork/execvp/wait with the exec-failure guard
; (pin.x -- the one correct shape), and fork-without-exec plus dlsym'd
; signal calls (logo).  This class homes the correct shape once; the
; call sites keep only their policy.
;
; No shell parse: argv reaches execvp verbatim, so a path with spaces
; or quotes is one argument, not a re-split command line.

(import x/type/class)
(import x/sys/posix)

(def-class Proc ()
  (doc "Argv-based child processes: run and wait, or run and capture stdout."
    (note "Status convention: 0-255 = the child's exit code; 125 = the child died before exec (an error between fork and exec -- the child never escapes); 127 = exec never happened (command absent); 128+N = killed by signal N. Callers branch on = 127 for command-absent (the %pin-download! contract).")
    (see run!) (see capture))
  (static
    (method run! (self (param argv LIST "Command and arguments, e.g. (list \"curl\" \"-fsSL\" url)"))
      (doc "Fork/exec argv; wait; return how the child ended."
        (returns INT "Exit status; 127 = exec failed; 128+N = signal death")
        (example "(Proc run! (list \"/bin/sh\" \"-c\" \"exit 3\"))" "3"))
      ; The child must die on exec failure -- AND on any failure at all
      ; between fork and exec: an uncaught error there aborts the form
      ; and drops a SECOND INTERPRETER back into the caller's control
      ; flow, sharing the parent's stdin; under a spec batch each escaped
      ; child re-runs the remaining program and forks again -- the fork
      ; bomb that OOM-killed the 16GB CI runner. guard-everything + hard
      ; exits is the whole rule (the %pin-run! rule, homed here).
      ; 125 = died before exec; 127 = exec itself failed.
      (let ((pid (Sys fork)))
        (match
          ((= pid 0)
            (do (guard (e (Sys exit 125))
                  (Sys exec (first argv) (rest argv)))
                (Sys exit 127)))
          (#t (Sys wait pid)))))
    ; Child-side prologue for the -with variants (#364): applied between
    ; fork and exec, so it can only be env/cwd -- the two knobs subprocess
    ; callers actually need. A failed chdir must NOT exec in the wrong
    ; directory: exit 126 (the shell's cannot-execute convention).
    (method %child-prep (self (param opts ALIST "Options: (cwd . PATH) and/or (env . ((NAME . VALUE) ...))"))
      (let ((env (Assoc get 'env opts)))
        (unless (null? env)
          (List for-each (fn (_ kv) (Sys setenv (first kv) (rest kv))) env)))
      (let ((cwd (Assoc get 'cwd opts)))
        (unless (null? cwd)
          (when (< (Sys chdir cwd) 0) (Sys exit 126)))))

    (method run-with! (self (param opts ALIST "Options: (cwd . PATH) working directory, (env . ((NAME . VALUE) ...)) environment overrides -- both optional")
                            (param argv LIST "Command and arguments"))
      (doc "run! with a child-side working directory and/or environment overrides (#364). Env pairs are set on top of the inherited environment; cwd applies after them."
        (returns INT "Exit status; 126 = the cwd was unusable; 127 = exec failed; 128+N = signal death")
        (example "(Proc run-with! (list (pair 'cwd \"/tmp\")) (list \"/bin/sh\" \"-c\" \"test $(pwd) = /tmp || test $(pwd) = /private/tmp\"))" "0"))
      (let ((pid (Sys fork)))
        (match
          ((= pid 0)
            ; Same child-must-die rule as run!: any catchable failure in
            ; prep or exec exits 125 rather than escaping the fork arm.
            ; %child-prep's own (Sys exit 126) for an unusable cwd passes
            ; through -- exit is not an error.
            (do (guard (e (Sys exit 125))
                  (do (Proc %child-prep opts)
                      (Sys exec (first argv) (rest argv))))
                (Sys exit 127)))
          (#t (Sys wait pid)))))

    (method capture-with (self (param opts ALIST "Options as in run-with!")
                               (param argv LIST "Command and arguments"))
      (doc "capture with a child-side working directory and/or environment overrides (#364)."
        (returns PAIR "(status . stdout-string); status as in run-with!")
        (example "(rest (Proc capture-with (list (pair 'env (list (pair \"X364\" \"y\")))) (list \"/bin/sh\" \"-c\" \"printf %s $X364\")))" "\"y\""))
      (let ((fds (Sys pipe)))
        (let ((pid (Sys fork)))
          (match
            ((= pid 0)
              ; child-must-die rule; see run!.
              (do (guard (e (Sys exit 125))
                    (do (Sys close (first fds))
                        (Sys dup2 (rest fds) 1)
                        (Sys close (rest fds))
                        (Proc %child-prep opts)
                        (Sys exec (first argv) (rest argv))))
                  (Sys exit 127)))
            (#t
              ; Same drain-before-wait rule as capture (see its comment).
              (let ((drain (fn (self rfd acc)
                             (let ((chunk (Sys fd-read rfd 65536)))
                               (if (null? chunk) (%str-concat (%reverse acc))
                                 (self rfd (pair (bytes->str chunk) acc)))))))
                (do (Sys close (rest fds))
                    (let ((out (drain (first fds) ())))
                      (do (Sys close (first fds))
                          (pair (Sys wait pid) out))))))))))

    (method capture (self (param argv LIST "Command and arguments"))
      (doc "Fork/exec argv with stdout piped back; wait; return status and output."
        (returns PAIR "(status . stdout-string); status as in run!")
        (example "(Proc capture (list \"/bin/sh\" \"-c\" \"printf hi\"))" "(0 . \"hi\")"))
      (let ((fds (Sys pipe)))
        (let ((pid (Sys fork)))
          (match
            ((= pid 0)
              ; child-must-die rule; see run!.
              (do (guard (e (Sys exit 125))
                    (do (Sys close (first fds))
                        (Sys dup2 (rest fds) 1)
                        (Sys close (rest fds))
                        (Sys exec (first argv) (rest argv))))
                  (Sys exit 127)))
            (#t
              ; Drain the pipe BEFORE waiting: a child writing more than
              ; the pipe buffer would block forever against a parent that
              ; waits first.  bytes->str is the raw byte-packer, matching
              ; fd-read's byte list.  The drain fn rides a let binding,
              ; NOT a def: this arm is the method's tail, and a
              ; tail-position def binds globally under TCO.
              ; Chunks prepend, ONE concat when the pipe closes (#333):
              ; appending per 64KB chunk re-copied all prior output.
              (let ((drain (fn (self rfd acc)
                             (let ((chunk (Sys fd-read rfd 65536)))
                               (if (null? chunk) (%str-concat (%reverse acc))
                                 (self rfd (pair (bytes->str chunk) acc)))))))
                (do (Sys close (rest fds))
                    (let ((out (drain (first fds) ())))
                      (do (Sys close (first fds))
                          (pair (Sys wait pid) out))))))))))))

(doc (provide x/sys/proc Proc)
  (note "First consumer of Sys pipe; capture is the door callers previously lacked (curl wrote to files, cc printed to the terminal).")
  (example "(first (Proc capture (list \"/bin/sh\" \"-c\" \"exit 0\")))" "0")
  "Proc: run argv as a child process -- wait for status, or capture stdout.")

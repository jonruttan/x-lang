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
    (note "Status convention: 0-255 = the child's exit code; 127 = exec never happened (command absent); 128+N = killed by signal N. Callers branch on = 127 for command-absent (the %pin-download! contract).")
    (see run!) (see capture))
  (static
    (method run! (self (param argv LIST "Command and arguments, e.g. (list \"curl\" \"-fsSL\" url)"))
      (doc "Fork/exec argv; wait; return how the child ended."
        (returns INT "Exit status; 127 = exec failed; 128+N = signal death")
        (example "(Proc run! (list \"/bin/sh\" \"-c\" \"exit 3\"))" "3"))
      ; The child must die on exec failure or a second interpreter
      ; continues this very program (the %pin-run! rule, homed here).
      (let ((pid (Sys fork)))
        (match
          ((= pid 0)
            (do (Sys exec (first argv) (rest argv))
                (Sys exit 127)))
          (#t (Sys wait pid)))))
    (method capture (self (param argv LIST "Command and arguments"))
      (doc "Fork/exec argv with stdout piped back; wait; return status and output."
        (returns PAIR "(status . stdout-string); status as in run!")
        (example "(Proc capture (list \"/bin/sh\" \"-c\" \"printf hi\"))" "(0 . \"hi\")"))
      (let ((fds (Sys pipe)))
        (let ((pid (Sys fork)))
          (match
            ((= pid 0)
              (do (Sys close (first fds))
                  (Sys dup2 (rest fds) 1)
                  (Sys close (rest fds))
                  (Sys exec (first argv) (rest argv))
                  (Sys exit 127)))
            (#t
              ; Drain the pipe BEFORE waiting: a child writing more than
              ; the pipe buffer would block forever against a parent that
              ; waits first.  bytes->str is the raw byte-packer, matching
              ; fd-read's byte list.  The drain fn rides a let binding,
              ; NOT a def: this arm is the method's tail, and a
              ; tail-position def binds globally under TCO.
              (let ((drain (fn (self rfd acc)
                             (let ((chunk (Sys fd-read rfd 65536)))
                               (if (null? chunk) acc
                                 (self rfd (Str8 append acc (bytes->str chunk))))))))
                (do (Sys close (rest fds))
                    (let ((out (drain (first fds) "")))
                      (do (Sys close (first fds))
                          (pair (Sys wait pid) out))))))))))))

(doc (provide x/sys/proc Proc)
  (note "First consumer of Sys pipe; capture is the door callers previously lacked (curl wrote to files, cc printed to the terminal).")
  (example "(first (Proc capture (list \"/bin/sh\" \"-c\" \"exit 0\")))" "0")
  "Proc: run argv as a child process -- wait for status, or capture stdout.")

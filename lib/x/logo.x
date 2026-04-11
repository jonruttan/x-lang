; logo.x -- Logo turtle graphics with live browser viewer
;
; Usage:  ./x.sh -l logo
;
; Starts a server on localhost:8080. Open the URL in your browser.
; Type Logo commands — the browser updates live.

(def %bignum ())
(import x/num/float)
(import x/logo/turtle)
(import x/sys/posix)
(import x/logo/serve)

; --- Fork the server, continue with the REPL in the parent ---
(def %logo-port 8080)

; Write empty bytecode file before starting
(%bc-write)

; Fork server — must be one expression so child doesn't race for the pipe
(def %server-pid
  (let ((pid (sh-fork)))
    (if (= pid 0)
      (do (sh-close 0) (sh-open-read "/dev/null") (turtle-serve %logo-port))
      pid)))

; --- Hooks: append bytecodes, clear file on clearscreen ---
(set! %turtle-on-bc %bc-append)
(set! %turtle-on-clear %bc-clear)

; Kill server child when REPL exits
(set! %logo-on-exit
  (fn ()
    (ptr-call (dlsym (dlopen () 1) "kill") %server-pid 15)))

; Replace stdin (pipe) with the saved terminal fd.
; x.sh saves the original stdin as fd 3 before creating the pipe
; (exec 3<&0). After the library loads through the pipe, we dup2
; fd 3 onto fd 0 so the REPL reads from the real terminal.
; The pipe can die on ctrl-c — we don't need it anymore.
(sh-dup2 3 0)
(sh-close 3)

(display "http://localhost:") (display %logo-port) (newline)

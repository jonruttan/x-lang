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

; Reopen stdin from /dev/tty so the REPL reads directly from the terminal.
; x.sh loads this file via "cat lib/logo.x - | ./x" — a pipe. If the user
; presses ctrl-c, the shell kills cat, closing the pipe permanently. By
; switching the input fd to /dev/tty after the library has loaded, the REPL
; is no longer reading from the pipe. The terminal fd survives ctrl-c.
(def %files (rest (first (first (rest (first (%base)))))))
(def %filein (first %files))
(def %tty-fd (sh-open-read "/dev/tty"))
(if (>= %tty-fd 0) (set-first-int! %filein %tty-fd))

(display "http://localhost:") (display %logo-port) (newline)

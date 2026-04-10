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

; Write empty segments file before starting
(%segments-write)

; Fork server — must be one expression so child doesn't race for the pipe
(def %server-pid
  (let ((pid (sh-fork)))
    (if (= pid 0)
      (do (sh-close 0) (sh-open-read "/dev/null") (turtle-serve %logo-port))
      pid)))

; --- Hooks: append segments, clear file on clearscreen ---
(set! %turtle-on-segment %segment-append)
(set! %turtle-on-clear %segments-clear)

; Kill server child when REPL exits
(set! %logo-on-exit
  (fn ()
    (ptr-call (dlsym (dlopen () 1) "kill") %server-pid 15)))

(display "http://localhost:") (display %logo-port) (newline)

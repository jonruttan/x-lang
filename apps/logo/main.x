; logo.x -- Logo turtle graphics with live browser viewer
;
; Usage:  x.sh -l logo
;
; Starts a server on localhost:8080. Open the URL in your browser.
; Type Logo commands — the browser updates live.

(import-path! "apps")
(def %bignum ())
(import x/num/float)
(import logo/turtle)
(import x/sys/posix)
(import logo/serve)
; Fetch the ptr/ffi prims from the catalog (ns `ptr`/`ffi` are de-registered, R5).
(def %ptr-call (prim-ref 'ptr 'call))
(def %dlopen (prim-ref 'ffi 'dlopen))
(def %dlsym (prim-ref 'ffi 'dlsym))


; --- Fork the server, continue with the REPL in the parent ---
(def %logo-port 8080)

; Write empty bytecode file before starting
(%bc-write)

; Fork server — must be one expression so child doesn't race for the pipe.
; Skipped in batch (-f): the run exits as soon as the program is processed,
; so a server would be killed before its URL could ever be visited.  The
; bytecode file is still written -- it is the batch run's artifact.
(def %server-pid
  (unless %batch?
    (let ((pid (Sys fork)))
      (if (= pid 0)
        ; Ignore SIGINT in the server child so ctrl-c doesn't throw
        ; STOP errors in the request handler (SIG_IGN = 1, SIGINT = 2)
        (do (Sys close 0) (Sys open-read "/dev/null")
            (%ptr-call (%dlsym (%dlopen () 1) "signal") 2 1)
            (turtle-serve %logo-port))
        pid))))

; --- Hooks: append bytecodes, clear file on clearscreen ---
(set! %turtle-on-bc %bc-append)
(set! %turtle-on-clear %bc-clear)

; Kill server child when the REPL exits.  No server in batch: %logo-on-exit
; stays nil and logo-batch's unless skips it.
(unless %batch?
  (set! %logo-on-exit
    (fn ()
      (%ptr-call (%dlsym (%dlopen () 1) "kill") %server-pid 15)))
  (display "http://localhost:") (display %logo-port) (newline))

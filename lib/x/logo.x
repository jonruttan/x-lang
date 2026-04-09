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

; --- Hook: write segments after each Logo command ---
(def %orig-process logo-process-tokens)
(set! logo-process-tokens
  (fn (_ tokens)
    (def result (%orig-process tokens))
    (%segments-write)
    result))

; Register SHOW as a command (immediate browser update)
(set! %logo-commands
  (pair (list "SHOW" 0 (fn () (%segments-write)))
    %logo-commands))

(display "http://localhost:") (display %logo-port) (newline)

; logo.x -- Logo turtle graphics dialect
;
; Usage:  ./x.sh -l logo
(include "lib/x-core.x")
(include "lib/x/logo.x")

; Replace stdin (pipe) with the saved terminal fd.
; x.sh saves the original stdin as fd 3 before creating the pipe
; (exec 3<&0). After the library loads through the pipe, we dup2
; fd 3 onto fd 0 so the REPL reads from the real terminal.
; The pipe can die on ctrl-c — we don't need it anymore.
(sh-dup2 3 0)
(sh-close 3)

(logo-repl)

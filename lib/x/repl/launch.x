; launch.x -- the interactive launcher, unconditionally
;
; The dialect entries (he.x, xe.x, rn.x -- and their shims) end with a %batch?-guarded
; launcher so that -f can evaluate a file instead of starting a session.
; -F wants BOTH: evaluate the file, then hand the user a prompt.  x.sh
; concatenates this file after the -F file, so the launcher runs once the
; file's forms have been evaluated -- at which point reclaiming stdin from
; fd 3 discards nothing.
;
; Not a module: no (provide), nothing to import.  It exists to be cat'd.
(%banner)
(repl)

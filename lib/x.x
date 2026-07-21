; x.x -- the default entry, a pointer only (#95): bare `sh x.sh` boots the
; LIGHT dialect, helium.  Swap the body include to re-point the default.
; The launcher stays HERE, at stream top level: nested inside the include
; the REPL would read the file's EOF, not the session's stdin.
(include "lib/x/boot/helium.x")
(unless %batch? (do (%banner) (repl)))

; x.x -- the default entry, a pointer only (#95): bare `sh x.sh` boots the
; LIGHT dialect, helium.  Swap the body include to re-point the default.
; The launcher stays HERE, at stream top level: nested inside the include
; the REPL would read the file's EOF, not the session's stdin.
(include "lib/x/boot/helium.x")
; The launcher is lib/he.x's, line editor included; the comment there says
; why the editor is imported here and not in the boot.
(unless %batch? (do (guard (_ ()) (import x/repl/line)) (%banner) (repl)))

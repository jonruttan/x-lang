; x-or.x -- retired name for the radon dialect (#95); kept one release so
; `-l x-or` and pinned scripts keep booting.  Use lib/rn.x.  The launcher
; rides the shim, not the body: a nested (repl) reads the file's EOF.
(include "lib/x/boot/radon.x")
(unless %batch? (do (%banner) (repl)))

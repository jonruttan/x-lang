; x-and.x -- retired name for the xenon dialect (#95); kept one release so
; `-l x-and` and pinned scripts keep booting.  Use lib/xe.x.  The launcher
; rides the shim, not the body: a nested (repl) reads the file's EOF.
(include "lib/x/boot/xenon.x")
(unless %batch? (do (%banner) (repl)))

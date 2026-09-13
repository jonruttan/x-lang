; # Computational Expressions in C
;
; ## rn.x -- radon: the experimental dialect
;
; @description radon: Experimental/Hacking dialect.  x-core plus the shared
;   compiled numeric tower (lib/x/boot/tower-compiled.x), the x/rn
;   extensions, and the interactive banner/REPL.  Heavy AND radioactive:
;   xenon's surface plus raw/volatile APIs.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
(include "lib/x/boot/radon.x")
; Reclaim the tower's load burst -- the same collect, at the same moment, for
; the same reason as lib/xe.x: the entry's top level, after the include has
; returned, is the first point at which nothing is in flight.
((prim-ref (lit heap) (lit collect)))
; Interactive launcher, unless x.sh passed --batch (see repl/banner.x).
; Kept at top level -- (repl) inside the body include would read the
; file's EOF, not the session's stdin (see boot/radon.x).
; THE LINE EDITOR IS AN INTERACTIVE-ONLY COST, so it is imported here, on
; the branch that hands a session to a person, and not from the boot: it
; pulls in the dict, file and path layers, and a batch run that will never
; see a prompt should not pay for a line editor.  On load it replaces `repl`
; -- the seam x-python and x-ash already use to install a reader of their
; own -- but only when there is a terminal to edit on, so a pipe or a -f run
; reaches the C reader's loop exactly as before.  Guarded: a build without
; those modules must still start a REPL, just a plain one.
(unless %batch? (do (guard (_ ()) (import x/repl/line)) (%banner) (repl)))

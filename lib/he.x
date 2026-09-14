; # Computational Expressions in C
;
; ## he.x -- helium: the light dialect
;
; @description helium: light, fast boot, interactive, no numeric tower.
;   x-core plus the interactive banner/REPL -- today's default entry
;   (lib/x.x points here).  #95.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2021 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
(include "lib/x/boot/helium.x")
; Interactive launcher, unless x.sh passed --batch (see repl/banner.x).
; Kept at top level -- wrapping (repl) in a fn would give it that fn's
; environment, and the REPL's top-level defs must land in the global one.
; It cannot ride the body include either: the REPL reads the CURRENT
; input source, and inside an include frame that is the file's EOF, not
; the session's stdin (see boot/helium.x).
; THE LINE EDITOR IS AN INTERACTIVE-ONLY COST, so it is imported here, on
; the branch that hands a session to a person, and not from the boot: it
; pulls in the dict, file and path layers, and a batch run that will never
; see a prompt should not pay for a line editor.  On load it replaces `repl`
; -- the seam x-python and x-ash already use to install a reader of their
; own -- but only when there is a terminal to edit on, so a pipe or a -f run
; reaches the C reader's loop exactly as before.  Guarded: a build without
; those modules must still start a REPL, just a plain one.
(unless %batch? (do (guard (_ ()) (import x/repl/line)) (%banner) (repl)))

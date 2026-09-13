; # Computational Expressions in C
;
; ## xe.x -- xenon: the stable full-tower dialect
;
; @description xenon: Stable/Hardened dialect.  x-core plus the shared
;   compiled numeric tower (lib/x/boot/tower-compiled.x), the x/xe module,
;   and the interactive banner/REPL.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
(include "lib/x/boot/xenon.x")
; --- Reclaim the tower's load burst -----------------------------------------
;
; The collect that pays for the boot -- one collect, worth 99.7% of the heap;
; the measurements are in boot/xenon.x above the spot it used to occupy.  It
; is HERE, at the entry's own top level, because this is the first moment at
; which nothing is in flight: the include has returned, so no wrapper frame
; is parked in the loader's C locals (x_eval_load; x-engine-c fix/load-roots
; roots it, released engines do not), and no importer is holding anything a
; module cannot know about (the note at the end of boot/tower-compiled.x).
; An entry is fed to the engine directly and is never itself included, so
; a collect on this line has no includer to harm.
((prim-ref (lit heap) (lit collect)))
; Interactive launcher, unless x.sh passed --batch (see repl/banner.x).
; Kept at top level -- (repl) inside the body include would read the
; file's EOF, not the session's stdin (see boot/xenon.x).
; THE LINE EDITOR IS AN INTERACTIVE-ONLY COST, so it is imported here, on
; the branch that hands a session to a person, and not from the boot: it
; pulls in the dict, file and path layers, and a batch run that will never
; see a prompt should not pay for a line editor.  On load it replaces `repl`
; -- the seam x-python and x-ash already use to install a reader of their
; own -- but only when there is a terminal to edit on, so a pipe or a -f run
; reaches the C reader's loop exactly as before.  Guarded: a build without
; those modules must still start a REPL, just a plain one.
(unless %batch? (do (guard (_ ()) (import x/repl/line)) (%banner) (repl)))

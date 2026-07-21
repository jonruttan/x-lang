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
(unless %batch? (do (%banner) (repl)))

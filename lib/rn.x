; # Computational Expressions in C
;
; ## rn.x -- radon: the experimental dialect
;
; @description radon: Experimental/Hacking dialect.  x-core plus the shared
;   compiled numeric tower (lib/x/boot/tower-compiled.x), the x/rn
;   extensions, and the interactive banner/REPL.  Heavy AND radioactive:
;   xenon's surface plus raw/volatile APIs.  Retired spelling: x-or (#95).
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
(include "lib/x/boot/radon.x")
; Interactive launcher, unless x.sh passed --batch (see repl/banner.x).
; Kept at top level -- (repl) inside the body include would read the
; file's EOF, not the session's stdin (see boot/radon.x).
(unless %batch? (do (%banner) (repl)))

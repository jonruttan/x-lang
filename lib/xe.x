; # Computational Expressions in C
;
; ## xe.x -- xenon: the stable full-tower dialect
;
; @description xenon: Stable/Hardened dialect.  x-core plus the shared
;   compiled numeric tower (lib/x/boot/tower-compiled.x), the x/xe module,
;   and the interactive banner/REPL.  Retired spelling: x-and (#95).
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
(include "lib/x/boot/xenon.x")
; Interactive launcher, unless x.sh passed --batch (see repl/banner.x).
; Kept at top level -- (repl) inside the body include would read the
; file's EOF, not the session's stdin (see boot/xenon.x).
(unless %batch? (do (%banner) (repl)))

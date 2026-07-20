; # Computational Expressions in C
;
; ## x.x -- x Standard Library
;
; @description Computational Expressions in C
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2021 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
(include "lib/x-core.x")
(set! %lang-name "x-lang")
(set! %lang-version x-lib-version)
; Interactive launcher, unless x.sh passed --batch (see repl/banner.x).
; Kept at top level -- wrapping (repl) in a fn would give it that fn's
; environment, and the REPL's top-level defs must land in the global one.
(unless %batch? (do (%banner) (repl)))

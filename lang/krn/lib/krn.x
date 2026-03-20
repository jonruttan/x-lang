; # Computational Expressions in C
;
; ## krn.x -- Kernel Personality (interactive)
;
; @description Kernel language built on x-lang (extends x-core)
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
(include "lang/krn/lib/krn-base.x")
(set! %repl-prompt ">> ")
(set! %lang-name "Kernel")
(set! %lang-version x-lib-version)
(%banner)
(repl)

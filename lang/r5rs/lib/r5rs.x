; # Computational Expressions in C
;
; ## r5rs.x -- R5RS Scheme Personality (interactive)
;
; @description R5RS-compatible Scheme built on x-lang
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2024 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
(include "lang/r5rs/lib/r5rs-base.x")
(set! %lang-name "R5RS Scheme")
(set! %lang-version x-lib-version)
(%banner)
(repl)

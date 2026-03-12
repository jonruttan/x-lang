; # Computational Expressions in C
;
; ## r7rs.x -- R7RS Scheme Personality (interactive)
;
; @description R7RS-compatible Scheme built on x-lang (extends R5RS)
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2024 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
(include "lang/r7rs/lib/r7rs-base.x")
(set %lang-name "R7RS Scheme")
(set %lang-version x-lib-version)
(%banner)
(repl)

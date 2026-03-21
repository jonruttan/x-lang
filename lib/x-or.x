; # Computational Expressions in C
;
; ## x-or.x -- x/or Standard Library
;
; @description x/or: Experimental/Hacking dialect
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2021 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
(include "lib/x-base.x")
; Pre-register heavy module paths
(set-first! %include-list-cell
  (pair "lib/x/posix.x"
  (pair "lib/x/hash.x"
  (pair "lib/x/compile.x"
  (pair "lib/x/or.x"
    (first %include-list-cell))))))
(include "lib/x/or.x")
(set! %lang-name "x-or")
(set! %lang-version x-lib-version)
(%banner)
(repl)

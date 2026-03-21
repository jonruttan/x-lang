; # Computational Expressions in C
;
; ## x-and.x -- x/and Standard Library
;
; @description x/and: Stable/Hardened dialect
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
  (pair "lib/x/and.x"
    (first %include-list-cell))))))
(include "lib/x/and.x")
(set! %lang-name "x-and")
(set! %lang-version x-lib-version)
(%banner)
(repl)

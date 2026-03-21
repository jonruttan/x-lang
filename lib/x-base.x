; # Computational Expressions in C
;
; ## x-base.x -- x Standard Library (non-interactive)
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
(do
  ; Pre-register paths so import calls within these files are no-ops
  (set-first! %include-list-cell
    (pair "lib/x/regex.x"
    (pair "lib/x/float.x"
    (pair "lib/x/rational.x"
    (pair "lib/x/complex.x"
      (first %include-list-cell))))))
  (include "lib/x/regex.x")
  (include "lib/x/float.x")
  (include "lib/x/rational.x")
  (include "lib/x/complex.x"))

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
    (pair "lib/x/num/bignum.x"
    (pair "lib/x/sys/regex.x"
    (pair "lib/x/num/float.x"
    (pair "lib/x/num/rational.x"
    (pair "lib/x/num/complex.x"
    (pair "lib/x/core/hash.x"
      (first %include-list-cell))))))))
  (include "lib/x/num/bignum.x")
  (include "lib/x/sys/regex.x")
  (include "lib/x/num/float.x")
  (include "lib/x/num/rational.x")
  (include "lib/x/num/complex.x")
  (include "lib/x/core/hash.x")
  ())

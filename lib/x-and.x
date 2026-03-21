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
; Load core first (fast, no numeric tower)
(include "lib/x-core.x")
; Pre-register all heavy module paths
(set-first! %include-list-cell
  (pair "lib/x/posix.x"
  (pair "lib/x/hash.x"
  (pair "lib/x/compile.x"
  (pair "lib/x/bignum.x"
  (pair "lib/x/regex.x"
  (pair "lib/x/float.x"
  (pair "lib/x/rational.x"
  (pair "lib/x/complex.x"
  (pair "lib/x/and.x"
    (first %include-list-cell)))))))))))
; Load compiler infrastructure FIRST (before numeric tower)
(include "lib/x/posix.x")
(include "lib/x/hash.x")
(include "lib/x/compile.x")
; Load numeric tower (analysers will be compiled after)
(include "lib/x/bignum.x")
(include "lib/x/regex.x")
(include "lib/x/float.x")
(include "lib/x/rational.x")
(include "lib/x/complex.x")
; Load x-and module
(include "lib/x/and.x")
(set! %lang-name "x-and")
(set! %lang-version x-lib-version)
(%banner)
(repl)

; # Computational Expressions in C
;
; ## r7rs.x -- R7RS Scheme Personality
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

(include "lang/r5rs/lib/r5rs-base.x")

(begin
  ; --- x-lang native constructs ---
  (include "lang/r7rs/lib/x/case-lambda.x")
  (include "lang/r7rs/lib/x/promises.x")
  (include "lang/r7rs/lib/x/records.x")
  (include "lang/r7rs/lib/x/params.x")
  (include "lang/r7rs/lib/x/cond-expand.x")

  ; --- Scheme standard library ---
  (include "lang/r7rs/lib/scm/equiv.scm")
  (include "lang/r7rs/lib/scm/numeric.scm")
  (include "lang/r7rs/lib/scm/char.scm")
  (include "lang/r7rs/lib/scm/string.scm")
  (include "lang/r7rs/lib/scm/list.scm")
  (include "lang/r7rs/lib/scm/vector.scm")
  (include "lang/r7rs/lib/scm/error.scm")
  (include "lang/r7rs/lib/scm/control.scm")
  (include "lang/r7rs/lib/scm/ports.scm")
)

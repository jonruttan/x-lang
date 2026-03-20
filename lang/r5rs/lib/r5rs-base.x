; # Computational Expressions in C
;
; ## scm.x -- Scheme Personality
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

(include "lib/x-core.x")

; Native compiler for tokenizer callbacks (requires posix.x)
; Must load before derived.scm redefines 'do' from begin to R5RS iteration
(include "lib/x/posix.x")
(include "lib/x/hash.x")
(include "lib/x/compile.x")

; Tokenizer types: compiled to native code for fast tokenization
; %prim-read: raw read primitive (before ports.scm wraps it)
; %ellipsis-sym: the ... symbol (normally defined in macro.scm)
(def %prim-read read)
(def %ellipsis-sym (string->symbol "..."))
(include "lang/r5rs/lib/x/syntax.x")

(do
  ; --- x-lang aliases for Scheme naming ---
  (include "lang/r5rs/lib/x/aliases.x")

  ; --- Float support ---
  (include "lib/x/float.x")

  ; --- Numeric tower ---
  (include "lib/x/rational.x")
  (include "lib/x/complex.x")

  ; --- string->number: try integer first, then float ---
  (def %string->number-int string->number)
  (def %string->number-try-float
    (fn (s)
      (def %raw (string->float s))
      (if (= %raw 0)
        (if (= (string-ref s 0) (string-ref "0" 0))
          (make-instance %float 0)
          ())
        (make-instance %float %raw))))
  (def string->number
    (fn (s . rest)
      (if (not (null? rest))
        (%string->number-int s (first rest))
        (if (= (string-length s) 0) ()
          (let ((%r (%string->number-int s)))
            (if %r %r (%string->number-try-float s)))))))

  ; --- Derived expression types ---
  (include "lang/r5rs/lib/scm/derived.scm")

  ; --- Equivalence predicates ---
  (include "lang/r5rs/lib/scm/equiv.scm")

  ; --- List operations ---
  (include "lang/r5rs/lib/scm/list.scm")

  ; --- Character operations ---
  (include "lang/r5rs/lib/scm/char.scm")

  ; --- String operations ---
  (include "lang/r5rs/lib/scm/string.scm")

  ; --- Numeric operations ---
  (include "lang/r5rs/lib/scm/numeric.scm")

  ; --- Control features ---
  (include "lang/r5rs/lib/scm/control.scm")

  ; --- Port system ---
  (include "lang/r5rs/lib/scm/ports.scm")

  ; --- Hygienic macros ---
  (include "lang/r5rs/lib/scm/macro.scm")
)

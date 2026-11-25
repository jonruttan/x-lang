; decimal/literal.x -- the decimal literal: 1.5d, -0.001d, 3d, 1.5e-8d
;
; Importing this module installs the literal on the base that imports it:
; an analyse handler and a read handler on the DECIMAL type.  x/num/decimal
; is the library -- the type, its arithmetic, its conversions, its printer --
; and installs no reader syntax, so a program may have decimals without
; 1.5d meaning one in the text it reads.
;
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

(module x/num/decimal/literal)
(import x/core/doors buf-tok type-push-analyse)
(import x/num/decimal Decimal decimal-type)

; --- Tokenizer state machine: [+-]?DIGITS[.DIGITS][eE[+-]DIGITS]d ---
;
; The states are module-level defs, not inline closures, for the reason
; every other tower stage records: the compiled analyser in
; boot/tower-compiled.x captures them as free variables once, and an
; anonymous closure there is rooted by nothing after the compile's
; free-variable alist is cleared (#49).
;
; Only the terminal `d` scores, and the score covers the suffix, so 1.5d
; (4 chars) outbids float's 1.5 (3) on the same run.  Without the suffix
; nothing here scores at all and the float reader keeps the token.
;
; dec-int, dec-frac and dec-exp-digits have compiled twins in
; boot/tower-compiled.x that must agree with them form for form, so a
; change to one of them here is a change there.

(def dec-exp-digits ())
(set! dec-exp-digits
  (fn (_ buffer score chr)
    (if (and (>= chr 48) (<= chr 57)) dec-exp-digits
      (if (= chr 100) (%score-set score 1 buffer) ()))))

(def %dec-exp-first
  (fn (_ buffer score chr)
    (if (and (>= chr 48) (<= chr 57)) dec-exp-digits ())))

(def dec-exp-sign
  (fn (_ buffer score chr)
    (if (and (>= chr 48) (<= chr 57)) dec-exp-digits
      (if (or (= chr 45) (= chr 43)) %dec-exp-first ()))))

(def dec-frac ())
(set! dec-frac
  (fn (_ buffer score chr)
    (match
      ((and (>= chr 48) (<= chr 57)) dec-frac)
      ((= chr 100) (%score-set score 1 buffer))
      ((or (= chr 101) (= chr 69)) dec-exp-sign)
      (#t ()))))

(def dec-first-frac
  (fn (_ buffer score chr)
    (if (and (>= chr 48) (<= chr 57)) dec-frac ())))

(def dec-int ())
(set! dec-int
  (fn (_ buffer score chr)
    (match
      ((and (>= chr 48) (<= chr 57)) dec-int)
      ((= chr 100) (%score-set score 1 buffer))
      ((= chr 46) dec-first-frac)
      ((or (= chr 101) (= chr 69)) dec-exp-sign)
      (#t ()))))

; A lone sign must see a digit next, so `-` and `+` stay operators.
(def dec-sign
  (fn (_ buffer score chr)
    (if (and (>= chr 48) (<= chr 57)) dec-int ())))

; The entry test: a digit starts the integer part, a sign must see a digit.
(def %dec-literal-analyse
  (fn (_ buffer score chr)
    (if (and (>= chr 48) (<= chr 57)) dec-int
      (if (or (= chr 45) (= chr 43)) dec-sign ()))))

; The token's text is read by the library's own door from text, so the
; reader and (Decimal from "...") share one parser.
; The door is fetched once: a tokenizer callback does not dispatch on a class
; (lib/x/type/io.x).
(def %dec-from (class-static-ref Decimal (lit from)))
(def %dec-literal-read
  (fn (_ . args) (%dec-from Decimal (buf-tok (first args)))))

(type-push-analyse decimal-type %dec-literal-analyse)
((prim-ref (lit type) (lit push-read)) decimal-type %dec-literal-read)

(doc (provide x/num/decimal/literal
  dec-int dec-first-frac dec-frac dec-exp-sign dec-exp-digits dec-sign)
  (note "Only the terminal d scores, and the score covers the suffix, so 1.5d outbids float's 1.5 on the same digits; a run without the suffix is never contested.")
  (note "The exported names are the analyser's states, which boot/tower-compiled.x compiles in place.")
  (sample "(import x/num/decimal/literal)" "1.5d now reads as a decimal on this base")
  "The decimal literal 1.5d, installed on the importing base's DECIMAL type.")

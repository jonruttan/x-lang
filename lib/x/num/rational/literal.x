; rational/literal.x -- the rational literal: 1/3, -2/7
;
; Importing this module installs the literal on the base that imports it:
; an analyse handler and a read handler on the RATIONAL type.  x/num/rational
; is the library -- the type, its arithmetic, its conversions, its printer --
; and installs no reader syntax.
;
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

(module x/num/rational/literal)
(import x/core/doors buf-tok type-push-analyse)
(import x/num/rational rational rational-type)

(def %cvt (prim-ref (lit convert) (lit to)))

; --- Tokenizer state machine: [+-]?[0-9]+/[0-9]+ ---
; After '/' — must see at least one digit

(def rat-denom ())

(set! rat-denom
  (fn (_ buffer score chr)
    (if (and (>= chr 48) (<= chr 57))
      (%seq (%score-set score 1 buffer) rat-denom)
      (%seq (%buffer-unread buffer) (%score-set score 1 buffer)))))

(def rat-first-denom
  (fn (_ buffer score chr)
    (if (and (>= chr 48) (<= chr 57))
      (%seq (%score-set score 1 buffer) rat-denom)
      ())))
; Integer digits before '/'

(def rat-numer ())

(set! rat-numer
  (fn (_ buffer score chr)
    (if (and (>= chr 48) (<= chr 57))
      rat-numer
      (if (= chr 47) rat-first-denom ()))))

; The state after a leading sign: digits continue into the numerator, anything
; else rejects. A module-level def, NOT an inline closure, for two reasons --
; the interpreted analyser below would otherwise allocate a fresh closure on
; every '-'/'+' char it sees, and the COMPILED analyser in
; boot/tower-compiled.x captures this value ONCE as a free variable. An
; anonymous closure there is rooted by nothing after the compile's free-variable alist is cleared,
; so a later collect frees the code the compiled analyser jumps to (#49).
; Every other tower stage already uses a module-level def for its sign state
; (%big-sign-state, %int-capped-sign, %float-neg-int, %cx-neg); rational was
; the odd one out.
(def rat-sign
  (fn (_ buffer score chr)
    (if (and (>= chr 48) (<= chr 57)) rat-numer ())))
(def %rat-literal-analyse
  (fn (_ buffer score chr)
    (match
      ((and (>= chr 48) (<= chr 57)) rat-numer)
      ((= chr 45) rat-sign)
      ((= chr 43) rat-sign)
      (#t ()))))

; The token's text goes through the library's own conversion from text, so
; the reader and (Convert to "1/3" (Rational type)) share one parser.
(def %rat-literal-read
  (fn (_ . args) (%cvt (buf-tok (first args)) rational)))

(type-push-analyse rational-type %rat-literal-analyse)
((prim-ref (lit type) (lit push-read)) rational-type %rat-literal-read)

(doc (provide x/num/rational/literal
  rat-numer rat-denom rat-first-denom rat-sign)
  (note "The literal outscores the integer reader on the same digits by the slash and the denominator.")
  (note "The exported names are the analyser's states, which boot/tower-compiled.x compiles in place.")
  (sample "(import x/num/rational/literal)" "1/3 now reads as a rational on this base")
  "The rational literal 1/3, installed on the importing base's RATIONAL type.")

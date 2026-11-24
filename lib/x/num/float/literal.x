; float/literal.x -- the float literal: 3.14, -0.5, 1.0e-5
;
; Importing this module installs the literal on the base that imports it:
; an analyse handler and a read handler on the FLOAT type.  x/num/float
; is the library -- the type, its arithmetic, its conversions, its printer --
; and installs no reader syntax.
;
; The states are x/num/float's, which reads text converted to a float by
; them; this module puts the same states on the program's reader.
;
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

(module x/num/float/literal)
(import x/core/doors buf-tok type-make-instance type-push-analyse)
(import x/num/float float float-type str->float)

; Entry: a digit, or '-' followed by a digit.  The literal's score is its
; length, so 3.14 (4) outscores the integer reader's 3 (1).
;
; Made in x/num/float's frame, so that the states it hands back are the
; ones bound there when it is called: boot/tower-compiled.x rebinds them to
; their compiled forms in that frame, and a copy imported here would stay
; the interpreted one.
(def %float-literal-analyse
  (eval (lit (fn (_ buffer score chr)
               (if (and (>= chr 48) (<= chr 57))
                 float-int-digits
                 (if (= chr 45) float-neg-int ()))))
        (module x/num/float)))

; The token's text is strtod's to read.
(def %float-literal-read
  (fn (_ . args)
    (type-make-instance float (str->float (buf-tok (first args))))))

(type-push-analyse float-type %float-literal-analyse)
((prim-ref (lit type) (lit push-read)) float-type %float-literal-read)

(doc (provide x/num/float/literal)
  (note "The exponent wants a point before it, so 1e3 is no float; the printer writes a point before every exponent to match.")
  (sample "(import x/num/float/literal)" "3.14 now reads as a float on this base")
  "The float literal 3.14, installed on the importing base's FLOAT type.")

; regex/literal.x -- the regex literal: #/pattern/
;
; Importing this module installs the literal on the base that imports it.
; x/type/regex is the library and installs no reader syntax.
;
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

(module x/type/regex/literal)
(import x/core/doors buf-tok type-by-atom type-of type-push-analyse)
(import x/type/regex Regex)

; After #, a / opens the pattern; it runs to the next / that no backslash
; stands before.  The states are module-level defs, so reading a # makes no
; closure.
(def %regex-scan-escape ())

(def %regex-scan-body
  (fn (self buffer score chr)
    (match
      ((= chr #\/) (%score-set score 1 buffer))
      ((= chr #\\) %regex-scan-escape)
      (#t self))))

(set! %regex-scan-escape
  (fn (_ _ _ _)
    %regex-scan-body))

(def %regex-after-hash
  (fn (_ buffer score chr) (if (= chr #\/) %regex-scan-body ())))

(def %regex-literal-analyse
  (fn (_ buffer score chr) (if (= chr #\#) %regex-after-hash ())))

; The token without its #/ and its closing /, compiled by the library's own
; door from text.  The door is fetched once: a tokenizer callback does not
; dispatch on a class (lib/x/type/io.x).
(def %regex-compile (class-static-ref Regex (lit compile)))
(def %regex-literal-read
  (fn (_ . args)
    (let ((tok (buf-tok (first args))))
      (%regex-compile Regex (%substring tok 2 (- (%str-length tok) 1))))))

(def %regex-type (type-by-atom (type-of (Regex compile "x"))))
(type-push-analyse %regex-type %regex-literal-analyse)
((prim-ref (lit type) (lit push-read)) %regex-type %regex-literal-read)

(doc (provide x/type/regex/literal)
  (sample "(import x/type/regex/literal)" "#/[0-9]+/ now reads as a regex on this base")
  "The regex literal #/pattern/, installed on the importing base's REGEX type.")

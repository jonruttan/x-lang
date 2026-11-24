; bigint/literal.x -- the bigint literal: an integer past the native range
;
; Importing this module installs the literal on the base that imports it:
; an analyse handler and a read handler on the BIGINT type.  x/num/bigint
; is the library -- the type, its arithmetic, its conversions, its printer --
; and installs no reader syntax.
;
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

; It also caps the INTEGER type's own reader, which is what hands a long run
; of digits to this one.

(module x/num/bigint/literal)
(import x/core/doors buf-tok int< type-by-atom type-of type-push-analyse)
(import x/num/bigint bigint bigint-type)

(def %cvt (prim-ref (lit convert) (lit to)))

; The count of decimal digits an integer always fits in: two a byte.
(def %int-max-digits (* %word-size 2))

; Analyser: consumes [+-]?[0-9]+ but only scores when too many digits for int
(def big-digits ())
(set! big-digits
  (fn (_ buffer score chr)
    (if (if (>= chr 48) (<= chr 57) #f)
      big-digits
      (do (%buffer-unread buffer)
          ; Only score if digit count exceeds native integer range
          (if (int< %int-max-digits (%buffer-len buffer))
            (%score-set score 1 buffer)
            ())))))

(def big-sign-state
  (fn (_ buffer score chr)
    (if (if (>= chr 48) (<= chr 57) #f)
      big-digits
      ())))

(def %big-analyse
  (fn (_ buffer score chr)
    (if (if (>= chr 48) (<= chr 57) #f)
      big-digits
      (if (if (= chr 45) #t (= chr 43))
        big-sign-state
        ()))))

; The token's text goes through the library's own conversion from text, which
; answers a plain integer for a 17 to 19 digit literal that fits the word.
(def %big-literal-read
  (fn (_ . args) (%cvt (buf-tok (first args)) bigint)))

(type-push-analyse bigint-type %big-analyse)
((prim-ref (lit type) (lit push-read)) bigint-type %big-literal-read)

; --- Cap the integer analyser ---
; Push a capped analyser onto the integer type's analyse stack
; that rejects numbers with too many digits for native int

(def %int-type (type-by-atom (type-of 0)))

(def int-capped-digits ())
(set! int-capped-digits
  (fn (_ buffer score chr)
    (if (if (>= chr 48) (<= chr 57) #f)
      int-capped-digits
      (do (%buffer-unread buffer)
          (if (not (int< %int-max-digits (%buffer-len buffer)))
            (%score-set score 1 buffer)
            ())))))

; Hex literals (#507): a leading 0 may open 0x/0X, and the engine's own
; xdigits machine is shadowed by this push, so the cap must read hex too.
; "0x" plus 16 hex digits fills the 64-bit word, so the cap is 18 bytes;
; a bare "0x" declines (no digit was consumed).  Character constants
; throughout: chr arrives as the character CODE and eq?/< compare
; operand words (engine law 1), so #\x and 120 are the same test.
(def %int-capped-xdigits ())
(set! %int-capped-xdigits
  (fn (_ buffer score chr)
    (match
      ((if (>= chr #\0) (<= chr #\9) #f) %int-capped-xdigits)
      ((if (>= chr #\a) (<= chr #\f) #f) %int-capped-xdigits)
      ((if (>= chr #\A) (<= chr #\F) #f) %int-capped-xdigits)
      (#t (do (%buffer-unread buffer)
              (if (not (int< 18 (%buffer-len buffer)))
                (%score-set score 1 buffer)
                ()))))))

(def %int-capped-xfirst
  (fn (_ buffer score chr)
    (match
      ((if (>= chr #\0) (<= chr #\9) #f) %int-capped-xdigits)
      ((if (>= chr #\a) (<= chr #\f) #f) %int-capped-xdigits)
      ((if (>= chr #\A) (<= chr #\F) #f) %int-capped-xdigits)
      (#t ()))))

(def int-capped-base
  (fn (_ buffer score chr)
    (if (if (= chr #\x) #t (= chr #\X))
      %int-capped-xfirst
      (int-capped-digits buffer score chr))))

(def int-capped-sign
  (fn (_ buffer score chr)
    (if (= chr #\0)
      int-capped-base
      (if (if (>= chr #\1) (<= chr #\9) #f)
        int-capped-digits
        ()))))

(def %int-capped-analyse
  (fn (_ buffer score chr)
    (match
      ((= chr #\0) int-capped-base)
      ((if (>= chr #\1) (<= chr #\9) #f) int-capped-digits)
      ((if (= chr #\-) #t (= chr #\+)) int-capped-sign)
      (#t ()))))


(type-push-analyse %int-type %int-capped-analyse)

(doc (provide x/num/bigint/literal
  big-digits big-sign-state int-capped-base int-capped-digits int-capped-sign)
  (note "The INTEGER type's reader is capped at the digits a word always holds, hex included, so a longer run is this literal's.")
  (note "The exported names are the analyser's states, which boot/tower-compiled.x compiles in place.")
  (sample "(import x/num/bigint/literal)" "18446744073709551616 now reads as a bigint on this base")
  "The bigint literal, installed on the importing base's BIGINT and INTEGER types.")

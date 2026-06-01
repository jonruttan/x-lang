; str/utf8.x -- StrUTF8: the UTF-8 code-point string class
(import x/protocol/str/str8)
(import x/codec/utf8)

; StrUTF8 reinterprets the SAME bytes as Str8, but one whole UTF-8 sequence per
; element, yielding the decoded code point as a CHARACTER. It inherits the full
; string suite from Str8 (append, join, contains?, split, trim, =?, <?, ...) --
; written once through self primitives -- and overrides ONLY the primitives that
; change with the encoding:
;   length      : code-point count (cursor walk), not Str8's O(1) byte length
;   index       : decode to the i-th CODE POINT (O(n) walk)
;   sub         : substring of `len` CODE POINTS from code-point offset `start`
;   step        : consume one UTF-8 sequence per element
;   char->bytes : encode a code point to its 1-4 UTF-8 bytes (inverse of step)
; All byte access goes through the inherited Str8 byte primitives + the shared
; codec (x/codec/utf8); index/sub are O(n) (inherent to variable-width random
; access -- prefer ->list / cursor traversal to visit every element).

; Byte offset of code-point index k: advance k whole sequences from byte `from`.
(def %u8-byte-offset
  (fn (self s k from)
    (if (= k 0) from
      (self s (- k 1) (rest (utf8-decode s from))))))

(def-class StrUTF8 (extends Str8)
  (static
    (method length (self v) (self count v))   ; code points, via Seq's cursor walk

    (method index (self v i)
      (integer->char (first (utf8-decode v (%u8-byte-offset v i 0)))))

    (method sub (self v start len)
      (def b0 (%u8-byte-offset v start 0))
      (def b1 (%u8-byte-offset v len b0))
      (str-byte-sub v b0 (- b1 b0)))

    (method step (self v cur)
      (let ((d (utf8-decode v cur)))
        (pair (integer->char (first d)) (rest d))))

    ; encode: a code point -> its UTF-8 bytes (inverse of step)
    (method char->bytes (self el) (utf8-encode (char->integer el)))))

; Utf8 = alias for the UTF-8 protocol class.
(def Utf8 StrUTF8)

; Str = the AMBIENT string protocol. The default is UTF-8 (code points): the
; bare string call (s i), the str-* API, and str->list all work in code points
; out of the box. Str8 and StrUTF8 always name their fixed protocols; rebind
; Str (e.g. (def Str Str8)) to change the active protocol for the whole str-*
; library at once.
(def Str StrUTF8)

(provide x/protocol/str/utf8 StrUTF8 Utf8 Str)

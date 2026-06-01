; string.x -- DEPRECATED. Low-level UTF-8 string<->list conversions only.
;
; The string LIBRARY moved to x/type/str (the str-* API, in the active protocol)
; and the protocol classes x/protocol/str/str8 (Str8) and x/protocol/str/utf8
; (StrUTF8). This module survives only for two reasons:
;   1. It loads early in boot (right after the UTF-8 codec, before the object
;      system), so it is the home for the code-point list<->string transform
;      that boot code (number->str, sys/convert) needs before classes exist.
;   2. Back-compat: `import x/type/string` still works and re-exports the str-*
;      API from x/type/str.
;
; New code should `import x/type/str` (or use Str8 / StrUTF8 directly).
(import x/type/char)
(import x/core/list)
(import x/codec/utf8)

; list->str: list of code-point CHARACTERs -> UTF-8 string. The C primitive of
; this name is the dumb byte-packer (bytes->str, one low byte per char); this
; redefines it to be code-point aware -- each char is UTF-8 encoded via the
; shared codec, then byte-packed. Exact inverse of str->list, so
; (list->str (str->list s)) round-trips any UTF-8 string. (No UTF-8 in C: C
; packs bytes; the x-lang layer owns the byte<->code-point transform.)
(doc (def list->str
  (fn (_ chars)
    (bytes->str
      (map integer->char
        (fold (fn (_ acc ch) (append acc (utf8-encode (char->integer ch))))
              () chars)))))
  (param chars LIST "List of CHARACTERs (Unicode code points)")
  (returns STRING "UTF-8 string encoding each code point")
  (example "(list->str (list #\\$ #\\€))" "\"$€\"")
  "Build a UTF-8 string from a list of code-point characters. Inverse of str->list.")

(doc (def str->list
  (fn (_ s)
    (def len (str-length s))
    (let go ((i 0) (acc ()))
      (if (>= i len)
        (reverse acc)
        (do
          (def d (utf8-decode s i))
          (go (rest d) (pair (integer->char (first d)) acc)))))))
  (param s STRING "String to decode")
  (returns LIST "List of CHARACTERs, one per Unicode code point")
  (example "(str->list \"$¢€\")" "(#\\$ #\\¢ #\\€)")
  "Decode a UTF-8 string into a list of code-point characters. Inverse of list->str.")

(doc (provide x/type/string list->str str->list)
  (note "DEPRECATED string library. list->str / str->list are the low-level code-point conversions; the str-* API now lives in x/type/str.")
  "Deprecated: use x/type/str for the string library.")

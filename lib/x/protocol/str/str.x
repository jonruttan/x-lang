; str/str.x -- Str: the byte view of an x-lang string
(import x/protocol/seq)

; Str treats a STRING as its raw UTF-8 bytes. start/done?/step are expressed in
; terms of the byte-level C primitives str-length and str-ref, so each element
; is the CHARACTER holding one byte (0-255). This is the literal storage view --
; the namespace where the byte primitives live. Utf8 (a subclass) reinterprets
; the same bytes as code points by overriding only `step`.
(def-class Str (extends Seq)
  (static
    (method start (self v)     0)
    (method done? (self v cur) (>= cur (str-length v)))
    (method step  (self v cur) (pair (str-ref v cur) (+ cur 1)))

    ; bytes are randomly indexable, so expose the O(1) fast paths Seq lacks
    (method length (self v)     (str-length v))   ; overrides Seq's cursor walk
    (method ref    (self v i)   (str-ref v i))))

(provide x/protocol/str/str Str)

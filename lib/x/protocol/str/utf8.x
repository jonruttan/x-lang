; str/utf8.x -- Utf8: the code-point view of a UTF-8 string
(import x/protocol/str/str)
(import x/codec/utf8)

; Utf8 reinterprets the SAME bytes Str walks, but one whole UTF-8 sequence per
; element, yielding the decoded code point as a CHARACTER. It reuses Str's byte
; cursor unchanged -- start (0) and done? (>= byte-length) are inherited -- and
; overrides only:
;   step    : consume a multi-byte sequence instead of a single byte
;   length  : fall back to Seq's cursor count (code points), because Str's O(1)
;             byte length is the wrong answer for a code-point view
;   ref     : decode to the i-th CODE POINT (O(n) walk), replacing Str's O(1)
;             byte ref, which is wrong for a variable-width view. O(n) is
;             inherent to random access in a variable-width encoding; prefer
;             ->list / cursor traversal when visiting every element.
;
; step decodes one UTF-8 sequence per element via the shared codec (x/codec/utf8),
; the single home for the byte<->code-point transform (str->list uses it too).

(def-class Utf8 (extends Str)
  (static
    (method length (self v) (self count v))   ; code points, via Seq's cursor walk
    (method step (self v cur)
      (let ((d (utf8-decode v cur)))
        (pair (integer->char (first d)) (rest d))))
    ; O(n) code-point index: walk i sequences from the start, decode the i-th.
    ; Overrides Str's O(1) byte ref, which is wrong for a variable-width view.
    (method ref (self v i)
      (let loop ((cur (self start v)) (n i))
        (let ((d (utf8-decode v cur)))
          (if (= n 0)
            (integer->char (first d))
            (loop (rest d) (- n 1))))))))

(provide x/protocol/str/utf8 Utf8)

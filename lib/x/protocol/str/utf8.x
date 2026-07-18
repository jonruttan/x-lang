; str/utf8.x -- StrUTF8: the UTF-8 code-point string class
(import x/protocol/str/str8)
; Fetch the string prims from the catalog (ns `str` is de-registered, R5).
(def %str-byte-sub (prim-ref (lit str) (lit byte-sub)))
(def %str-byte-len (prim-ref (lit str) (lit byte-len)))

(import x/codec/utf8)
; Fetch the char/int casts from the catalog (ns `char`/`int` utility members de-registered, R5).
(def %char->integer (prim-ref (lit char) (lit ->int)))
(def %integer->char (prim-ref (lit int) (lit ->char)))


; StrUTF8 reinterprets the SAME bytes as Str8, but one whole UTF-8 sequence per
; element, yielding the decoded code point as a CHARACTER. It inherits the full
; string suite from Str8 (append, join, contains?, split, trim, =?, <?, ...) --
; written once through self primitives -- and overrides ONLY the primitives that
; change with the encoding:
;   length      : code-point count (cursor walk), not Str8's O(1) byte length
;   ref         : decode to the i-th CODE POINT (O(n) walk)
;   sub         : substring of `len` CODE POINTS from code-point offset `start`
;   step        : consume one UTF-8 sequence per element
;   char->bytes : encode a code point to its 1-4 UTF-8 bytes (inverse of step)
; All byte access goes through the inherited Str8 byte primitives + the shared
; codec (x/codec/utf8); ref/sub are O(n) (inherent to variable-width random
; access -- prefer ->list / cursor traversal to visit every element).

; Byte offset of code-point index k: advance k whole sequences from byte `from`.
; Clamps at the byte length instead of decoding past the end (%utf8-decode is
; an unchecked read) -- callers detect out-of-range by landing at the length.
(def %u8-byte-offset
  (fn (self s k from)
    (if (= k 0) from
      (if (< from (%str-byte-len s))
        (self s (- k 1) (rest (%utf8-decode s from)))
        from))))

(def-class StrUTF8 (extends Str8)
  (static
    (method length (self (param v STRING "String to measure"))
      (doc "Number of UTF-8 CODE POINTS in v (not bytes), via a cursor walk."
        (returns INT "Code-point count of v")
        (example "(StrUTF8 length \"$¢€\")" "3"))
      (self count v))   ; code points, via Seq's cursor walk

    (method ref (self (param i INT "Code-point position (0-based; negative counts from the end)") (param v STRING "String to index"))
      (doc "The i-th CODE POINT of v as a CHARACTER, found by an O(n) UTF-8 walk; negative i counts from the end. Errors when i is nil or out of range."
        (returns CHAR "Code point at position i")
        (example "(StrUTF8 ref 1 \"$¢€\")" "#\\¢"))
      ; The walker clamps at the byte length, so landing there means i is past
      ; the last code point -- error instead of decoding past the end. The nil
      ; guard makes a piped index-search miss fail loudly; only the negative
      ; case pays the code-point count walk.
      (def j (%str8->int i "Str ref: index not convertible to INT"))
      (if (< j 0)
        (let ((k (+ j (self count v))))
          (if (< k 0) (error "Str ref: index out of range") (self ref k v)))
        (let ((b (%u8-byte-offset v j 0)))
          (if (< b (%str-byte-len v))
            (%integer->char (first (%utf8-decode v b)))
            (error "Str ref: index out of range")))))

    (method sub (self (param start INT "Start code-point offset (0-based)") (param len INT "Number of code points") (param v STRING "Source string"))
      (doc "Substring of len CODE POINTS starting at code-point offset start (O(n) walk)."
        (returns STRING "The len-code-point slice of v from start")
        (example "(StrUTF8 sub 1 1 \"$¢€\")" "\"¢\""))
      (def st2 (%str8->int start "Str sub: start not convertible to INT"))
      (def len2 (%str8->int len "Str sub: length not convertible to INT"))
      (def b0 (%u8-byte-offset v st2 0))
      (def b1 (%u8-byte-offset v len2 b0))
      (%str-byte-sub v b0 (- b1 b0)))

    (method step (self (param cur INT "Current byte offset of the cursor") (param v STRING "String being traversed"))
      (doc "Cursor step: decode one UTF-8 sequence at byte offset cur, yielding (CODE-POINT . next-byte-offset)."
        (returns PAIR "Pair of the decoded code point (CHARACTER) and the next byte offset")
        (example "(StrUTF8 step 1 \"$¢\")" "(#\\¢ . 3)"))
      (let ((d (%utf8-decode v cur)))
        (pair (%integer->char (first d)) (rest d))))

    ; encode: a code point -> its UTF-8 bytes (inverse of step)
    (method char->bytes (self (param el CHAR "Code point to encode"))
      (doc "Encode one CODE POINT to its 1-4 UTF-8 bytes (inverse of step)."
        (returns LIST "List of the UTF-8 byte values (integers) for el")
        (example "(StrUTF8 char->bytes (integer->char 162))" "(194 162)"))
      (%utf8-encode (%char->integer el)))

    ; --- The byte <-> code-point codec (x/codec/utf8 surfaces here) ---
    (method seq-len (self (param b INT "Lead byte value (0-255)"))
      (doc "Number of bytes in the UTF-8 sequence introduced by lead byte b."
        (returns INT "Sequence length 1-4"))
      (%utf8-seq-len b))
    (method decode (self (param s STRING "Byte string") (param i INT "Byte index of a sequence start"))
      (doc "Decode the UTF-8 sequence at byte index i."
        (returns PAIR "(code-point . next-byte-index)"))
      (%utf8-decode s i))
    (method encode (self (param cp INT "Code point to encode"))
      (doc "Encode a code point as a list of its 1-4 UTF-8 byte values. Out-of-range emits U+FFFD."
        (returns LIST "UTF-8 byte values (integers)")
        (example "(Utf8 encode 162)" "(194 162)"))
      (%utf8-encode cp))
    (method width (self (param s STRING "Byte string") (param i INT "Byte index of a sequence start"))
      (doc "Byte width of the UTF-8 sequence at byte index i. Allocation-free."
        (returns INT "Sequence length 1-4"))
      (%utf8-width s i))
    (method cp-at (self (param s STRING "Byte string") (param i INT "Byte index of a sequence start"))
      (doc "Code point at byte index i. Allocation-free (no pair, no closure)."
        (returns INT "Decoded code point"))
      (%utf8-cp-at s i))))

; Utf8 = alias for the UTF-8 protocol class.
(def Utf8 StrUTF8)

; Str = the AMBIENT string protocol. The default is UTF-8 (code points): the
; bare string call (s i), the str-* API, and str->list all work in code points
; out of the box. Str8 and StrUTF8 always name their fixed protocols; rebind
; Str (e.g. (def Str Str8)) to change the active protocol for the whole str-*
; library at once.
(def Str StrUTF8)

; Value dispatch over the existing code-point call handler: ("hi" index 0) and
; ("hi" upcase) dispatch to Str methods; ("hi" 0) still does code-point access.
(%bind-call-over! (Type of "x") Str)

(doc (provide x/protocol/str/utf8 StrUTF8 Utf8 Str)
  (note "The UTF-8 code-point view (a Str8 subclass). Utf8 and Str are aliases for StrUTF8; Str names the active protocol. (help StrUTF8) lists every method.")
  "StrUTF8: the UTF-8 code-point string protocol, overriding Str8's element access for code points.")

; str-index.x -- UTF-8-aware string indexing (language integration)
;
; Wires UTF-8 into the bare string call so ("$¢€" i) indexes by CODE POINT,
; while the named byte API (str-ref / str-length / substring) stays byte-level.
; This is language integration -- it commits the language to UTF-8 -- distinct
; from the encoding-agnostic protocol library. It sits on the shared codec
; (x/codec/utf8), not the protocol classes, because indexing is low-level and
; must not depend on the object system.
;
; Mechanism: the string type's call is a pushable stack (like write/display).
; We capture the C byte handler, repoint the named byte API straight at it, then
; push a code-point handler so the bare call dispatches by arity to the codec.
;
; Bare call (code-point view)        Named API (byte view, unchanged)
;   (s)      -> code-point count       (str-length s)        -> byte count
;   (s i)    -> i-th code point        (str-ref s i)         -> i-th byte
;   (s a n)  -> code-point substring   (substring s a b)     -> byte substring
;
; All arities of the bare call are code-point so they stay mutually consistent:
; str=? compares (a) length against (a i) elements, so mixing byte length with
; code-point indexing would read past the end of a multi-byte string. (The hot
; loops that still use the bare call, e.g. str=?, are correct but now O(n) per
; index -- optimizing them to the byte API is a deferred follow-up.)

(import x/codec/utf8)

(def %str-type (type-by-atom (type-of "x")))

; Capture the C byte handler BEFORE pushing, so the byte API and the code-point
; walks can use it without re-entering the pushed handler (no recursion).
(def %byte-handler (type-call-top %str-type))
(def %byte-call (fn (_ s . args) (apply %byte-handler (pair s args))))

; --- named byte API: route straight to the captured byte handler ---
(def str-length (fn (_ s)         (%byte-call s)))
(def str-ref    (fn (_ s i)       (%byte-call s i)))
(def substring  (fn (_ s start end) (%byte-call s start (- end start))))

; --- code-point operations (walk via the shared codec; byte access throughout) ---

; Byte offset of code-point index k (walk k sequences from byte offset `from`).
(def %cp-byte-offset
  (fn (self s k from)
    (if (= k 0) from
      (self s (- k 1) (rest (utf8-decode s from))))))

(def %cp-count
  (fn (_ s)
    (def len (%byte-call s))
    (let loop ((i 0) (n 0))
      (if (>= i len) n
        (loop (rest (utf8-decode s i)) (+ n 1))))))

(def %cp-ref
  (fn (_ s i)
    (integer->char (first (utf8-decode s (%cp-byte-offset s i 0))))))

(def %cp-substring
  (fn (_ s start len)
    (def b0 (%cp-byte-offset s start 0))
    (def b1 (%cp-byte-offset s len b0))
    (%byte-call s b0 (- b1 b0))))

; --- push the code-point call handler over the byte default ---
; (fn (_ s . vals)): s is the string, vals the (already-evaluated) index args.
(type-push-call %str-type
  (fn (_ s . vals)
    (if (null? vals)
      (%cp-count s)
      (if (null? (rest vals))
        (%cp-ref s (first vals))
        (%cp-substring s (first vals) (first (rest vals)))))))

(provide x/type/str-index str-length str-ref substring)

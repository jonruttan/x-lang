; str-index.x -- UTF-8-aware string indexing (language integration)
;
; Wires UTF-8 into the bare string call so ("$¢€" i) indexes by CODE POINT,
; while the named byte API (str-ref / str-length / substring) stays byte-level.
; This is language integration -- it commits the language to UTF-8 -- distinct
; from the encoding-agnostic protocol library. It sits on the shared codec
; (x/codec/utf8), not the protocol classes, because indexing is low-level and
; must not depend on the object system.
;
; ALLOCATION DISCIPLINE: bare (s i) is used inside tokenizer reader/analyse
; callbacks (e.g. make-str-state in x/sys/token.x, the logo readers). Heap
; allocation there can trigger GC mid-parse and corrupt the C stack. So the
; code-point walk below uses ONLY the no-alloc codec accessors (utf8-cp-at,
; utf8-width) -- never utf8-decode, which conses a (cp . next) pair. The walk
; itself is plain integer recursion (no pair/closure built per step), so a
; code-point (s i) allocates no more than the byte path it replaces (one
; result object), keeping reader callbacks GC-safe.
;
; Bare call (code-point view)        Named API (byte view, unchanged)
;   (s)      -> code-point count       (str-length s)        -> byte count
;   (s i)    -> i-th code point        (str-ref s i)         -> i-th byte
;   (s a n)  -> code-point substring   (substring s a b)     -> byte substring

(import x/codec/utf8)

(def %str-type (type-by-atom (type-of "x")))

; Capture the C byte handler BEFORE pushing, so the byte API and the code-point
; walks can use it without re-entering the pushed handler (no recursion).
(def %byte-handler (type-call-top %str-type))
(def %byte-call (fn (_ s . args) (apply %byte-handler (pair s args))))

; --- named byte API: route straight to the captured byte handler ---
(def str-length (fn (_ s)           (%byte-call s)))
(def str-ref    (fn (_ s i)         (%byte-call s i)))
(def substring  (fn (_ s start end) (%byte-call s start (- end start))))

; --- code-point operations (walk via no-alloc codec accessors) ---

; Byte offset of code-point index k: advance k whole sequences from byte `from`.
; Plain integer recursion -- nothing heap-allocated per step.
(def %cp-byte-offset
  (fn (self s k from)
    (if (= k 0) from
      (self s (- k 1) (+ from (utf8-width s from))))))

(def %cp-count
  (fn (self s len i n)
    (if (>= i len) n
      (self s len (+ i (utf8-width s i)) (+ n 1)))))

; i-th code point. Negative i counts from the end (matches the old byte path:
; the C call added the length to a negative index). Normalizing requires the
; code-point count, so only the negative case pays for the extra walk.
(def %cp-ref
  (fn (_ s i)
    (def k (if (< i 0) (+ i (%cp-count s (%byte-call s) 0 0)) i))
    (integer->char (utf8-cp-at s (%cp-byte-offset s k 0)))))

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
      (%cp-count s (%byte-call s) 0 0)
      (if (null? (rest vals))
        (%cp-ref s (first vals))
        (%cp-substring s (first vals) (first (rest vals)))))))

(provide x/type/str-index str-length str-ref substring)

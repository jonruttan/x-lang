; str-index.x -- UTF-8-aware bare string indexing (language integration)
;
; Makes the bare string call follow the UTF-8 protocol:
;   (s)     -> code-point count
;   (s i)   -> i-th code point
;   (s a n) -> code-point substring (n code points from code-point offset a)
; by pushing a handler onto the STRING type's call slot.
;
; The named byte API is SEPARATE and stays byte-level: str-ref / str-length /
; substring are bound (in boot) to the str-byte-* C primitives, which read raw
; bytes directly and ignore this handler. So readers/tokenizers/loaders that
; need bytes use those (or the Str8 class) and never touch the ambient (s i).
;
; ALLOCATION DISCIPLINE: the bare call may run inside tokenizer callbacks, where
; heap allocation can trip GC mid-parse. The code-point walk uses ONLY the
; no-alloc codec accessors (utf8-width / utf8-cp-at) -- never utf8-decode (which
; conses a pair) -- and plain integer recursion, so it allocates no more than
; the one result object the byte path already made.

(import x/codec/utf8)

(def %str-type (type-by-atom (type-of "x")))

; Byte offset of code-point index k: advance k whole sequences from byte `from`.
(def %cp-byte-offset
  (fn (self s k from)
    (if (= k 0) from
      (self s (- k 1) (+ from (utf8-width s from))))))

(def %cp-count
  (fn (self s len i n)
    (if (>= i len) n
      (self s len (+ i (utf8-width s i)) (+ n 1)))))

; i-th code point. Negative i counts from the end (matches the old byte path:
; the C call added the length to a negative index). Only the negative case pays
; for the extra code-point count walk.
(def %cp-ref
  (fn (_ s i)
    (def k (if (< i 0) (+ i (%cp-count s (str-byte-len s) 0 0)) i))
    (integer->char (utf8-cp-at s (%cp-byte-offset s k 0)))))

(def %cp-substring
  (fn (_ s start len)
    (def b0 (%cp-byte-offset s start 0))
    (def b1 (%cp-byte-offset s len b0))
    (str-byte-sub s b0 (- b1 b0))))

; --- push the code-point call handler over the byte default ---
; (fn (_ s . vals)): s is the string, vals the (already-evaluated) index args.
(type-push-call %str-type
  (fn (_ s . vals)
    (if (null? vals)
      (%cp-count s (str-byte-len s) 0 0)
      (if (null? (rest vals))
        (%cp-ref s (first vals))
        (%cp-substring s (first vals) (first (rest vals)))))))

(provide x/type/str-index)

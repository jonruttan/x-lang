; str-utf8.x -- The low-level UTF-8 code-point layer for the STRING type.
;
; Loaded early in boot (right after the UTF-8 codec, before the object system),
; this owns the two pieces of code-point string handling that need only the
; codec -- not the protocol classes -- and that boot code depends on:
;
;   1. list->str / str->list : the code-point list <-> UTF-8 string transforms.
;      Used by char-io, number->str and sys/convert before any class exists.
;   2. The bare (s i) call handler: makes (s), (s i) and (s a n) index the
;      STRING in CODE POINTS, by pushing a handler onto the STRING call slot.
;
; The NAMED byte API stays SEPARATE and byte-level: str-ref / str-length /
; substring are bound (in boot) to the str-byte-* C primitives, which read raw
; bytes directly and ignore this handler. So readers/tokenizers/loaders that
; need bytes use those (or the Str8 class) and never touch the ambient (s i).
;
; The high-level string library -- the Str8 / StrUTF8 protocol classes and the
; Str entry point -- lives in x/type/str, loaded later once objects exist.
;
; No UTF-8 in C: C packs/loads bytes; this x-lang layer owns the byte<->code-
; point transform, via the shared codec (x/codec/utf8).

(import x/type/char)
; Fetch the string prims from the catalog (ns `str` is de-registered, R5).
(def %str-byte-len (prim-ref (lit str) (lit byte-len)))
; Fetch the type prims from the catalog (ns `type` is de-registered, R5).
(def %type-of (prim-ref (lit type) (lit of)))

(def %str-byte-sub (prim-ref (lit str) (lit byte-sub)))
; Fetch the char/int casts from the catalog (ns `char`/`int` utility members de-registered, R5).
(def %char->integer (prim-ref (lit char) (lit ->int)))
(def %integer->char (prim-ref (lit int) (lit ->char)))


; Fetch the type-system helpers from the catalog (registered by sys/type.x).
(def %type-by-atom (prim-ref (lit type) (lit by-atom)))
(def %type-push-call (prim-ref (lit type) (lit push-call)))

(import x/core/list)
(import x/codec/utf8)

; --- list <-> string (code-point) transforms -------------------------------

; list->str: list of code-point CHARACTERs -> UTF-8 string. The C primitive of
; this name is the dumb byte-packer (bytes->str, one low byte per char); this
; redefines it to be code-point aware -- each char is UTF-8 encoded via the
; shared codec, then byte-packed. Exact inverse of str->list, so
; (list->str (str->list s)) round-trips any UTF-8 string.
(doc (def list->str
  (fn (_ chars)
    (bytes->str
      (map %integer->char
        (fold (fn (_ acc ch) (append acc (%utf8-encode (%char->integer ch))))
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
        (let ((d (%utf8-decode s i)))
          (go (rest d) (pair (%integer->char (first d)) acc)))))))
  (param s STRING "String to decode")
  (returns LIST "List of CHARACTERs, one per Unicode code point")
  (example "(str->list \"$¢€\")" "(#\\$ #\\¢ #\\€)")
  "Decode a UTF-8 string into a list of code-point characters. Inverse of list->str.")

; --- bare (s i) -> code-point call handler ---------------------------------
;
; ALLOCATION DISCIPLINE: the bare call may run inside tokenizer callbacks, where
; heap allocation can trip GC mid-parse. The code-point walk uses ONLY the
; no-alloc codec accessors (%utf8-width / utf8-cp-at) -- never %utf8-decode (which
; conses a pair) -- and plain integer recursion, so it allocates no more than
; the one result object the byte path already made.

(def %str-type (%type-by-atom (%type-of "x")))

; Byte offset of code-point index k: advance k whole sequences from byte `from`.
; Clamps at byte length `len` instead of walking past the end (%utf8-width is
; an unchecked read) -- callers detect out-of-range by landing at `len`. The
; length rides as a param so the walk stays alloc-free (str-byte-len is a prim
; call that makes an int per call).
(def %cp-byte-offset
  (fn (self s len k from)
    (if (= k 0) from
      (if (< from len)
        (self s len (- k 1) (+ from (%utf8-width s from)))
        from))))

(def %cp-count
  (fn (self s len i n)
    (if (>= i len) n
      (self s len (+ i (%utf8-width s i)) (+ n 1)))))

; i-th code point. Negative i counts from the end (matches the old byte path:
; the C call added the length to a negative index). Only the negative case pays
; for the extra code-point count walk. Out of range (either side) errors --
; %utf8-cp-at is an unchecked read, so this is the x-lang guard. INT-ONLY by
; design (the N5 coercion exception): this handler can run under reader
; constraints, where conversion dispatch is illegal -- the protocol classes
; (Str8/StrUTF8 ref) are the coercing doors.
(def %cp-ref
  (fn (_ s i)
    (def len (%str-byte-len s))
    (def k (if (null? i) (- 0 1) (if (< i 0) (+ i (%cp-count s len 0 0)) i)))
    (def b (if (< k 0) len (%cp-byte-offset s len k 0)))
    (if (< b len)
      (%integer->char (%utf8-cp-at s b))
      (error "str: index out of range"))))

; Clamped like StrUTF8 sub: offsets past the end yield the empty/short slice.
; A negative count must short-circuit -- the offset walk only stops on k = 0,
; so a negative k would otherwise clamp at the end and take the whole tail.
(def %cp-substring
  (fn (_ s start len)
    (def blen (%str-byte-len s))
    (def b0 (%cp-byte-offset s blen start 0))
    (def b1 (if (< len 0) b0 (%cp-byte-offset s blen len b0)))
    (%str-byte-sub s b0 (- b1 b0))))

; --- push the code-point call handler over the byte default ---
; (fn (_ s . vals)): s is the string, vals the (already-evaluated) index args.
(%type-push-call %str-type
  (fn (_ s . vals)
    (if (null? vals)
      (%cp-count s (%str-byte-len s) 0 0)
      (if (null? (rest vals))
        (%cp-ref s (first vals))
        (%cp-substring s (first vals) (first (rest vals)))))))

(doc (provide x/type/str-utf8 list->str str->list)
  (note "Low-level layer, loaded before the object system. The high-level string API is the Str8 / StrUTF8 classes and the Str entry point in x/type/str.")
  (note "The named byte API (str-length, str-ref, substring) stays byte-level; only the bare (s i) call is code-point aware.")
  "The low-level UTF-8 code-point layer for the STRING type: the list<->str transforms and the bare (s i) code-point indexing handler.")

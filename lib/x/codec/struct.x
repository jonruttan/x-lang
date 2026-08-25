; codec/struct.x -- Struct: binary record pack/unpack against a field spec.
;
; The shape every hand-rolled binary decode in the tree wanted (#371):
; platform/dirent.x grew %u8/%u16 peeks, sys/file.x grew %peek-u16/u32/i64,
; sockets hand-packed big-endian ports. This codec names the pattern once:
;
;   spec  = ((name type) ...) fields, in record order:
;             (name u8|i8|u16|i16|u32|i32|u64|i64)   little-endian; u64 >= 2^63
;                                                    reads back machine-negative
;             (name u16be|u32be)                     big-endian (ports, lengths)
;             (name str N)                           N raw bytes as a string
;             (name cstr N)                          NUL-terminated within N bytes
;             (pad N)                                N bytes skipped / zero-filled
;   (Struct length spec)            -> total byte width
;   (Struct unpack spec buf [off])  -> ((name . value) ...) alist, spec order
;   (Struct pack spec values)       -> byte LIST (values = alist by name)
;   (Struct reader spec)            -> (fn (buf off) -> alist), the HOT door:
;                                      the spec compiles ONCE into a closure
;                                      plan (the analyser pattern) -- zero
;                                      class dispatch per record.
;
; Buffers are strings ((str make N) regions syscalls filled). Reads ride
; str byte-ref, which is NUL-blind -- interior NULs decode fine -- but there
; is NO bounds check: a buffer's observable strlen lies past a NUL (the
; x-lib ruling), so the CALLER owns the bound, as with every raw peek this
; replaces. pack returns a byte LIST (the lossless carrier, #362); callers
; needing a buffer take bytes->str knowing the length from the list.
;
; NOT this class: x/type/struct is type-SYSTEM plumbing (the type's
; layout walkers), unrelated to binary records.
;
; Strict per #61: unknown type symbols, malformed fields, and pack values
; missing a name raise kind-'value.
;
; Zero top-level %-globals (new-file budget 0); the plan builder is a
; %-private method (cold, build-time), and per-field work inside a plan
; rides captured locals.

(import x/type/class)
(import x/core/list)
(import x/core/alist)

(def-class Struct ()
  (doc "Binary records against a field spec: (Struct unpack spec buf) decodes a syscall-filled string buffer to an alist; (Struct pack spec values) builds the byte list back; (Struct reader spec) compiles the spec once into a zero-dispatch decode closure for hot paths."
    (example "(Struct unpack (list (list 'a 'u8) (list 'b 'u16)) (bytes->str (list 7 1 2)))" "(('a . 7) ('b . 513))")
    (see unpack) (see pack) (see reader))
  (static
    ; The compiled plan: ((name width rdr) ...) with rdr = (fn (buf off) -> value)
    ; capturing the byte prims; pads carry a nil rdr. Cold, build-time only.
    (method %plan (self (param spec LIST "Field spec"))
      (doc "Compile a field spec into ((name width reader-closure) ...) -- pads carry a nil reader. Raises kind-'value on malformed fields or unknown types."
        (returns LIST "The plan, in spec order"))
      (def %bref (prim-ref (lit str) (lit byte-ref)))
      (def %c->i (prim-ref (lit char) (lit ->int)))
      (def %bsub (prim-ref (lit str) (lit byte-sub)))
      (def %b (fn (_ buf i) (%c->i (%bref buf i))))
      (def %bad (fn (_ what f)
        (Err raise (lit value) (Str8 append "Struct: " what) f)))
      ; little-endian unsigned reader over w bytes
      (def %le (fn (_ w)
        (fn (_ buf off)
          (let go ((i (- w 1)) (acc 0))
            (if (< i 0) acc
              (go (- i 1) (+ (* acc 256) (%b buf (+ off i)))))))))
      ; sign-fold a w-byte unsigned value.  The half/span constants are
      ; (<< 1 (- (* 8 w) 1)) -- (<< 1 31) for a 4-byte field, which overflows
      ; a 32-bit fixnum, and the 8-byte case below relies on a 64-bit machine
      ; int wrapping.  Byte assembly itself is endian-NEUTRAL (%le and %be
      ; both build the value arithmetically), so only the width binds.
      ; constraint: word-size = 8 -- sign-fold constants exceed a 32-bit fixnum
      ; w < 8 ONLY: an 8-byte
      ; accumulation already wraps to the two's-complement signed value
      ; (and (<< 1 64) is 1 under hardware shift-count masking -- the
      ; fold there subtracted one, caught by the i64 round-trip smoke).
      (def %signed (fn (_ w rdr)
        (let ((half (<< 1 (- (* 8 w) 1))) (span (<< 1 (* 8 w))))
          (fn (_ buf off)
            (let ((v (rdr buf off)))
              (if (< v half) v (- v span)))))))
      ; big-endian unsigned reader over w bytes
      (def %be (fn (_ w)
        (fn (_ buf off)
          (let go ((i 0) (acc 0))
            (if (= i w) acc
              (go (+ i 1) (+ (* acc 256) (%b buf (+ off i)))))))))
      (List map
        (fn (_ f)
          (match
            ((not (pair? f)) (%bad "field is not a list" f))
            ((eq? (first f) (lit pad))
              (list (lit pad) (first (rest f)) ()))
            (#t
              (let ((name (first f)) (ty (first (rest f))))
                (match
                  ((eq? ty (lit u8))  (list name 1 (%le 1)))
                  ((eq? ty (lit i8))  (list name 1 (%signed 1 (%le 1))))
                  ((eq? ty (lit u16)) (list name 2 (%le 2)))
                  ((eq? ty (lit i16)) (list name 2 (%signed 2 (%le 2))))
                  ((eq? ty (lit u32)) (list name 4 (%le 4)))
                  ((eq? ty (lit i32)) (list name 4 (%signed 4 (%le 4))))
                  ((eq? ty (lit u64)) (list name 8 (%le 8)))
                  ((eq? ty (lit i64)) (list name 8 (%le 8)))     ; 8-byte wrap IS the signed value
                  ((eq? ty (lit u16be)) (list name 2 (%be 2)))
                  ((eq? ty (lit u32be)) (list name 4 (%be 4)))
                  ; (str byte-sub s START LEN) takes a LENGTH, not an end index --
                  ; the C signature is (str-byte-sub s start len).  Passing
                  ; (+ off n) read off EXTRA bytes for any field at a non-zero
                  ; offset: a 3-byte str field at offset 1 came back 4 bytes long.
                  ; Correct at offset 0, which is why every existing spec passed.
                  ((eq? ty (lit str))
                    (let ((n (first (rest (rest f)))))
                      (list name n (fn (_ buf off) (%bsub buf off n)))))
                  ((eq? ty (lit cstr))
                    (let ((n (first (rest (rest f)))))
                      (list name n
                        (fn (_ buf off)
                          (let scan ((i 0))
                            (match
                              ((= i n) (%bsub buf off n))
                              ((= (%b buf (+ off i)) 0) (%bsub buf off i))
                              (#t (scan (+ i 1)))))))))
                  (#t (%bad "unknown field type" f)))))))
        spec))

    (method length (self (param spec LIST "Field spec"))
      (doc "The record's total byte width -- the sum of every field and pad."
        (returns INT "Byte count")
        (example "(Struct length (list (list 'a 'u16) (list 'pad 5) (list 'b 'i64)))" "15"))
      (List fold (fn (_ acc entry) (+ acc (first (rest entry))))
        0 (Struct %plan spec)))

    (method unpack (self (param spec LIST "Field spec")
                         (param buf STRING "Record buffer (a (str make N) region a syscall filled; reads are NUL-blind)")
                         . (param offset INT "Byte offset of the record; default 0"))
      (doc "Decode one record at offset into an alist, fields in spec order, pads skipped. No bounds check is possible (a buffer's observable strlen lies past a NUL) -- the caller owns the bound, as with the raw peeks this replaces."
        (returns ALIST "((name . value) ...)")
        (example "(Struct unpack (list (list 'pad 1) (list 'p 'u16be)) (bytes->str (list 9 1 187)))" "(('p . 443))"))
      (let go ((plan (Struct %plan spec))
               (off (if (null? offset) 0 (first offset)))
               (acc ()))
        (match
          ((null? plan) (%reverse acc))
          (#t
            (let ((entry (first plan)))
              (go (rest plan)
                  (+ off (first (rest entry)))
                  (if (null? (first (rest (rest entry)))) acc
                    (pair (pair (first entry)
                                ((first (rest (rest entry))) buf off))
                          acc))))))))

    (method reader (self (param spec LIST "Field spec"))
      (doc "Compile the spec ONCE into a decode closure (fn (buf off) -> alist) -- the hot-path door: build it at load, call it per record, zero class dispatch inside (the analyser pattern)."
        (returns CALLABLE "(fn (buf off) -> ((name . value) ...))")
        (sample "(def %rec (Struct reader SPEC)) ... (%rec buf off)" "one alist per call, no dispatch"))
      (def plan (Struct %plan spec))
      (fn (_ buf off0)
        (let go ((p plan) (off off0) (acc ()))
          (match
            ((null? p) (%reverse acc))
            (#t
              (let ((entry (first p)))
                (go (rest p)
                    (+ off (first (rest entry)))
                    (if (null? (first (rest (rest entry)))) acc
                      (pair (pair (first entry)
                                  ((first (rest (rest entry))) buf off))
                            acc)))))))))

    (method pack (self (param spec LIST "Field spec")
                       (param values ALIST "((name . value) ...); every non-pad field must be present"))
      (doc "Encode values into a byte LIST (the lossless carrier, #362), fields in spec order: pads emit zeros, str/cstr fields zero-pad to width (cstr reserves the last byte for NUL), and a missing name raises kind-'value."
        (returns LIST "Byte values (0-255)")
        (example "(Struct pack (list (list 'a 'u16) (list 'pad 1)) (list (pair 'a 513)))" "(1 2 0)"))
      (def %bref (prim-ref (lit str) (lit byte-ref)))
      (def %c->i (prim-ref (lit char) (lit ->int)))
      (def %blen (prim-ref (lit str) (lit byte-len)))
      (def %bad (fn (_ what f)
        (Err raise (lit value) (Str8 append "Struct pack: " what) f)))
      ; value for name, presence-checked (a stored nil is not a miss)
      (def %val (fn (_ name)
        (let ((e (Assoc entry name values)))
          (if (null? e) (%bad "no value for field" name) (rest e)))))
      (def %le-bytes (fn (_ v w)
        (let go ((i 0) (v v) (acc ()))
          (if (= i w) (%reverse acc)
            (go (+ i 1) (>> v 8) (pair (& v 255) acc))))))
      (def %be-bytes (fn (_ v w)
        (let go ((i 0) (v v) (acc ()))
          (if (= i w) acc
            (go (+ i 1) (>> v 8) (pair (& v 255) acc))))))
      (def %zeros (fn (_ n) (List repeat n 0)))
      (def %str-bytes (fn (_ s cap)
        (let ((n (%blen s)))
          (let ((take (if (< n cap) n cap)))
            (let go ((i (- take 1)) (acc (%zeros (- cap take))))
              (if (< i 0) acc
                (go (- i 1) (pair (%c->i (%bref s i)) acc))))))))
      (List flat-map
        (fn (_ f)
          (match
            ((eq? (first f) (lit pad)) (%zeros (first (rest f))))
            (#t
              (let ((name (first f)) (ty (first (rest f))))
                (match
                  ((eq? ty (lit u8))  (%le-bytes (%val name) 1))
                  ((eq? ty (lit i8))  (%le-bytes (& (%val name) 255) 1))
                  ((eq? ty (lit u16)) (%le-bytes (%val name) 2))
                  ((eq? ty (lit i16)) (%le-bytes (& (%val name) 65535) 2))
                  ((eq? ty (lit u32)) (%le-bytes (%val name) 4))
                  ((eq? ty (lit i32)) (%le-bytes (& (%val name) 4294967295) 4))
                  ((eq? ty (lit u64)) (%le-bytes (%val name) 8))
                  ((eq? ty (lit i64)) (%le-bytes (%val name) 8))
                  ((eq? ty (lit u16be)) (%be-bytes (%val name) 2))
                  ((eq? ty (lit u32be)) (%be-bytes (%val name) 4))
                  ((eq? ty (lit str))
                    (%str-bytes (%val name) (first (rest (rest f)))))
                  ((eq? ty (lit cstr))
                    (let ((cap (first (rest (rest f)))))
                      (let ((body (%str-bytes (%val name) (- cap 1))))
                        (List append body (list 0)))))
                  (#t (%bad "unknown field type" f)))))))
        spec))))

(doc (provide x/codec/struct Struct)
  (note "Buffers are strings, reads NUL-blind, bounds the caller's (the x-lib C-string ruling); pack emits byte lists. First adopter: sys/file.x's stat/lstat decode. x/type/struct is unrelated type-system plumbing.")
  "Binary record pack/unpack against a field spec, homed on the Struct class.")

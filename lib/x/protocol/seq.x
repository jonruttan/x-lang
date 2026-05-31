; seq.x -- Seq: the base sequence protocol (cursor-based traversal)
(import x/type/object)

; A Seq subclass describes how to walk some in-memory value V as a sequence of
; elements. A subclass supplies just three cursor primitives:
;
;   (self start v)       -> opaque cursor positioned at the first element
;   (self done? v cur)   -> #t once the cursor is past the last element
;   (self step  v cur)   -> (element . next-cursor)
;
; Everything else (count, length, ->list, each, fold) is derived ONCE here.
; The derived methods call (self start/done?/step ...), which re-dispatch to the
; concrete subclass the call was made on -- so a new encoding gets the whole API
; for free by supplying only its three primitives. A cursor is deliberately
; opaque: a byte offset for strings, but it could be a (chunk . pos) for PNG or
; a frame index for WAV. Indexed O(1) ref is intentionally NOT in the contract,
; because it doesn't exist for variable-width or streamed formats.
;
; ENCODE (the inverse direction) is one more primitive + one derived method:
;   (self char->bytes el)  -> list of byte values (0-255) for one element
;   (self ->str elements)  -> string, derived from char->bytes (built here)
; So ->str is the dual of ->list, and a subclass is fully bidirectional once it
; supplies char->bytes. Encoding stays in the codec layer the subclass calls.

(def-class Seq ()
  (static
    ; --- contract: every subclass overrides these three ---
    (method start (self v)     (error "Seq: start is abstract"))
    (method done? (self v cur) (error "Seq: done? is abstract"))
    (method step  (self v cur) (error "Seq: step is abstract"))

    ; --- derived once, polymorphic through (self ...) ---
    (method count (self v)
      (let loop ((cur (self start v)) (n 0))
        (if (self done? v cur) n
          (loop (rest (self step v cur)) (+ n 1)))))

    ; default length walks the cursor; O(1) encodings override this
    (method length (self v) (self count v))

    (method ->list (self v)
      (let loop ((cur (self start v)) (acc ()))
        (if (self done? v cur)
          (reverse acc)
          (let ((s (self step v cur)))
            (loop (rest s) (pair (first s) acc))))))

    (method each (self v f)
      (let loop ((cur (self start v)))
        (if (self done? v cur) ()
          (let ((s (self step v cur)))
            (f (first s))
            (loop (rest s))))))

    (method fold (self v f acc)
      (let loop ((cur (self start v)) (a acc))
        (if (self done? v cur) a
          (let ((s (self step v cur)))
            (loop (rest s) (f a (first s)))))))

    ; --- encode direction (inverse of ->list) ---
    ; Contract: a subclass that can serialize supplies char->bytes.
    (method char->bytes (self el) (error "Seq: char->bytes is abstract"))

    ; Derived: encode a list of elements to a string, via char->bytes +
    ; the byte-packer. Dual of ->list, so (->str (->list v)) round-trips.
    ; fold here is fold-left: (fold f acc lst), callback (f acc element).
    (method ->str (self elements)
      (bytes->str
        (map integer->char
          (fold (fn (_ acc el) (append acc (self char->bytes el)))
                () elements))))))

(provide x/protocol/seq Seq)

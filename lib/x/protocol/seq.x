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
            (loop (rest s) (f a (first s)))))))))

(provide x/protocol/seq Seq)

; seq.x -- Seq: the base sequence protocol (cursor-based traversal)
(import x/type/object)
; Fetch the int->char cast from the catalog (ns `int` utility member de-registered, R5).
(def %integer->char (prim-ref (lit int) (lit ->char)))

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
  ; The contract: a concrete subclass must implement these (checked at def-class).
  ; start/done?/step drive traversal; char->bytes is needed only to serialize.
  (interface start done? step char->bytes)
  (static
    ; --- contract: every subclass overrides these three ---
    (method start (self (param v ANY "Value being traversed as a sequence"))
      (doc "Contract method: return an opaque cursor positioned at the first element. A subclass must override it."
        (returns ANY "A cursor (opaque -- a byte offset for strings)"))
      (error "Seq: start is abstract"))
    (method done? (self (param v ANY "Value being traversed") (param cur ANY "Current cursor"))
      (doc "Contract method: #t once the cursor has advanced past the last element. A subclass must override it."
        (returns BOOL "#t when traversal is complete"))
      (error "Seq: done? is abstract"))
    (method step (self (param v ANY "Value being traversed") (param cur ANY "Current cursor"))
      (doc "Contract method: return (element . next-cursor) at the cursor. A subclass must override it."
        (returns PAIR "A (element . next-cursor) pair"))
      (error "Seq: step is abstract"))

    ; --- derived once, polymorphic through (self ...) ---
    (method count (self (param v ANY "Value to traverse"))
      (doc "Count the elements by walking the cursor from start to done."
        (returns INT "Number of elements in v")
        (example "(Str8 count \"abc\")" "3"))
      (let loop ((cur (self start v)) (n 0))
        (if (self done? v cur) n
          (loop (rest (self step v cur)) (+ n 1)))))

    ; default length walks the cursor; O(1) encodings override this
    (method length (self (param v ANY "Value to measure"))
      (doc "Number of elements. The default walks the cursor in O(n); fixed-width encodings (e.g. Str8) override it with an O(1) count."
        (returns INT "Element count of v"))
      (self count v))

    (method ->list (self (param v ANY "Value to traverse"))
      (doc "Collect every element, in order, into a list."
        (returns LIST "List of v's elements")
        (example "(Str8 ->list \"ab\")" "(#\\a #\\b)"))
      (let loop ((cur (self start v)) (acc ()))
        (if (self done? v cur)
          (reverse acc)
          (let ((s (self step v cur)))
            (loop (rest s) (pair (first s) acc))))))

    (method each (self (param v ANY "Value to traverse") (param f CALLABLE "Applied to each element"))
      (doc "Apply f to each element in order, for its side effects; returns nil."
        (returns ANY "nil"))
      (let loop ((cur (self start v)))
        (if (self done? v cur) ()
          (let ((s (self step v cur)))
            (f (first s))
            (loop (rest s))))))

    (method fold (self (param v ANY "Value to traverse") (param f CALLABLE "Combiner, called (f acc element)") (param acc ANY "Initial accumulator"))
      (doc "Left-fold: thread acc through the elements left to right, calling (f acc element) at each step."
        (returns ANY "The final accumulator")
        (example "(Str8 fold \"abc\" (fn (_ a c) (+ a 1)) 0)" "3"))
      (let loop ((cur (self start v)) (a acc))
        (if (self done? v cur) a
          (let ((s (self step v cur)))
            (loop (rest s) (f a (first s)))))))

    ; --- encode direction (inverse of ->list) ---
    ; Contract: a subclass that can serialize supplies char->bytes.
    (method char->bytes (self (param el ANY "One element to encode"))
      (doc "Contract method: return the list of byte values (0-255) for one element. A subclass that serializes must override it."
        (returns LIST "Byte values for el"))
      (error "Seq: char->bytes is abstract"))

    ; Derived: encode a list of elements to a string, via char->bytes +
    ; the byte-packer. Dual of ->list, so (->str (->list v)) round-trips.
    ; fold here is fold-left: (fold f acc lst), callback (f acc element).
    (method ->str (self (param elements LIST "Elements to encode"))
      (doc "Encode a list of elements back into a string via char->bytes -- the dual of ->list, so (->str (->list v)) round-trips."
        (returns STRING "The encoded string")
        (example "(Str8 ->str (list #\\h #\\i))" "\"hi\""))
      (bytes->str
        (map %integer->char
          (fold (fn (_ acc el) (append acc (self char->bytes el)))
                () elements))))))

(doc (provide x/protocol/seq Seq)
  (note "A subclass supplies start/done?/step (and char->bytes to encode); count, length, ->list, each, fold and ->str are derived. (help Seq) lists the methods.")
  "Seq: the base sequence protocol -- cursor-based traversal shared by every sequence type.")

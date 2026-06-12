; data.x -- Pair and data accessors (bootstrap)
;
; Derived pair operations and low-level integer slot access.

; Fetch the raw-object prims from the catalog (ns `obj` is de-registered, R5).
(def %obj-set! (prim-ref (lit obj) (lit set!)))
(def %obj->ptr (prim-ref (lit obj) (lit ->ptr)))

(def set-first! (fn (_ p v) (%obj-set! p 0 v) p))
(def set-rest! (fn (_ p v) (%obj-set! p 1 v) p))

; %word-size and %data-offset computed once at boot
(def %word-size
  (match
    ((< 0 (ptr->int (int->ptr 4294967296))) 8)
    (#t 4)))
(def %data-offset (* %word-size 3))

; Int variants: read/write raw integer from pair slots
(def first-int (fn (_ x) (ptr-ref-word (%obj->ptr x) %data-offset)))
(def rest-int (fn (_ x) (ptr-ref-word (%obj->ptr x) (+ %data-offset %word-size))))
(def set-first-int! (fn (_ p v) (ptr-set-word! (%obj->ptr p) %data-offset v) p))
(def set-rest-int! (fn (_ p v) (ptr-set-word! (%obj->ptr p) (+ %data-offset %word-size) v) p))

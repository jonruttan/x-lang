; data.x -- Pair and data accessors (bootstrap)
;
; Derived pair operations and low-level integer slot access.

; Fetch the raw-object prims from the catalog (ns `obj` is de-registered, R5).
(def %obj->ptr (prim-ref (lit obj) (lit ->ptr)))
; Fetch the ptr/ffi prims from the catalog (ns `ptr`/`ffi` are de-registered, R5).
(def %ptr->int (prim-ref (lit ptr) (lit ->int)))
(def %ptr-ref-word (prim-ref (lit ptr) (lit ref-word)))
(def %ptr-set-word! (prim-ref (lit ptr) (lit set-word!)))
; Fetch the char/int casts from the catalog (ns `char`/`int` utility members de-registered, R5).
(def %int->ptr (prim-ref (lit int) (lit ->ptr)))

; %word-size and %data-offset computed once at boot; the header length comes
; from the committed layout contract (tools/obj-layout.x, included by
; x-core.x just before this file).
(def %word-size
  (match
    ((< 0 (%ptr->int (%int->ptr 4294967296))) 8)
    (#t 4)))
(def %data-offset (* %word-size %obj-meta-len))

; Data-slot write, pure reflection: data word i of an object lives at
; %data-offset + i*%word-size; the stored word is the value's object
; pointer.  Formerly the C (obj set!) prim -- boot/reflect.x files this
; same fn back into the catalog under that name.  Returns v (C contract).
(def %obj-set!
  (fn (_ o i v)
    (%ptr-set-word! (%obj->ptr o) (+ %data-offset (* i %word-size))
      (%ptr->int (%obj->ptr v)))
    v))

(def set-first! (fn (_ p v) (%obj-set! p 0 v) p))
(def set-rest! (fn (_ p v) (%obj-set! p 1 v) p))

; Int variants: read/write raw integer from pair slots
(def first-int (fn (_ x) (%ptr-ref-word (%obj->ptr x) %data-offset)))
(def rest-int (fn (_ x) (%ptr-ref-word (%obj->ptr x) (+ %data-offset %word-size))))
(def set-first-int! (fn (_ p v) (%ptr-set-word! (%obj->ptr p) %data-offset v) p))
(def set-rest-int! (fn (_ p v) (%ptr-set-word! (%obj->ptr p) (+ %data-offset %word-size) v) p))

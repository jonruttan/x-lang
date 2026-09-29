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
; from the committed layout contract (engine/tools/contract/obj-layout.x, included by
; x-core.x just before this file).
(def %word-size
  (match
    ((< 0 (%ptr->int (%int->ptr 4294967296))) 8)
    (#t 4)))
(def %data-offset (* %word-size %obj-meta-len))

; The engine's integer + and *, fetched once.  The formula below runs on every
; data-slot access, and the names + and * are rebound after this file: to the
; variadic wrappers (core/arithmetic.x), then to the numeric tower's generic
; dispatch.  The doors raise on nil and check nothing else: the class layer
; above validates an index.
(def %data-int+ (prim-ref (lit int) (lit +)))
(def %data-int* (prim-ref (lit int) (lit *)))

; THE data-word addressing formula -- the byte offset of data word i.  One
; definition: reflect.x's read half (%reflect-obj-ref) and the write half
; below must always address the same word, or set!/ref silently diverge.
(def %data-word-off
  (fn (_ i) (%data-int+ %data-offset (%data-int* i %word-size))))

; The two pair-slot offsets, hoisted through THE formula at load time --
; coherence (one addressing definition) AND no arithmetic at all on a
; first/rest write.
(def %data-off-0 (%data-word-off 0))
(def %data-off-1 (%data-word-off 1))

; Data-slot write, pure reflection: the stored word is the value's object
; pointer.  Formerly the C (obj set!) prim -- boot/reflect.x files this
; same fn back into the catalog under that name.  Returns v (C contract).
(def %obj-set!
  (fn (_ o i v)
    (%ptr-set-word! (%obj->ptr o) (%data-word-off i)
      (%ptr->int (%obj->ptr v)))
    v))

(def %set-first!
  (fn (_ p v) (%ptr-set-word! (%obj->ptr p) %data-off-0 (%ptr->int (%obj->ptr v))) p))
(def %set-rest!
  (fn (_ p v) (%ptr-set-word! (%obj->ptr p) %data-off-1 (%ptr->int (%obj->ptr v))) p))

; Int cells: read/write a raw machine integer in an object's first data
; word.  Reshaped from a pair-style first/rest accessor quartet (#231):
; every caller is a single-slot int CELL (the C-written sigint flag,
; reflect's counters, the profiler spine leaves), so the rest-slot half
; never had a caller -- the pair framing was the wrong design, not the
; unused half an accident.
(def %cell-int (fn (_ x) (%ptr-ref-word (%obj->ptr x) %data-off-0)))
(def %set-cell-int! (fn (_ p v) (%ptr-set-word! (%obj->ptr p) %data-off-0 v) p))

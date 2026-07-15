; Test harness: x-core.x + the object-layout descriptor as data
; (tools/obj-layout.x -- the committed header-word contract the obj-layout
; spec probes live objects against).
(include "lib/x-core.x")
(include "tools/obj-layout.x")

; Shared instruments, catalog-fetched ONCE per batch.  Every spec block used
; to re-fetch private copies; a missed edit in one block would probe stale
; coordinates while printing plausible output.  The fetches HERE are the pin:
; if a catalog coordinate moves, the whole file fails at once.
(def %obj->ptr     (prim-ref (lit obj) (lit ->ptr)))
(def %ptr->obj     (prim-ref (lit ptr) (lit ->obj)))
(def %ptr->int     (prim-ref (lit ptr) (lit ->int)))
(def %int->ptr     (prim-ref (lit int) (lit ->ptr)))
(def %ptr-ref-word (prim-ref (lit ptr) (lit ref-word)))
(def %meta-count!  (prim-ref (lit obj) (lit meta-count!)))
(def %meta-set!    (prim-ref (lit obj) (lit meta-set!)))
(def %meta-ref     (prim-ref (lit obj) (lit meta-ref)))
; Header-word probes over the descriptor slots.
(def %word  (fn (_ o slot) (%ptr-ref-word (%obj->ptr o) (* slot %word-size))))
(def %flags (fn (_ o) (& (%ptr-ref-word (%obj->ptr o) (* %obj-slot-flags %word-size))
                         (+ %obj-flag-type-mask %obj-flag-attr-mask))))

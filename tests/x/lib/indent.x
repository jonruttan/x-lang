; Test harness: x-core.x + x/reader/indent.
;
; The measurement and rule functions live under catalog ns `indent` for
; per-character callers who must not dispatch; the spec runs cold, so it
; fetches them once here and the cases use %adv / %msr / %cls.
(include "lib/x-core.x")
(import x/reader/indent)
(def %adv (prim-ref (lit indent) (lit advance)))
(def %msr (prim-ref (lit indent) (lit measure)))
(def %scn (prim-ref (lit indent) (lit scan)))
(def %cls (prim-ref (lit indent) (lit classify)))

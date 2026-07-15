; registry.x -- the primitives-catalog protocol, pure X (bootstrap stage 0)
;
; The FIRST file x-core loads: everything after it -- operatives.x included
; -- fetches its C instruments with prim-ref, so the protocol must exist
; before any other X code runs.  It can: the catalog is just a cell in the
; base spine (tools/base-paths.x, included immediately before this file),
; and reading it is a pure first/rest walk from (%base).  Uses ONLY the C
; spine forms (fn/def/match/lit + first/rest/eq?).
;
; This file replaces the C `prims`/`prim-domain`/`prim-ref` bindings (the
; C table rows are deleted; C still FILES the catalog at init through its
; internal registration path).  The producer half, prim-reg!, needs
; mutation (set-first!/set-rest!) and therefore lives in boot/reflect.x;
; `use` is retired outright (zero callers).

; Walk a step list (f = first, r = rest) from an object.  Interior steps
; land on spine pairs; the FINAL step's value is whatever the slot holds --
; an object for cell/spine slots, a raw int for int-slots (which callers
; must read with first-int/rest-int on the slot's parent instead).
(def %reflect-step
  (fn (loop o steps)
    (match
      ((eq? steps ()) o)
      ; nil-propagate: a step into a missing slot answers nil instead of
      ; first/rest on NULL (unchecked C -- a segfault).  Paths address
      ; OPTIONAL slots (e.g. an empty handler stack), so absent = nil.
      ((eq? o ()) ())
      ((eq? (first steps) (lit f)) (loop (first o) (rest steps)))
      (#t (loop (rest o) (rest steps))))))

; The step list filed under a path name, or nil.
(def %reflect-path
  (fn (loop name paths)
    (match
      ((eq? paths ()) ())
      ((eq? (first (first paths)) name) (rest (rest (first paths))))
      (#t (loop name (rest paths))))))

; Resolve a base-rooted path name to the object it addresses.
(def %reflect-base-cell
  (fn (_ name) (%reflect-step (%base) (%reflect-path name %base-paths))))

; The catalog cell, resolved once (spine-stable: its CONTENT mutates, the
; cell is never replaced).
(def %registry-prims-cell (%reflect-base-cell (lit prims)))

; The rest of the entry keyed k in an assoc list, or ().  Both catalog
; levels share this shape: ((ns . methods) ...) and ((method . value) ...).
; Keys are interned symbols, so eq? compares identity.
(def %registry-assoc-rest
  (fn (self k cur)
    (match
      ((eq? cur ()) ())
      ((eq? (first (first cur)) k) (rest (first cur)))
      (#t (self k (rest cur))))))

; The (ns . methods) domain PAIR itself, or () -- prim-reg! setcdrs it.
(def %registry-domain-pair
  (fn (self ns cur)
    (match
      ((eq? cur ()) ())
      ((eq? (first (first cur)) ns) (first cur))
      (#t (self ns (rest cur))))))

; --- the protocol (formerly C prims; semantics preserved exactly) ---
; (prims)                the catalog alist, for introspection and fetching
; (prim-domain ns)       the method alist filed under a namespace, or nil
; (prim-ref ns method)   the value filed under ns/method, or nil
(def prims (fn (_) (first %registry-prims-cell)))
(def prim-domain
  (fn (_ ns) (%registry-assoc-rest ns (first %registry-prims-cell))))
(def prim-ref
  (fn (_ ns method) (%registry-assoc-rest method (prim-domain ns))))

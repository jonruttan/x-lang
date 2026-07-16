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

; The step list filed under a path name.  A MISSING name ERRORS instead of
; answering nil: %reflect-step with steps=() returns the walked object
; ITSELF (root echo), so a typo'd path name would silently hand back the
; whole BASE -- and a consumer mutating "its cell" would overwrite
; interpreter spine words.  Every resolution happens at load time, so the
; error fires at boot, where the typo is.
(def %reflect-path
  (fn (loop name paths)
    (match
      ((eq? paths ()) (error (pair (lit missing-base-path) name)))
      ((eq? (first (first paths)) name) (rest (rest (first paths))))
      (#t (loop name (rest paths))))))

; Drop a step list's final step.  Descriptor paths END at the slot VALUE;
; mutators and int-slot readers need the PARENT node whose first/rest IS
; that slot -- so every "cell" derivation (the printer's handler pushes,
; the sys/type.x cell walkers, reflect.x's error-line read) flows through
; this one helper instead of re-flattening the walk by hand.  Stage-0 like
; the rest of this file: C spine forms only.
(def %reflect-path-parent
  (fn (self p)
    (match
      ((eq? (rest p) ()) ())
      (#t (pair (first p) (self (rest p)))))))

; Resolve a base-rooted path name to the object it addresses.
(def %reflect-base-cell
  (fn (_ name) (%reflect-step (%base) (%reflect-path name %base-paths))))

; The catalog cell, resolved once (spine-stable: its CONTENT mutates, the
; cell is never replaced).
(def %registry-prims-cell (%reflect-base-cell (lit prims)))

; The entry PAIR keyed k in an assoc list, or () -- prim-reg! setcdrs it.
; Both catalog levels share this shape: ((ns . methods) ...) and
; ((method . value) ...).  Keys are interned symbols, so eq? compares
; identity.  ONE walk; assoc-rest below is its value-projecting front.
(def %registry-domain-pair
  (fn (self ns cur)
    (match
      ((eq? cur ()) ())
      ((eq? (first (first cur)) ns) (first cur))
      (#t (self ns (rest cur))))))

; The rest of the entry keyed k, or ().  Nil guard is mandatory (first/rest
; are unchecked -- projecting a missed lookup would be UB), and it is a
; separate fn, not a do-body: `do` is X-defined and does not exist at
; stage 0.
(def %registry-rest-or-nil
  (fn (_ p)
    (match
      ((eq? p ()) ())
      (#t (rest p)))))
(def %registry-assoc-rest
  (fn (_ k cur) (%registry-rest-or-nil (%registry-domain-pair k cur))))

; --- the protocol (formerly C prims; semantics preserved exactly) ---
; (prims)                the catalog alist, for introspection and fetching
; (prim-domain ns)       the method alist filed under a namespace, or nil
; (prim-ref ns method)   the value filed under ns/method, or nil
(def prims (fn (_) (first %registry-prims-cell)))
(def prim-domain
  (fn (_ ns) (%registry-assoc-rest ns (first %registry-prims-cell))))
(def prim-ref
  (fn (_ ns method) (%registry-assoc-rest method (prim-domain ns))))

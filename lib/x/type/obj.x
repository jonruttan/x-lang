; type/obj.x -- Obj: raw object construction, slot access, metadata, and
; FFI handles.
;
; The C primitives live in src/x-prim/type.c and src/x-prim/ffi.c (catalog
; ns `obj`); the methods fetch inline per the cold rule. ns `obj` is
; DE-REGISTERED (R5): the class -- or a catalog fetch, for boot and other
; load-time callers (boot/data.x's pair mutators are built on these) -- is
; the only surface. eq? and same? also file under ns `obj` but are
; keep-list globals: the C binder's kept-names list keeps them bare.

(import x/type/object)

(def-class Obj ()
  (static
    (method make (self (param ts ANY "Type handle (from Type of / make-type)")
                       (param n INT "Number of slots"))
      (doc "Allocate a raw typed object with N nil slots (the Vector pattern: slot 0 = length)."
        (returns ANY "The new object"))
      ((prim-ref (lit obj) (lit make)) ts n))
    (method ref (self (param obj ANY "Object") (param i INT "Slot index (0-based)"))
      (doc "Read slot I of a raw object." (returns ANY "The slot value"))
      ((prim-ref (lit obj) (lit ref)) obj i))
    (method set! (self (param obj ANY "Object") (param i INT "Slot index (0-based)")
                       (param v ANY "Value to store"))
      (doc "Write slot I of a raw object." (returns ANY "nil"))
      ((prim-ref (lit obj) (lit set!)) obj i v))
    (method ->ptr (self (param obj ANY "Object"))
      (doc "The raw pointer of an object (FFI handle; see also Ptr)."
        (returns ANY "A PTR to the object's storage"))
      ((prim-ref (lit obj) (lit ->ptr)) obj))
    (method meta-count (self)
      (doc "The base-wide extra-metadata slot count (0 = metadata disabled)."
        (returns INT "Current extra-slot count"))
      ((prim-ref (lit obj) (lit meta-count))))
    (method meta-count! (self (param n INT "Extra slots to reserve per object"))
      (doc "Set the base-wide extra-metadata slot count; objects allocated afterwards carry N extra slots."
        (returns INT "The previous extra-slot count"))
      ((prim-ref (lit obj) (lit meta-count!)) n))
    (method meta-ref (self (param obj ANY "Object") (param i INT "Metadata slot index"))
      (doc "Read metadata slot I of an object (e.g. coverage flags, source line)."
        (returns ANY "The metadata value"))
      ((prim-ref (lit obj) (lit meta-ref)) obj i))
    (method meta-set! (self (param obj ANY "Object") (param i INT "Metadata slot index")
                            (param v ANY "Value to store"))
      (doc "Write metadata slot I of an object." (returns ANY "nil"))
      ((prim-ref (lit obj) (lit meta-set!)) obj i v))
    (method make-callable (self (param p ANY "C function pointer (PTR, e.g. from the JIT or dlsym)"))
      (doc "Wrap a C function pointer as a callable primitive object."
        (returns CALLABLE "The new callable"))
      ((prim-ref (lit obj) (lit make-callable)) p))))

(doc (provide x/type/obj Obj)
  (note "ns `obj` is de-registered -- no bare names; boot/hot callers fetch from the catalog.")
  "Raw object layer: construction, slot and metadata access, FFI handles, on the Obj class.")

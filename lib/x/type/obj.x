; type/obj.x -- Obj: raw object construction, slot access, metadata, and
; FFI handles.
;
; The C primitives live in src/x-prim/type.c and src/x-prim/ffi.c (catalogue
; ns `obj`); the methods fetch inline per the cold rule. ns `obj` is
; DE-REGISTERED (R5): the class -- or a catalogue fetch, for boot and other
; load-time callers (boot/data.x's pair mutators are built on these) -- is
; the only surface. eq? and same? also file under ns `obj` but are
; keep-list globals: the C binder's kept-names list keeps them bare.

(import x/type/class)

(def-class Obj ()
  (static
    (method make (self (param ts ANY "Type handle (from Type of / make-type)")
                       (param n INTEGER "Number of slots"))
      (doc "Allocate a raw typed object with N nil slots (the Vector pattern: slot 0 = length)."
        (note "GC CONTRACT: raw slots are traced only if the TYPE declares units -- ((prim-ref 'type 'set-units!) ts -1) for slot-0-counted sizes (the Vector convention), or a fixed count. Without it a collect frees the payloads under the object (otherwise the segfault a Dict hits across a REPL turn).")
        (returns ANY "The new object")
        (example "(let ((o (Obj make (Type of (Vector make 2 ())) 3))) (Obj set! o 1 42) (Obj ref o 1))" "42"))
      ((prim-ref (lit obj) (lit make)) ts n))
    (method ref (self (param obj ANY "Object") (param i INTEGER "Slot index (0-based)"))
      (doc "Read slot I of a raw object." (returns ANY "The slot value")
        (example "(Obj ref (pair 'a 'b) 1)" "'b"))
      ((prim-ref (lit obj) (lit ref)) obj i))
    (method set! (self (param obj ANY "Object") (param i INTEGER "Slot index (0-based)")
                       (param v ANY "Value to store"))
      (doc "Write slot I of a raw object." (returns ANY "nil")
        (example "(let ((p (pair 1 2))) (Obj set! p 1 9) p)" "(1 . 9)"))
      ((prim-ref (lit obj) (lit set!)) obj i v))
    (method ->ptr (self (param obj ANY "Object"))
      (doc "The raw pointer of an object (FFI handle; see also Ptr)."
        (returns ANY "A PTR to the object's storage")
        (example "(Ptr ptr? (Obj ->ptr (list 1 2)))" "#t"))
      ((prim-ref (lit obj) (lit ->ptr)) obj))
    (method meta-count (self)
      (doc "The base-wide extra-metadata slot count (0 = metadata disabled)."
        (returns INTEGER "Current extra-slot count")
        (sample "(Obj meta-count)" "the width this engine was set to: 0 with metadata off, 2 under the coverage and source-line slots"))
      ((prim-ref (lit obj) (lit meta-count))))
    (method meta-count! (self (param n INTEGER "Extra slots to reserve per object"))
      (doc "Set the base-wide extra-metadata slot count; objects allocated afterwards carry N extra slots. BOOT-TIME POLICY: setting a width DIFFERENT from the current one while allocated objects are live is undefined -- the engine frees each object's prefix at the width current at COLLECT time, so older objects are freed at the wrong address (x-engine-c#21). Setting the value it already holds is safe."
        (returns INTEGER "The previous extra-slot count")
        (sample "(Obj meta-count! 2)" "the width it held before; objects allocated from now on carry 2 extra slots"))
      ((prim-ref (lit obj) (lit meta-count!)) n))
    (method meta-ref (self (param obj ANY "Object") (param i INTEGER "Metadata slot index"))
      (doc "Read metadata slot I of an object (e.g. coverage flags, source line)."
        (returns ANY "The metadata value")
        (sample "(Obj meta-ref o 0)" "whatever metadata slot 0 of o holds, such as a coverage flag; only meaningful while (Obj meta-count) is above 0"))
      ((prim-ref (lit obj) (lit meta-ref)) obj i))
    (method meta-set! (self (param obj ANY "Object") (param i INTEGER "Metadata slot index")
                            (param v ANY "Value to store"))
      (doc "Write metadata slot I of an object." (returns ANY "nil")
        (sample "(Obj meta-set! o 1 42)" "stores 42 in metadata slot 1 of o; (Obj meta-ref o 1) reads it back"))
      ((prim-ref (lit obj) (lit meta-set!)) obj i v))
    (method make-callable (self (param p ANY "C function pointer (PTR, e.g. from the JIT or dlsym)"))
      (doc "Wrap a C function pointer as a callable primitive object."
        (returns CALLABLE "The new callable")
        (sample "(Obj make-callable (Ffi dlsym (Ffi dlopen () 1) \"getpid\"))" "a callable that runs the C function when applied"))
      ((prim-ref (lit obj) (lit make-callable)) p))))

(doc (provide x/type/obj Obj)
  (note "ns `obj` is de-registered -- no bare names; boot/hot callers fetch from the catalogue.")
  (example "(Obj ref (list 'a 'b) 0)" "'a")
  "Raw object layer: construction, slot and metadata access, FFI handles, on the Obj class.")

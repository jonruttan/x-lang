; name.x -- what a foreign address is called, from three sources that
; never go looking.
; lint-known: %isa-bare
;
; Imported by tools/dev/image-foreign.x (which counts them) and
; tools/dev/image-write.x (which emits them as the image's foreign table).
;
; Nothing here searches for a name, because nothing in x safely can: `first`
; is unchecked -- the C layer is a CPU -- so (first 5) reads a bad address;
; `pair?` answers #f for the structural pairs the base spine is built from; and
; %reflect-type-word is itself a dereference, so the test for "may I walk
; this?" is already the unsafe act.  Names are declared (the ISA's %isa-bare),
; looked up (the prims catalog), or asked of the linker (dladdr, round-trip
; checked).
;
; Plain defs in the root, with no module header, as x/tool/image/walk is
; and for its reason.  The ISA contract is read through the engine seam's
; root (lib/x/boot/engine.x).
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

(import x/tool/image/walk image-word-at image-obj->ptr image-int< image-int-)

; --- the naming sources: address -> the path it was found at ---------------
; The key is the C function pointer the primitive holds in unit 0, not the
; primitive object's own address -- a foreign unit is that pointer.  Two
; distinct primitive objects (catalog + and bare +) share one function and stay
; two object records in the image, so identity survives; what the foreign table
; names is the C function behind them.
(doc (def image-fnptr (fn (_ v) (image-word-at (image-obj->ptr v) 0)))
  (param v ANY "A primitive, or any object whose unit 0 is a function pointer")
  (returns INTEGER "The address unit 0 holds")
  "The C function pointer an object holds in its first unit.")
(def %image-prim? (fn (_ v) (str=? (Type name v) "PRIMITIVE")))

; A map is a plain list of (addr . label); ~150 entries, so a linear probe is
; cheaper than anything with structure.
; An entry is (fnptr . (label . payload)): label 1 catalog, 2 bare, 3 dlsym, and
; the payload is the NAME the loader will reacquire it by.  Kept as a list --
; ~130 entries, so a linear probe beats anything with structure.
(doc (def image-foreign-catalog 1)
  "Foreign label 1: a catalog primitive, named NAMESPACE/NAME.")
(doc (def image-foreign-bare 2)
  "Foreign label 2: a bare global the engine binds, named by its symbol.")
(doc (def image-foreign-dlsym 3)
  "Foreign label 3: a symbol of the dynamic linker, named as dlsym takes it.")
(doc (def image-name-map-add (fn (_ m a label payload) (pair (pair a (pair label payload)) m)))
  (param m LIST "Naming map")
  (param a INTEGER "Address to name")
  (param label INTEGER "Foreign label")
  (param payload STRING "The name the loader reacquires the address by")
  (returns LIST "The map with the entry in front")
  "Add one address to a naming map.")
(doc (def image-name-map-get
  (fn (self m a)
    (if (null? m) ()
      (if (eq? (first (first m)) a) (rest (first m)) (self (rest m) a)))))
  (param m LIST "Naming map")
  (param a INTEGER "Address to look up")
  (returns PAIR "(label . name), or nil when the map does not name the address")
  "Look an address up in a naming map.")

; catalog: LIST of (ns . ((name . value) ...))
(def %image-from-catalog
  (fn (self cat m)
    (if (null? cat) m
      (self (rest cat) (%image-from-methods (rest (first cat)) m (first (first cat)))))))
(def %image-from-methods
  (fn (self ms m ns)
    (if (null? ms) m
      (self (rest ms) (%image-method-add (first ms) m ns) ns))))
(def %image-method-add
  (fn (_ e m ns)
    (if (%image-prim? (rest e))
      (image-name-map-add m (image-fnptr (rest e)) image-foreign-catalog
        (Str append (symbol->str ns) "/" (symbol->str (first e))))
      m)))

; The base env is NOT made of heap pairs.  It is the base's static spine --
; structural pairs built at base creation -- and `pair?` and `atom?` both
; answer about heap objects, so `pair?` is #f and `atom?` is #t for a binding
; that first/rest walk perfectly well.  The type word is what tells the truth.
(def %image-walkable?
  (fn (_ x)
    (if (null? x) #f
      (if (pair? x) #t (eq? (%reflect-type-word x) %reflect-spair-tw)))))
(def %image-from-env
  (fn (self x m d)
    (if (image-int< d 0) m
      (if (%image-walkable? x)
        ; `rest` is list traversal at the SAME level and must not spend depth:
        ; spending it there bounded the number of BINDINGS seen, not the nesting.
        (%image-from-env (rest x) (%image-from-env (first x) (%image-from-entry x m) (image-int- d 1)) d)
        m))))
(def %image-from-entry
  (fn (_ x m)
    (if (%image-walkable? x)
      (if (%image-prim? (rest x)) (image-name-map-add m (image-fnptr (rest x)) 2) m)
      m)))

; Catalog only.  Walking the base env for the bare bindings crashes exactly as
; docs/state-images.md predicts: a structural pair in the base tree may hold a
; raw C function pointer (the collector's own hooks), so following it as a
; reference is a wild read.  The bare bindings must come through base-paths.x
; step lists, not a generic descent -- which is the next piece of work, not a
; thing to bodge here.
; --- source 2: the bare globals, from the ISA contract -------------------
;
; The engine DECLARES its bare globals -- %isa-bare in the ISA contract -- so
; they can be looked up by name instead of hunted for.  That matters because
; nothing in x may go looking: `first` is unchecked (the C layer is a CPU), so
; (first 5) segfaults, `pair?` answers #f for the structural pairs the base
; spine is made of, and %reflect-type-word IS a dereference -- asking "may I
; walk this?" is already the unsafe act.  Two attempts to walk the spine for
; these names crashed, once generically and once over a single flat list.
;
; Looking a name up cannot crash: eval raises catchably when it is unbound,
; and Type name is safe on any value including immediates.  A name the library
; has rebound (the six raw bitwise operators, wrapped by core/arithmetic.x)
; yields the wrapper, not the primitive, and is simply not added -- those
; survive only inside a closure, which docs/state-images.md already records.
(include (Str append %engine-root "/tools/contract/isa.x"))
(def %image-from-bare
  (fn (self rows m b)
    (if (null? rows) m (self (rest rows) (%image-bare-add (first (first rows)) m b) b))))
(def %image-bare-add
  (fn (_ nm m b)
    (guard (_ m)
      ((fn (_ v) (if (%image-prim? v) (image-name-map-add m (image-fnptr v) image-foreign-bare (symbol->str nm)) m))
       (b eval nm)))))

; NOT by walking the base env, and two failed attempts are why.
;
; The bare bindings live in the base's STATIC SPINE and nothing here may walk
; it.  A generic descent crashes as docs/state-images.md predicts -- a
; structural pair there may hold a raw C function pointer, the collector's own
; hooks, and following it as a reference is a wild read.  Restricting to one
; flat rest-only pass crashes too, for a subtler reason: asking
; %reflect-type-word what a slot holds IS a dereference, so the test for "may I
; walk this?" is already the unsafe act.  Looking a DECLARED name up cannot
; crash, which is why %isa-bare is the door.
;
; Built FOR a base rather than for the ambient one: the writer images a child,
; whose catalog and bare bindings are its own.
(doc (def image-name-map
  (fn (_ b)
    (%image-from-bare %isa-bare (%image-from-catalog (first (b cell (lit prims))) ()) b)))
  (param b ANY "The base to name: a Base instance")
  (returns LIST "Entries (address . (label . name)), for the base's catalog and bare primitives")
  "Build the naming map of a base from its prims catalog and the bare globals the ISA contract declares.")

; --- the call pointer a whole TYPE shares -----------------------------------
; A PROCEDURE's unit 0 is the engine's procedure-call function, and EVERY
; procedure holds the same one; operatives likewise hold theirs.  Such an
; address has no useful symbol -- it is internal, so dladdr names it and dlsym
; will not give it back -- and it needs none: a loader creating an object of
; that type gives it the type's own call pointer.  The writer recognises one
; by its type: the word the type's call handler holds (image-write.x).
(doc (def image-foreign-typecall 4)
  "Foreign label 4: the call pointer a whole type shares, named by the type.")
; A dlopen HANDLE is not a symbol and dladdr will never name one: the
; writer's own, re-opened by the loader.
(doc (def image-foreign-dlopen 5)
  "Foreign label 5: a dlopen handle, which the loader opens again.")

; --- source 3: ask the dynamic linker what an address is called -----------
;
; The pointers left over are dlsym results -- the census in the document counts
; sixteen over one dlopen handle.  Nothing declares them, but nothing has to:
; dladdr maps an address back to its symbol, and dlsym maps that symbol back to
; the address.  The round trip is CHECKED here rather than assumed, because a
; name that does not resolve is worse than no name -- macOS reports getpid as
; "__getpid", which does dlsym back to the same address, and a mechanism that
; silently produced unresolvable names would look like coverage.
(doc (def image-dl-handle (Ffi dlopen () 1))
  "This process's dlopen handle on itself, the one the names are asked of.")
(def %image-c-dladdr (Ffi dlsym image-dl-handle "dladdr"))
; The engine's allocator.  dlopen/dlsym/dladdr stay: naming a C function is
; the dynamic linker's job, and there is no engine-side substitute for it.
(def %image-dl-buf ((prim-ref (lit ptr) (lit alloc)) 64))
(def %image-dli-sname 16)   ; Dl_info: fname, fbase, sname, saddr
; Returns the symbol NAME if it round-trips back to the same address, else nil.
; The round trip is checked rather than assumed: macOS reports getpid as
; "__getpid", which does resolve back, and a mechanism quietly producing
; unresolvable names would look exactly like coverage.
(doc (def image-dl-name
  (fn (_ w)
    (if (eq? (Ptr call %image-c-dladdr w %image-dl-buf) 0) () (%image-dl-check w (Ptr ref-word %image-dl-buf %image-dli-sname)))))
  (param w INTEGER "Address to name")
  (returns STRING "The symbol's name, or nil when none resolves back to the address")
  "Ask the dynamic linker what an address is called, and keep the name only if dlsym gives the address back.")
(def %image-dl-check
  (fn (_ w sname)
    (if (eq? sname 0) ()
      (guard (_ ())
        (%image-dl-verify w (Ptr ->str (Ptr from-int sname)))))))
(def %image-dl-verify
  (fn (_ w nm)
    ((fn (_ back) (if (null? back) () (if (eq? (Ptr ->int back) w) nm ())))
     (Ffi dlsym image-dl-handle nm))))
(doc (def image-dl-round-trips? (fn (_ w) (if (null? (image-dl-name w)) #f #t)))
  (param w INTEGER "Address to name")
  (returns BOOL "#t when the dynamic linker names the address and the name resolves back")
  "Whether image-dl-name has a name for an address.")

(doc (provide x/tool/image/name
  image-name-map image-name-map-add image-name-map-get image-fnptr
  image-dl-name image-dl-round-trips? image-dl-handle
  image-foreign-catalog image-foreign-bare image-foreign-dlsym
  image-foreign-typecall image-foreign-dlopen)
  "Names for the foreign addresses a state image holds.")

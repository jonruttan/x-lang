; image-name.x -- what a foreign address is called, from three sources that
; never go looking.
;
; Included by tools/dev/image-foreign.x (which counts them) and
; tools/dev/image-write.x (which emits them as the image's foreign table).
;
; NOTHING HERE HUNTS FOR A NAME, because nothing in x safely can: `first` is
; unchecked -- the C layer is a CPU -- so (first 5) segfaults; `pair?` answers
; #f for the structural pairs the base spine is built from; and
; %reflect-type-word IS a dereference, so the test for "may I walk this?" is
; already the unsafe act.  Names are DECLARED (the ISA's %isa-bare), LOOKED UP
; (the prims catalog), or ASKED OF THE LINKER (dladdr, round-trip checked).
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

(include "tools/dev/image-walk.x")

; --- the naming sources: address -> the path it was found at ---------------
; The KEY is the C function pointer the primitive holds in unit 0, not the
; primitive object's own address -- a foreign unit IS that pointer.  Two
; distinct primitive objects (catalog + and bare +) share one function, and
; that is correct: they stay two object records in the image, so identity
; survives; what the foreign table names is the C function behind them.
(def %fnptr (fn (_ v) (%word-at (%o->p v) 0)))
(def %prim? (fn (_ v) (str=? (Type name v) "PRIMITIVE")))

; A map is a plain list of (addr . tag); ~150 entries, so a linear probe is
; cheaper than anything with structure.
; An entry is (fnptr . (kind . payload)): kind 1 catalog, 2 bare, 3 dlsym, and
; the payload is the NAME the loader will reacquire it by.  Kept as a list --
; ~130 entries, so a linear probe beats anything with structure.
(def %F-CATALOG 1)
(def %F-BARE 2)
(def %F-DLSYM 3)
(def %map-add (fn (_ m a kind payload) (pair (pair a (pair kind payload)) m)))
(def %map-get
  (fn (self m a)
    (if (null? m) ()
      (if (eq? (first (first m)) a) (rest (first m)) (self (rest m) a)))))

; catalog: LIST of (ns . ((name . value) ...))
(def %from-catalog
  (fn (self cat m)
    (if (null? cat) m
      (self (rest cat) (%from-methods (rest (first cat)) m (first (first cat)))))))
(def %from-methods
  (fn (self ms m ns)
    (if (null? ms) m
      (self (rest ms) (%method-add (first ms) m ns) ns))))
(def %method-add
  (fn (_ e m ns)
    (if (%prim? (rest e))
      (%map-add m (%fnptr (rest e)) %F-CATALOG
        (Str append (symbol->str ns) "/" (symbol->str (first e))))
      m)))

; The base env is NOT made of heap pairs.  It is the base's static spine --
; structural pairs built at base creation -- and `pair?` and `atom?` both
; answer about heap objects, so `pair?` is #f and `atom?` is #t for a binding
; that first/rest walk perfectly well.  The type word is what tells the truth.
(def %walkable?
  (fn (_ x)
    (if (null? x) #f
      (if (pair? x) #t (eq? (%reflect-type-word x) %reflect-spair-tw)))))
(def %from-env
  (fn (self x m d)
    (if (%ilt d 0) m
      (if (%walkable? x)
        ; `rest` is list traversal at the SAME level and must not spend depth:
        ; spending it there bounded the number of BINDINGS seen, not the nesting.
        (%from-env (rest x) (%from-env (first x) (%from-entry x m) (%int- d 1)) d)
        m))))
(def %from-entry
  (fn (_ x m)
    (if (%walkable? x)
      (if (%prim? (rest x)) (%map-add m (%fnptr (rest x)) 2) m)
      m)))

; CATALOG ONLY.  Walking the base env for the bare bindings crashes exactly as
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
(include "engine/tools/contract/isa.x")
(def %from-bare
  (fn (self rows m)
    (if (null? rows) m (self (rest rows) (%bare-add (first (first rows)) m)))))
(def %bare-add
  (fn (_ nm m)
    (guard (_ m)
      ((fn (_ v) (if (%prim? v) (%map-add m (%fnptr v) %F-BARE (symbol->str nm)) m))
       (eval nm)))))

; NOT the base env, and the two failed attempts are why.
;
; The bare bindings live in the base's STATIC SPINE, and nothing here may walk
; it.  A generic descent crashes as docs/state-images.md predicts: a structural
; pair in the base tree may hold a raw C function pointer (the collector's own
; hooks), and following it as a reference is a wild read.  Restricting to one
; flat `rest`-only pass over the boot frame crashes too, for a subtler reason
; -- the predicate itself.  Asking %reflect-type-word what a slot holds IS a
; dereference, so the test for "may I walk this?" is already the unsafe act.
;
; Both attempts are the same mistake at different depths: the spine can only be
; read through base-layout.x and base-paths.x, whose rows say which leaves are
; cells, which are direct values and which are external.  That is the next
; piece of work.
(def %MAP
  (%from-bare %isa-bare
    (%from-catalog (first (%reflect-base-cell (lit prims))) ())))

(def %mlen (fn (self m n) (if (null? m) n (self (rest m) (%int+ n 1)))))

; --- source 3: ask the dynamic linker what an address is called -----------
;
; The pointers left over are dlsym results -- the census in the document counts
; sixteen over one dlopen handle.  Nothing declares them, but nothing has to:
; dladdr maps an address back to its symbol, and dlsym maps that symbol back to
; the address.  The round trip is CHECKED here rather than assumed, because a
; name that does not resolve is worse than no name -- macOS reports getpid as
; "__getpid", which does dlsym back to the same address, and a mechanism that
; silently produced unresolvable names would look like coverage.
(def %lib (Ffi dlopen () 1))
(def %c-dladdr (Ffi dlsym %lib "dladdr"))
(def %dl-buf (Ptr from-int (Ptr call (Ffi dlsym %lib "malloc") 64)))
(def %DLI-SNAME 16)   ; Dl_info: fname, fbase, sname, saddr
; Returns the symbol NAME if it round-trips back to the same address, else nil.
; The round trip is checked rather than assumed: macOS reports getpid as
; "__getpid", which does resolve back, and a mechanism quietly producing
; unresolvable names would look exactly like coverage.
(def %dl-name
  (fn (_ w)
    (if (eq? (Ptr call %c-dladdr w %dl-buf) 0) () (%dl-check w (Ptr ref-word %dl-buf %DLI-SNAME)))))
(def %dl-check
  (fn (_ w sname)
    (if (eq? sname 0) ()
      (guard (_ ())
        (%dl-verify w (Ptr ->str (Ptr from-int sname)))))))
(def %dl-verify
  (fn (_ w nm)
    ((fn (_ back) (if (null? back) () (if (eq? (Ptr ->int back) w) nm ())))
     (Ffi dlsym %lib nm))))
(def %dl-round-trips? (fn (_ w) (if (null? (%dl-name w)) #f #t)))


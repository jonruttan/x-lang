; image-foreign.x -- which foreign units a state image can name, and how many
; it still cannot.
;
;   sh x.sh -q -f tools/dev/image-foreign.x
;
; Every foreign unit in the heap holds a raw address, and no address survives
; into another process.  So each one has to be REACQUIRED by name, and this
; counts how far the naming sources actually reach.  Run it beside
; tools/dev/image-write.x, whose foreign table this measures the inputs to.
;
; THE KEY IS THE C FUNCTION POINTER, NOT THE OBJECT ADDRESS.  A foreign unit
; IS the function pointer a primitive holds in unit 0; keying a naming map on
; the primitive object's own address matches nothing, which is what the first
; version of this did (0 of 146).  Nor does keying on the function merge
; anything it should not: the catalog's `+` and the bare `+` are two distinct
; objects sharing one C function, and they stay two records in the image, so
; identity survives.  docs/state-images.md's warning is about naming an OBJECT
; by a path that yields an equal value, which is a different thing.
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

(include "tools/dev/image-walk.x")

; --- the naming sources: address -> the path it was found at ---------------
(def %p->i (prim-ref (lit ptr) (lit ->int)))
; The KEY is the C function pointer the primitive holds in unit 0, not the
; primitive object's own address -- a foreign unit IS that pointer.  Two
; distinct primitive objects (catalog + and bare +) share one function, and
; that is correct: they stay two object records in the image, so identity
; survives; what the foreign table names is the C function behind them.
(def %fnptr (fn (_ v) (%word-at (%o->p v) 0)))
(def %prim? (fn (_ v) (str=? (Type name v) "PRIMITIVE")))

; A map is a plain list of (addr . tag); ~150 entries, so a linear probe is
; cheaper than anything with structure.
(def %map-add (fn (_ m a tag) (pair (pair a tag) m)))
(def %map-get
  (fn (self m a)
    (if (null? m) ()
      (if (eq? (first (first m)) a) (rest (first m)) (self (rest m) a)))))

; catalog: LIST of (ns . ((name . value) ...))
(def %from-catalog
  (fn (self cat m)
    (if (null? cat) m
      (self (rest cat) (%from-methods (rest (first cat)) m)))))
(def %from-methods
  (fn (self ms m)
    (if (null? ms) m
      (self (rest ms)
        (if (%prim? (rest (first ms))) (%map-add m (%fnptr (rest (first ms))) 1) m)))))

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
      ((fn (_ v) (if (%prim? v) (%map-add m (%fnptr v) 2) m)) (eval nm)))))

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
(display "catalog entries: ") (write (%mlen %MAP 0)) (newline)

; --- source 3: ask the dynamic linker what an address is called -----------
;
; The pointers left over are dlsym results -- the census in the document counts
; sixteen over one dlopen handle.  Nothing declares them, but nothing has to:
; dladdr maps an address back to its symbol, and dlsym maps that symbol back to
; the address.  The round trip is CHECKED here rather than assumed, because a
; name that does not resolve is worse than no name -- macOS reports getpid as
; "__getpid", which does dlsym back to the same address, and a mechanism that
; silently produced unresolvable names would look like coverage.
(def %lib ((prim-ref (lit ffi) (lit dlopen)) () 1))
(def %dlsym (prim-ref (lit ffi) (lit dlsym)))
(def %pcall (prim-ref (lit ptr) (lit call)))
(def %p->i (prim-ref (lit ptr) (lit ->int)))
(def %p->s (prim-ref (lit ptr) (lit ->str)))
(def %c-dladdr (%dlsym %lib "dladdr"))
(def %dl-buf ((prim-ref (lit int) (lit ->ptr)) (%pcall (%dlsym %lib "malloc") 64)))
(def %DLI-SNAME 16)   ; Dl_info: fname, fbase, sname, saddr
(def %dl-round-trips?
  (fn (_ w)
    (if (eq? (%pcall %c-dladdr w %dl-buf) 0) #f (%dl-check w (%rw %dl-buf %DLI-SNAME)))))
(def %dl-check
  (fn (_ w sname)
    (if (eq? sname 0) #f
      (guard (_ #f)
        ((fn (_ back) (if (null? back) #f (eq? (%p->i back) w)))
         (%dlsym %lib (%p->s ((prim-ref (lit int) (lit ->ptr)) sname))))))))

; --- census: classify every foreign unit in the heap -----------------------
; acc = (catalog-named bare-named . unnamed)
(def %census
  (fn (_ k w acc)
    (if (eq? k 3) (%tally (%map-get %MAP w) acc w) acc)))
(def %tally
  (fn (_ tag acc w)
    (if (null? tag) (%tally-miss acc w)
      (if (eq? tag 1) (pair (%int+ (first acc) 1) (rest acc))
        (pair (first acc) (pair (%int+ (first (rest acc)) 1) (rest (rest acc))))))))
(def %tally-miss
  (fn (_ acc w)
    (pair (first acc)
      (pair (first (rest acc))
        (if (%dl-round-trips? w)
          (pair (%int+ (first (rest (rest acc))) 1) (rest (rest (rest acc))))
          (pair (first (rest (rest acc))) (%int+ (rest (rest (rest acc))) 1)))))))
(def %f-walk (fn (_ p acc) (%over-units p %census acc)))

(%collect)
(%mark! (%base) %TRACE)
((fn (_ r)
   (do (display "foreign units named by catalog: ") (write (first (first r))) (newline)
       (display "               by bare binding: ") (write (first (rest (first r)))) (newline)
       (display "            by dladdr round-trip: ") (write (first (rest (rest (first r))))) (newline)
       (display "                       UNNAMED: ") (write (rest (rest (rest (first r))))) (newline)
       (display "                       visited: ") (write (rest r)) (newline)))
 (%walk (pair 1 2) %f-walk (pair 0 (pair 0 (pair 0 0)))))
(%clear! %TRACE)

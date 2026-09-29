; walk.x -- one heap walk and one unit reader, shared by the image tools.
;
; Imported by x/tool/image/name and by tools/dev/image-write.x,
; image-inspect.x and image-foreign.x, so the rules below hold in one place
; rather than in a copy each.
;
;   (image-walk start f acc)  ->  (acc . visited)
;
; f is called (f p acc) for each traced object, p a pointer to it.  The visited
; count is returned so a vacuous walk is visible: a pass reporting a clean zero
; over zero objects is not a clean pass.
;
;   * Nothing walks bytes.  An interpreted per-byte loop costs hundreds of
;     evals a byte; this is lib/x/tool/asm-cache.x's rule, for its reason.
;   * No `def` between the mark and the last walk.  A def repoints an
;     environment pair -- itself a traced object in the image -- at a value
;     the stamping pass never saw, and each one surfaces as an unresolved
;     reference.
;   * The cursor is an object, never a pointer.  An object held in a parameter
;     is rooted, so a collect cannot free it under the walk; a ptr roots
;     nothing it addresses.  A cursor freed under the walk visits nothing and
;     reports a clean zero of everything.
;
; Plain defs in the root, with no module header: the walk runs once per
; object, and a module's frame would sit in front of every root lookup made
; from inside it (docs/namespaces.md, "What to measure first").  The object
; layout the offsets below are computed from -- %obj-slot-heap and its
; neighbours -- is the engine's contract, loaded by lib/x/boot/engine.x.
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

(doc (def image-obj->ptr (prim-ref (lit obj) (lit ->ptr)))
  (param o ANY "Object to address")
  (returns POINTER "A pointer to the object's header")
  "The engine's (obj ->ptr): the address of an object, as a pointer.")
(doc (def image-ptr->obj (prim-ref (lit ptr) (lit ->obj)))
  (param p POINTER "Pointer to an object's header")
  (returns ANY "The object at that address")
  "The engine's (ptr ->obj): the object a pointer addresses.")
(doc (def image-int->ptr (prim-ref (lit int) (lit ->ptr)))
  (param i INTEGER "Address")
  (returns POINTER "A pointer to that address")
  "The engine's (int ->ptr): an integer address as a pointer.")
(doc (def image-ref-word (prim-ref (lit ptr) (lit ref-word)))
  (param p POINTER "Base address")
  (param off INTEGER "Offset from it, in bytes")
  (returns INTEGER "The machine word read there")
  "The engine's (ptr ref-word): read one machine word.")
(doc (def image-int+ (prim-ref (lit int) (lit +)))
  (param a INTEGER "First addend")
  (param b INTEGER "Second addend")
  (returns INTEGER "Their sum")
  "The engine's (int +), which the number tower does not wrap.")
(doc (def image-int& (prim-ref (lit int) (lit &)))
  (param a INTEGER "First operand")
  (param b INTEGER "Second operand")
  (returns INTEGER "Their bitwise and")
  "The engine's (int &), which the number tower does not wrap.")
(doc (def image-collect (prim-ref (lit heap) (lit collect)))
  (returns ANY "What the engine's collect answers")
  "The engine's (heap collect): collect this base's heap.")
(doc (def image-heap-count (prim-ref (lit heap) (lit count)))
  (returns INTEGER "The number of live objects")
  "The engine's (heap count): how many objects this base's heap holds.")
(doc (def image-mark! (prim-ref (lit heap) (lit tree-mark!)))
  (param root ANY "Object to mark from")
  (param flag INTEGER "Flag bit to set")
  (returns ANY "What the engine's mark answers")
  "The engine's (heap tree-mark!): set a flag on every object reachable from root.")
(doc (def image-clear! (prim-ref (lit heap) (lit chain-clear!)))
  (param flag INTEGER "Flag bit to clear")
  (returns ANY "What the engine's clear answers")
  "The engine's (heap chain-clear!): clear a flag on every object of the chain.  A mark made after a clear flags nothing, so a process marks once.")
(doc (def image-trace-flag %obj-flag-trace)
  "The flag bit a mark sets and a walk reads, from the object layout contract.")
(doc (def image-heap-off  (* %obj-slot-heap  %word-size))
  "Byte offset of an object's heap link, the next object on the chain.")
(doc (def image-flags-off (* %obj-slot-flags %word-size))
  "Byte offset of an object's flags word.")
(def %image-next (fn (_ p) (image-ref-word p image-heap-off)))
(doc (def image-traced? (fn (_ p) (if (eq? (image-int& (image-ref-word p image-flags-off) image-trace-flag) 0) #f #t)))
  (param p POINTER "Pointer to an object's header")
  (returns BOOL "#t when the object carries the trace flag")
  "Whether the mark reached the object at p.")

; image-walk visits only traced objects and so needs a mark; image-walk-all
; visits every object on the chain and needs none.  Two rules force that
; distinction:
;
;   * One mark per process.  (heap chain-clear!) permanently disables any
;     later (heap tree-mark!): marking twice with no clear between is
;     idempotent, but a mark after a clear flags nothing at all, silently, and
;     every subsequent walk reports a clean zero of everything.  A pass that
;     needs no reachability must not spend the one mark -- it uses
;     image-walk-all and runs before the mark, which also lets it `def` its
;     results freely.
;   * No collect while a cursor points into another base's chain (spec 4.1).
;     The periodic collect below is this base's; it marks whatever this
;     base's frames hold -- the cursor, an object on the other chain -- and a
;     sweep clears flags on this chain only, so every collect during such a
;     walk leaves the other base with stale mark bits.  A walk over a child
;     turns the periodic collect off with image-walk-collect! and collects
;     between walks instead.
(def %image-walk-collect #t)
(doc (def image-walk-collect! (fn (_ on) (set! %image-walk-collect on)))
  (param on BOOL "#t for a collect every 1024 objects walked, #f for none")
  (returns ANY "Unspecified")
  "Turn the walk's periodic collect on or off.  It starts on; a walk over another base's chain runs with it off.")
(doc (def image-walk-collect? (fn (_) %image-walk-collect))
  (returns BOOL "#t when a walk collects as it goes")
  "Whether the walk's periodic collect is on.")
(doc (def image-walk     (fn (_ cur f acc) (%image-walk-on cur f acc 0 0 #t)))
  (param cur ANY "Cursor: an object on the chain to walk, never a pointer")
  (param f CALLABLE "Called (f p acc) with a pointer to each object visited")
  (param acc ANY "Starting accumulator")
  (returns PAIR "(acc . visited): the fold's result and the count of objects visited")
  "Fold f over every traced object on the chain from cur.  Needs a mark.")
(doc (def image-walk-all (fn (_ cur f acc) (%image-walk-on cur f acc 0 0 #f)))
  (param cur ANY "Cursor: an object on the chain to walk, never a pointer")
  (param f CALLABLE "Called (f p acc) with a pointer to each object visited")
  (param acc ANY "Starting accumulator")
  (returns PAIR "(acc . visited): the fold's result and the count of objects visited")
  "Fold f over every object on the chain from cur, traced or not.  Needs no mark.")
(def %image-take? (fn (_ p filt) (if filt (image-traced? p) #t)))
(def %image-walk-on
  (fn (_ cur f acc n seen filt)
    (%image-walk-after cur f
      (if (%image-take? (image-obj->ptr cur) filt) (f (image-obj->ptr cur) acc) acc)
      n
      (if (%image-take? (image-obj->ptr cur) filt) (image-int+ seen 1) seen) filt)))
(def %image-walk-after
  (fn (_ cur f acc n seen filt)
    (do (if %image-walk-collect (if (eq? (image-int& n 1023) 0) (image-collect) ()) ())
        (if (eq? (%image-next (image-obj->ptr cur)) 0)
            (pair acc seen)
            (%image-walk-on (image-ptr->obj (image-int->ptr (%image-next (image-obj->ptr cur)))) f acc
                      (image-int+ n 1) seen filt)))))

; --- unit labels ----------------------------------------------------------
(doc (def image-int- (prim-ref (lit int) (lit -)))
  (param a INTEGER "Minuend")
  (param b INTEGER "Subtrahend")
  (returns INTEGER "Their difference")
  "The engine's (int -), which the number tower does not wrap.")
(doc (def image-int* (prim-ref (lit int) (lit *)))
  (param a INTEGER "First factor")
  (param b INTEGER "Second factor")
  (returns INTEGER "Their product")
  "The engine's (int *), which the number tower does not wrap.")
(doc (def image-int>> (prim-ref (lit int) (lit >>)))
  (param a INTEGER "Value to shift")
  (param n INTEGER "Bits to shift by")
  (returns INTEGER "a shifted right by n bits")
  "The engine's (int >>), which the number tower does not wrap.")
(doc (def image-int< (prim-ref (lit int) (lit <)))
  (param a INTEGER "First operand")
  (param b INTEGER "Second operand")
  (returns BOOL "#t when a is less than b")
  "The engine's (int <), which the number tower does not wrap.")
(doc (def image-set-word! (prim-ref (lit ptr) (lit set-word!)))
  (param p POINTER "Base address")
  (param off INTEGER "Offset from it, in bytes")
  (param w INTEGER "Word to write")
  (returns ANY "What the engine's write answers")
  "The engine's (ptr set-word!): write one machine word.")
(doc (def image-ptr->str (prim-ref (lit ptr) (lit ->str)))
  (param p POINTER "Pointer to NUL-terminated bytes")
  (returns STRING "A string of those bytes")
  "The engine's (ptr ->str): the string at an address.")
(doc (def image-byte-len (prim-ref (lit str) (lit byte-len)))
  (param s STRING "String to measure")
  (returns INTEGER "Its length in bytes")
  "The engine's (str byte-len): a string's length in bytes.")
(doc (def image-type-off (* %obj-slot-type %word-size))
  "Byte offset of an object's type word.")
(def %image-data-off (* %obj-meta-len  %word-size))
(def %image-meta1-off (- 0 (* 2 %word-size)))
(def %image-meta-bit %obj-flag-meta)
(def %image-flagged? (fn (_ p) (if (eq? (image-int& (image-ref-word p image-flags-off) %image-meta-bit) 0) #f #t)))
;  A units value is one of THREE things -- docs/state-image-format.md 3.3 --
; and the third is not an integer: a type the library registered holds the
; engine's static x_type_units_pair_obj (type word 0), which means what
; make-instance allocates, two reference units.  The writer and the
; inspector read unit labels through here.
(doc (def image-unit-labels-static? (fn (_ u) (eq? (%reflect-type-word u) 0)))
  (param u ANY "A type's units value")
  (returns BOOL "#t when it is the engine's static units pair")
  "Whether a units value is the static one every library-registered type holds.")
(doc (def image-unit-labels-count
  (fn (_ u)
    (if (eq? (%reflect-type-word u) %reflect-spair-tw) (image-int+ 0 (first u))
      (if (image-unit-labels-static? u) 2 (image-int+ 0 u)))))
  (param u ANY "A type's units value")
  (returns INTEGER "The unit count it declares; negative for a counted tail")
  "The unit count of a units value, whichever of its three forms it takes.")
(doc (def image-unit-labels-mask
  (fn (_ u) (if (eq? (%reflect-type-word u) %reflect-spair-tw) (image-int+ 0 (rest u)) 0)))
  (param u ANY "A type's units value")
  (returns INTEGER "Two bits of label per described unit, or 0")
  "The unit-label mask of a units value.")
(doc (def image-unit-labels-desc  (fn (_ c) (if (image-int< c 0) (image-int+ 1 (image-int- 0 c)) c)))
  (param c INTEGER "A unit count, as image-unit-labels-count answers")
  (returns INTEGER "How many units the mask describes")
  "The number of units the mask describes; the last description repeats for any unit past it.")
(doc (def image-unit-label (fn (_ m i d) (image-int& (image-int>> m (image-int* 2 (if (image-int< i d) i (image-int- d 1)))) 3)))
  (param m INTEGER "Unit-label mask")
  (param i INTEGER "Unit index")
  (param d INTEGER "Units the mask describes")
  (returns INTEGER "The label of unit i")
  "The label of one unit, read from the mask.")
; The units cell of a type word; the catalog prim is fetched once, here, and
; closed over -- this runs per object walked.
(def %image-cell-of
  (let ((%units-cell (prim-ref (lit type) (lit units-cell))))
    (fn (_ tw) (first (%units-cell (image-ptr->obj (image-int->ptr tw)))))))
(def %image-count-of
  (fn (_ p u)
    (if (image-int< (image-unit-labels-count u) 0)
        (image-int+ (image-ref-word p %image-data-off) (image-int- 0 (image-unit-labels-count u)))
        (image-unit-labels-count u))))
(doc (def image-word-at (fn (_ p i) (image-ref-word p (image-int+ %image-data-off (image-int* i %word-size)))))
  (param p POINTER "Pointer to an object's header")
  (param i INTEGER "Unit index")
  (returns INTEGER "The word unit i holds")
  "Read one unit of the object at p.")

(doc (def image-over-units
  (fn (_ p g acc)
    (%image-over-tw p (image-ref-word p image-type-off) g acc)))
  (param p POINTER "Pointer to an object's header")
  (param g CALLABLE "Called (g label word acc) for each unit")
  (param acc ANY "Starting accumulator")
  (returns ANY "The fold's result")
  "Fold g over each unit of the object at p, by the unit labels its type declares.")
(def %image-over-tw
  (fn (_ p tw g acc)
    (if (eq? tw %reflect-satom-tw) (g 1 (image-word-at p 0) acc)
      (if (eq? tw 0) (g 1 (image-word-at p 0) acc)
        (if (eq? tw %reflect-spair-tw) (%image-units p g acc 0 2 0 2)
          (%image-over-cell p (%image-cell-of tw) g acc))))))
(def %image-over-cell
  (fn (_ p u g acc)
    (if (eq? u ())
        acc                                  ; type declares nothing
        (%image-units p g acc 0 (%image-count-of p u) (image-unit-labels-mask u) (image-unit-labels-desc (image-unit-labels-count u))))))
(def %image-units
  (fn (_ p g acc i n m d)
    (if (eq? i n)
        acc
        (%image-units p g (g (image-unit-label m i d) (image-word-at p i) acc) (image-int+ i 1) n m d))))


; How a type word is tagged.  Three of the four are not heap types at all --
; nil-typed, the static ATOM sentinel, the structural PAIR sentinel -- and none
; of those carries a navigable type pointer, so every consumer branches here
; before dereferencing one.
(def %image-t-nil 0)
(def %image-t-atom 1)
(def %image-t-pair 2)
(doc (def image-type-heap 3)
  "What image-type-label answers for a heap type, the one label whose type word is a pointer to follow.")
(doc (def image-type-label
  (fn (_ tw)
    (if (eq? tw 0) %image-t-nil
      (if (eq? tw %reflect-satom-tw) %image-t-atom
        (if (eq? tw %reflect-spair-tw) %image-t-pair image-type-heap)))))
  (param tw INTEGER "A type word")
  (returns INTEGER "0 nil-typed, 1 the static atom, 2 the structural pair, 3 a heap type")
  "How a type word is tagged.")

(doc (provide x/tool/image/walk
  image-walk image-walk-all image-walk-collect! image-walk-collect?
  image-over-units image-word-at image-traced? image-trace-flag
  image-collect image-heap-count image-mark! image-clear!
  image-unit-labels-static? image-unit-labels-count image-unit-labels-mask image-unit-labels-desc
  image-unit-label image-type-label image-type-heap
  image-heap-off image-flags-off image-type-off
  image-obj->ptr image-ptr->obj image-int->ptr
  image-ref-word image-set-word! image-ptr->str image-byte-len
  image-int+ image-int- image-int* image-int& image-int>> image-int<)
  "The heap walk and the unit reader of the state-image tools.")

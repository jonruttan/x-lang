; iter.x -- Iterator protocol, as the Iter class.
;
; One of the three iteration tiers -- Seq defines encodings, Iter drives
; sequences, Gen composes lazy pipelines; the full statement lives in
; x/protocol/seq.x's header (#365).
;
; Build:   (Iter new seq)  or  (Iter make step state)
; Drive:   (Iter next it)      (Iter empty? it)      (Iter step it)
; Consume: (Iter ->list it)    (Iter for-each f it)    (Iter fold f acc it)
;
; An iterator is a boxed GENERATOR: [step . state].  Steps are PURE -- an
; x-lang step is (step state) -> (value . next-state), or () when exhausted;
; the C driver behind (Iter next) owns the box write-back.  A nil state marks
; exhaustion.  (Iter step it) is the functional door: (value . next-iterator)
; with the source untouched -- the generator view Gen pipelines drive.

(import x/core/list)
; Fetch the type-system helpers from the catalog (registered by sys/type.x).
(def %type-by-atom (prim-ref (lit type) (lit by-atom)))
(def %type-push-iter (prim-ref (lit type) (lit push-iter)))

(import x/type/class)
(import x/type/vector)

; The C iter prims, captured from the catalog (the `iter` namespace is
; de-registered, so they have no bare names).  Applicative -- the methods call
; them with their param symbols, a single eval.
(def %i-make   (prim-ref (lit iter) (lit make)))
(def %i-next   (prim-ref (lit iter) (lit next)))
(def %i-step   (prim-ref (lit iter) (lit step)))
(def %i-empty? (prim-ref (lit iter) (lit empty?)))
(def %i-new    (prim-ref (lit iter) (lit new)))
; Fetch the type prims from the catalog (ns `type` is de-registered, R5).
(def %type-of (prim-ref (lit type) (lit of)))
(def %type? (prim-ref (lit type) (lit ?)))
; The ITER type handle, for iter?: type-of a degenerate iterator.
(def %iter (%type-of (%i-make () ())))

; The opaque form: ITER registers LAZILY (that %i-make above is the first
; iterator ever made), so boot/printer.x's "#<iter>" push no-oped -- the
; type didn't exist yet.  The module that registers the type owns its
; rendering (char-io's pattern); without this push instances render as the
; bounded #<obj:ITER> fallback.
(def %type-push-write (prim-ref (lit type) (lit push-write)))
(def %type-by-atom (prim-ref (lit type) (lit by-atom)))
(%type-push-write (%type-by-atom %iter) (fn (_ o) (display "#<iter>")))


; List step (PURE): the state is the remaining list; yields (head . rest).
; Steps never mutate -- the C driver owns the box write-back.
(def %list-iter-step
  (fn (self st)
    (if (null? st) () (pair (first st) (rest st)))))

(def-class Iter ()
  (static
    (method make (self (param step CALLABLE "Pure step: (step state) -> (value . next-state); a NIL next-state ends the iteration after that value, and a nil state must answer ()")
                       (param state ANY "Initial state; nil marks an already-exhausted iterator"))
      (doc "Build an iterator from a pure step function and its starting state -- the from-scratch constructor; (Iter new) is the from-a-sequence door. Exhaustion rides the STATE: the step signals the last element by returning a nil next-state (the list step below is the model)."
        (returns ITER "A fresh iterator")
        (example "(Iter ->list (Iter make (fn (_ st) (if (null? st) () (pair (first st) (rest st)))) (list 1 2 3)))" "(1 2 3)"))
      (%i-make step state))
    (method next (self (param it ITER "Iterator to advance"))
      (doc "The next element, ADVANCING the iterator in place (the C driver writes the successor state back into the box); () once exhausted. (Iter step) is the functional sibling that leaves it untouched."
        (returns ANY "The next element, or nil when exhausted"))
      (%i-next it))
    (method step   (self it)
      (doc "Step ITERATOR functionally: (value . next-iterator) leaving it untouched, or () when exhausted -- the generator view of an iterator."
        (param it ITER "Iterator") (returns ANY "Pair of value and successor iterator, or nil"))
      (%i-step it))
    (method empty? (self (param it ITER "Iterator to test"))
      (doc "Is the iterator exhausted? True once next would return nil; the source is not advanced."
        (returns BOOL "True when nothing remains"))
      (%i-empty? it))
    (method iter? (self (param x ANY "Value to test"))
      (doc "Test whether a value is an iterator."
        (returns BOOL "True if x is an iterator"))
      (%type? x %iter))
    ; nil has no type for the prim to dispatch on, so shadow it to an empty
    ; iterator; everything else uses the prim's per-type slot dispatch.
    (method new (self (param x ANY "A sequence: list, vector, string, or def-class instance; nil gives an empty iterator"))
      (doc "An iterator over a sequence, via the type's iter slot. Instances yield their members as (name . value) pairs; also available bare as `iter`."
        (returns ITER "An iterator positioned at the first element")
        (example "(Iter ->list (Iter new (list 1 2)))" "(1 2)"))
      (if (null? x) (%i-make %list-iter-step ()) (%i-new x)))
    (method ->list (self (param it ITER "Iterator to drain"))
      (doc "Drain the iterator into a list, in order; the iterator ends exhausted."
        (returns LIST "Every remaining element")
        (example "(Iter ->list (Iter new \"ab\"))" "(#\\a #\\b)"))
      ; Tail accumulate + %rev-onto (boot's, list.x): (pair h (drain it))
      ; recursed in argument position -- one C eval frame group per
      ; element, a segfault at ~16K.  it rides through unchanged like the
      ; fold/for-each loops below (the C driver advances it in place).
      (let drain ((it it) (acc ()))
        (if (%i-empty? it) (%rev-onto acc ())
          (drain it (pair (%i-next it) acc)))))
    (method for-each (self (param f CALLABLE "One-argument fn, called per element for effect")
                           (param it ITER "Iterator to drain"))
      (doc "Drain the iterator applying f to each element for effect; returns nil."
        (returns ANY "nil"))
      (let loop ((it it))
        (if (%i-empty? it) () (do (f (%i-next it)) (loop it)))))
    (method fold (self (param f CALLABLE "Two-argument fn: (f acc element) -> next acc")
                       (param acc ANY "Initial accumulator")
                       (param it ITER "Iterator to drain"))
      (doc "Drain the iterator folding f over the elements, left to right."
        (returns ANY "The final accumulator")
        (example "(Iter fold + 0 (Iter new (list 1 2 3)))" "6"))
      (let loop ((acc acc) (it it))
        (if (%i-empty? it) acc (loop (f acc (%i-next it)) it))))))

; iter: the foundational iterator constructor. A TYPE constructor, so a bare
; global like `list` -- (Iter new x) is the same thing homed on the class, and
; the sequence classes carry an `iter` method that delegates here too.
(def iter (fn (_ x) (Iter new x)))

; Make iterators value-callable, so they read fluently as objects:
;   (it next)   ((grid each-cell) for-each f)   (it ->list)   (it fold f acc)
; Subject-last dispatch (as for Str8/Vector/Num) puts the iterator in the
; trailing `it` parameter -- exactly the shape every Iter consumer already has,
; so (it for-each f) routes to (Iter for-each f it).
(def %type-push-call (prim-ref (lit type) (lit push-call)))
(%type-push-call (%type-by-atom %iter) (%class-call-handler Iter))

; --- Per-type iterator constructors (the values pushed onto the iter slot) ---

(def %list-iter (fn (_ lst) (Iter make %list-iter-step lst)))

; Index-based (vectors etc.): state is (seq . index); the PURE step yields
; (element . next-state), with a nil successor once index reaches len so
; (Iter empty?) turns true.
(def %index-iter
  (fn (_ seq len ref)
    (Iter make
      (fn (self st)
        (if (null? st) ()
          (pair (ref (first st) (rest st))
            (if (< (+ (rest st) 1) len) (pair (first st) (+ (rest st) 1)) ()))))
      (if (eq? len 0) () (pair seq 0)))))

(def %vector-iter (fn (_ v) (%index-iter v (Vector length v) (fn (_ vv ii) (Vector ref ii vv)))))
(def %str-iter (fn (_ s) (%list-iter (%str->list s))))

; --- Wire the iter slot on each sequence type ------------------------------

(%type-push-iter (%type-by-atom (%type-of (list 1))) %list-iter)
(%type-push-iter (%type-by-atom (%type-of (Vector of 1))) %vector-iter)
(%type-push-iter (%type-by-atom (%type-of "x")) %str-iter)
; def-class instances (all share the %object type): iterate the member alist as
; (name . value) pairs.  %object / %obj-fields are object.x internals.
(def %object-iter (fn (_ inst) (%list-iter (%obj-fields inst))))
(%type-push-iter (%type-by-atom %object) %object-iter)


; --- Block forms ------------------------------------------------------------
; ((v iter) for-each (x i) ...) alongside (Iter for-each f it); x/type/block.x.
(import x/type/block)
(Block method! Iter (lit for-each))
(Block method! Iter (lit fold) (lit fold) 2)

(doc (provide x/type/iter Iter iter)
  (note "(Iter new seq) iterates lists, vectors, strings, and def-class instances")
  (note "(instances yield (name . value) pairs); empty sequences give an empty iterator.")
  (example "(Iter ->list (Iter new (Vector of 1 2 3)))" "(1 2 3)")
  "Iterator protocol as the Iter class: build/new/make, drive next/empty?, consume ->list/for-each/fold.")

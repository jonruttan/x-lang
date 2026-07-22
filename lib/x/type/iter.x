; iter.x -- Iterator protocol, as the Iter class.
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
; tree didn't exist yet.  The module that registers the type owns its
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
    (method make   (self step state) (%i-make step state))
    (method next   (self it)         (%i-next it))
    (method step   (self it)
      (doc "Step ITERATOR functionally: (value . next-iterator) leaving it untouched, or () when exhausted -- the generator view of an iterator."
        (param it ITER "Iterator") (returns ANY "Pair of value and successor iterator, or nil"))
      (%i-step it))
    (method empty? (self it)         (%i-empty? it))
    (method iter? (self (param x ANY "Value to test"))
      (doc "Test whether a value is an iterator."
        (returns BOOL "True if x is an iterator"))
      (%type? x %iter))
    ; nil has no type for the prim to dispatch on, so shadow it to an empty
    ; iterator; everything else uses the prim's per-type slot dispatch.
    (method new    (self x)
      (if (null? x) (%i-make %list-iter-step ()) (%i-new x)))
    (method ->list (self it)
      (let drain ((it it))
        (if (%i-empty? it) () (let ((h (%i-next it))) (pair h (drain it))))))
    (method for-each (self f it)
      (let loop ((it it))
        (if (%i-empty? it) () (do (f (%i-next it)) (loop it)))))
    (method fold   (self f acc it)
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

(doc (provide x/type/iter Iter iter)
  (note "(Iter new seq) iterates lists, vectors, strings, and def-class instances")
  (note "(instances yield (name . value) pairs); empty sequences give an empty iterator.")
  (example "(Iter ->list (Iter new (Vector of 1 2 3)))" "(1 2 3)")
  "Iterator protocol as the Iter class: build/new/make, drive next/empty?, consume ->list/for-each/fold.")

; iter.x -- Iterator protocol, as the Iter class.
;
; Build:   (Iter new seq)  or  (Iter make step state)
; Drive:   (Iter next it)      (Iter empty? it)
; Consume: (Iter ->list it)    (Iter for-each f it)    (Iter fold f acc it)
;
; An iterator is [step . state]: (Iter next it) calls (step it), which yields the
; current item and advances the state; a nil state marks exhaustion.

(import x/core/list)
; Fetch the type-system helpers from the catalog (registered by sys/type.x).
(def %type-by-atom (prim-ref (lit type) (lit by-atom)))
(def %type-push-iter (prim-ref (lit type) (lit push-iter)))

(import x/type/object)
(import x/type/vector)

; The C iter prims, captured from the catalog (the `iter` namespace is
; de-registered, so they have no bare names).  Applicative -- the methods call
; them with their param symbols, a single eval.
(def %i-make   (prim-ref (lit iter) (lit make)))
(def %i-next   (prim-ref (lit iter) (lit next)))
(def %i-empty? (prim-ref (lit iter) (lit empty?)))
(def %i-new    (prim-ref (lit iter) (lit new)))

; List step: the state cell IS the remaining list; step reads the head and
; advances by mutating the iterator's own rest (the original list is untouched).
(def %list-iter-step
  (fn (self it)
    (if (null? (rest it))
      ()
      (let ((head (first (rest it))))
        (set-rest! it (rest (rest it)))
        head))))

(def-class Iter ()
  (static
    (method make   (self step state) (%i-make step state))
    (method next   (self it)         (%i-next it))
    (method empty? (self it)         (%i-empty? it))
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

; --- Per-type iterator constructors (the values pushed onto the iter slot) ---

(def %list-iter (fn (_ lst) (Iter make %list-iter-step lst)))

; Index-based (vectors etc.): state is (seq . index); step reads (ref seq index),
; advances, and nils the state once index reaches len so (Iter empty?) turns true.
(def %index-iter
  (fn (_ seq len ref)
    (Iter make
      (fn (self it)
        (let ((st (rest it)))
          (let ((i (rest st)))
            (set-rest! it (if (< (+ i 1) len) (pair (first st) (+ i 1)) ()))
            (ref (first st) i))))
      (if (eq? len 0) () (pair seq 0)))))

(def %vector-iter (fn (_ v) (%index-iter v (Vector length v) (fn (_ vv ii) (Vector ref vv ii)))))
(def %str-iter (fn (_ s) (%list-iter (str->list s))))

; --- Wire the iter slot on each sequence type ------------------------------

(%type-push-iter (%type-by-atom (type-of (list 1))) %list-iter)
(%type-push-iter (%type-by-atom (type-of (Vector of 1))) %vector-iter)
(%type-push-iter (%type-by-atom (type-of "x")) %str-iter)
; def-class instances (all share the %object type): iterate the member alist as
; (name . value) pairs.  %object / %obj-fields are object.x internals.
(def %object-iter (fn (_ inst) (%list-iter (%obj-fields inst))))
(%type-push-iter (%type-by-atom %object) %object-iter)

(doc (provide x/type/iter Iter)
  (note "(Iter new seq) iterates lists, vectors, strings, and def-class instances")
  (note "(instances yield (name . value) pairs); empty sequences give an empty iterator.")
  (example "(Iter ->list (Iter new (Vector of 1 2 3)))" "(1 2 3)")
  "Iterator protocol as the Iter class: build/new/make, drive next/empty?, consume ->list/for-each/fold.")

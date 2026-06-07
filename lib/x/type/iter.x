; iter.x -- Iterator protocol: make built-in sequences iterable, plus consumers.
;
; ITER drivers are C prims in the de-registered `iter` namespace, used via the
; Iter class.  An iterator is [step-fn . state]: (Iter next it) calls (step-fn it),
; which yields the current item and advances the state; a nil state ends it.

(import x/core/list)
(import x/type/object)

; The C iter prims, captured from the catalog (the `iter` namespace is
; de-registered, so they have no bare names).  They are applicative, so the
; class methods below call them directly with their (already-bound) params.
(def %i-make   (prim-ref (lit iter) (lit make)))
(def %i-next   (prim-ref (lit iter) (lit next)))
(def %i-empty? (prim-ref (lit iter) (lit empty?)))
(def %i-new    (prim-ref (lit iter) (lit new)))

; Iter -- the iterator protocol's class.  Its static methods are the x-layer
; entry points; each just hands its evaluated args to the matching C prim.
(def-class Iter ()
  (static
    (method make   (self step state) (%i-make step state))
    (method next   (self it)         (%i-next it))
    (method empty? (self it)         (%i-empty? it))
    (method new    (self x)          (%i-new x))))

; --- Per-type iterator constructors (the values pushed onto the iter slot) ---

; List: the state cell IS the remaining list; step reads the head, advances the
; cursor by mutating the iterator's own rest (the original list is untouched).
(def %list-iter-step
  (fn (self it)
    (if (null? (rest it))
      ()
      (let ((head (first (rest it))))
        (set-rest! it (rest (rest it)))
        head))))
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

(def %vector-iter (fn (_ v) (%index-iter v (vector-length v) vector-ref)))

; Strings iterate by code point (UTF-8 aware) via str->list, then a list iter.
(def %str-iter (fn (_ s) (%list-iter (str->list s))))

; --- Wire the iter slot on each sequence type ------------------------------

(type-push-iter (type-by-atom (type-of (list 1))) %list-iter)
(type-push-iter (type-by-atom (type-of (vector 1))) %vector-iter)
(type-push-iter (type-by-atom (type-of "x")) %str-iter)

; def-class instances (all share the %object type): iterate the member alist as
; (name . value) pairs.  %object / %obj-fields are object.x internals.
(def %object-iter (fn (_ inst) (%list-iter (%obj-fields inst))))
(type-push-iter (type-by-atom %object) %object-iter)

; The empty list is nil, which has no type for the iter prim to dispatch on
; (it would deref a null type).  Shadow iter so (iter ()) yields an empty
; iterator; everything else delegates to (Iter new)'s slot dispatch.
(def iter
  (fn (_ x)
    (if (null? x)
      (Iter make %list-iter-step ())
      (Iter new x))))

; --- Consumers -------------------------------------------------------------

(doc (def iter->list
  (fn (self (param it ANY "An iterator"))
    (if (Iter empty? it)
      ()
      (let ((head (Iter next it))) (pair head (self it))))))
  (returns LIST "All remaining elements, in order")
  (example "(iter->list (iter (list 1 2 3)))" "(1 2 3)")
  "Drain an iterator into a list.")

(doc (def iter-for-each
  (fn (self (param f CALLABLE "Applied to each element")
       (param it ANY "An iterator"))
    (if (Iter empty? it)
      ()
      (do (f (Iter next it)) (self f it)))))
  (returns ANY "nil")
  "Apply a function to each remaining element of an iterator, for side effects.")

(doc (def iter-fold
  (fn (self (param f CALLABLE "Combining fn: (acc el) -> acc")
       (param acc ANY "Initial accumulator")
       (param it ANY "An iterator"))
    (if (Iter empty? it)
      acc
      (self f (f acc (Iter next it)) it))))
  (returns ANY "Final accumulator")
  (example "(iter-fold + 0 (iter (list 1 2 3 4)))" "10")
  "Left-fold over the remaining elements of an iterator.")

(doc (provide x/type/iter
  iter iter->list iter-for-each iter-fold)
  (note "(iter seq) works for lists, vectors, strings, and def-class instances")
  (note "(those yield (name . value) pairs); empty sequences give an empty iterator.")
  (note "Low-level protocol is the Iter class: (Iter make step state), (Iter next it), (Iter empty? it).")
  (example "(iter->list (iter (vector 1 2 3)))" "(1 2 3)")
  "Iterator protocol: build an iterator with (iter seq) or (Iter make ...), drive it with (Iter next)/(Iter empty?), and consume it with iter->list / iter-for-each / iter-fold.")

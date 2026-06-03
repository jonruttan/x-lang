; iter.x -- Iterator protocol: make built-in sequences iterable, plus consumers.
;
; The ITER type and its drivers -- make-iter, iter-next, iter-empty? -- are C
; primitives.  An iterator is [step-fn . state]: iter-next calls (step-fn iter),
; which reads the current item out of the state, advances it, and returns the
; item; the state going nil marks exhaustion (iter-empty?).  Here we wire the
; `iter` type slot for the built-in sequence types so (iter seq) yields an
; iterator, and add a few consumers.

(import x/core/list)
(import x/type/object)

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
(def %list-iter (fn (_ lst) (make-iter %list-iter-step lst)))

; Index-based (vectors etc.): state is (seq . index); step reads (ref seq index),
; advances, and nils the state once index reaches len so iter-empty? turns true.
(def %index-iter
  (fn (_ seq len ref)
    (make-iter
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

; The empty list is nil, which has no type for the C iter prim to dispatch on
; (it would deref a null type).  Shadow iter so (iter ()) yields an empty
; iterator; everything else delegates to the C prim's slot dispatch.
(def %c-iter iter)
(def iter
  (fn (_ x)
    (if (null? x)
      (make-iter %list-iter-step ())
      (%c-iter x))))

; --- Consumers -------------------------------------------------------------

(doc (def iter->list
  (fn (self (param it ANY "An iterator"))
    (if (iter-empty? it)
      ()
      (let ((head (iter-next it))) (pair head (self it))))))
  (returns LIST "All remaining elements, in order")
  (example "(iter->list (iter (list 1 2 3)))" "(1 2 3)")
  "Drain an iterator into a list.")

(doc (def iter-for-each
  (fn (self (param f CALLABLE "Applied to each element")
       (param it ANY "An iterator"))
    (if (iter-empty? it)
      ()
      (do (f (iter-next it)) (self f it)))))
  (returns ANY "nil")
  "Apply a function to each remaining element of an iterator, for side effects.")

(doc (def iter-fold
  (fn (self (param f CALLABLE "Combining fn: (acc el) -> acc")
       (param acc ANY "Initial accumulator")
       (param it ANY "An iterator"))
    (if (iter-empty? it)
      acc
      (self f (f acc (iter-next it)) it))))
  (returns ANY "Final accumulator")
  (example "(iter-fold + 0 (iter (list 1 2 3 4)))" "10")
  "Left-fold over the remaining elements of an iterator.")

(doc (provide x/type/iter
  iter make-iter iter-next iter-empty?
  iter->list iter-for-each iter-fold)
  (note "(iter seq) works for lists, vectors, strings, and def-class instances")
  (note "(those yield (name . value) pairs); empty sequences give an empty iterator.")
  (example "(iter->list (iter (vector 1 2 3)))" "(1 2 3)")
  "Iterator protocol: build an iterator with (iter seq) or make-iter, drive it with iter-next / iter-empty?, and consume it with iter->list / iter-for-each / iter-fold.")

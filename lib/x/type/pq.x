; type/pq.x -- Pq: a binary-heap priority queue (#375).
;
; Comparator-ordered: (Pq make cmp) with (cmp a b) -> #t when a comes
; strictly first -- the List sort contract, so (fn (_ a b) (< a b)) makes
; a min-queue and (>) a max-queue. Backed by an Array (amortized O(1)
; push!, O(1) ref/set!); push!/pop! are O(log n), peek O(1).
;
; The NAME: this is the heap data structure, but `Heap` is the GC class
; (x/sys/gc) -- the queue is named for what callers use it as.
;
; Zero top-level %-globals (new-file budget 0).

(import x/type/class)
(import x/type/array)

(def-class Pq ()
  (doc "A binary-heap priority queue over a comparator: push!/pop! O(log n), peek O(1). (cmp a b) -> #t when a comes strictly first (the List sort contract)."
    (example "(let ((q (Pq make (fn (_ a b) (< a b))))) (q push! 3) (q push! 1) (q push! 2) (q pop!))" "1")
    (see push!) (see pop!))

  store  ; the backing Array; slot 0 is the front
  cmp    ; (cmp a b) -> #t when a sorts strictly first

  (static
    (method make (self (param cmp CALLABLE "Comparison: (cmp a b) -> #t when a comes strictly first"))
      (doc "An empty priority queue ordered by cmp."
        (returns Pq "A new empty queue")
        (example "((Pq make (fn (_ a b) (< a b))) length)" "0"))
      (new-from self (list 'store (Array make) 'cmp cmp))))

  ; --- the sift halves (private; both ride the backing array in place) ---
  (method %sift-up! (self i)
    (let ((st (member 'store)) (cmp (member 'cmp)))
      (let up ((i i))
        (if (= i 0) ()
          (let ((p (/ (- i 1) 2)))
            (if (cmp (st ref i) (st ref p))
              (let ((tmp (st ref p)))
                (st set! p (st ref i))
                (st set! i tmp)
                (up p))
              ()))))))

  (method %sift-down! (self i)
    (let ((st (member 'store)) (cmp (member 'cmp)))
      (let ((n (st length)))
        (let down ((i i))
          (let ((l (+ (* 2 i) 1)) (r (+ (* 2 i) 2)))
            (let ((best (if (if (< l n) (cmp (st ref l) (st ref i)) #f) l i)))
              (let ((best (if (if (< r n) (cmp (st ref r) (st ref best)) #f) r best)))
                (if (= best i) ()
                  (let ((tmp (st ref best)))
                    (st set! best (st ref i))
                    (st set! i tmp)
                    (down best))))))))))

  ; --- public API ---
  (method push! (self (param v ANY "Value to enqueue"))
    (doc "Enqueue a value: O(log n). Returns the queue for chaining."
      (returns Pq "self"))
    ((member 'store) push! v)
    (self %sift-up! (- ((member 'store) length) 1))
    self)

  (method peek (self)
    (doc "The front value (the one pop! would return), without removing it; raises kind-'value when empty."
      (returns ANY "The front value"))
    (if (= ((member 'store) length) 0)
      (Err raise 'value "Pq peek: empty" ())
      ((member 'store) ref 0)))

  (method pop! (self)
    (doc "Remove and return the front value: O(log n); raises kind-'value when empty."
      (returns ANY "The front value")
      (example "(let ((q (Pq make (fn (_ a b) (< a b))))) (q push! 9) (q push! 4) (list (q pop!) (q pop!)))" "(4 9)"))
    (let ((st (member 'store)))
      (let ((n (st length)))
        (match
          ((= n 0) (Err raise 'value "Pq pop!: empty" ()))
          ((= n 1) (st pop!))
          (#t
            (let ((front (st ref 0)))
              (st set! 0 (st pop!))
              (self %sift-down! 0)
              front))))))

  (method length (self)
    (doc "How many values are queued."
      (returns INT "The count"))
    ((member 'store) length))

  (method empty? (self)
    (doc "Is the queue empty?"
      (returns BOOL "#t when nothing is queued"))
    (= ((member 'store) length) 0)))

(doc (provide x/type/pq Pq)
  (note "The heap structure under the queue name -- Heap is the GC class. Comparator contract matches List sort: (cmp a b) -> #t when a comes strictly first.")
  "A binary-heap priority queue, homed on the Pq class.")

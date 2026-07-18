; array.x -- Array: the growable container over a vector backing store.
;
; The VECTOR is the fundamental fixed-size shape (the atom is its 1-slot
; case, the pair its 2-slot case); an Array is NOT a vector -- it is a
; stateful container (Dict/Set tier: instance dispatch) that wraps a backing
; vector, doubling it on overflow, plus a live length. The stdlib itself
; wanted this -- random.x's shuffle was O(n^2) "because there is no
; vector-set!".

(import x/type/object)
(import x/type/vector)
(import x/type/list)

; Fetch the raw slot prims (ns `obj` is de-registered, R5). Slot 0 of the
; backing vector is its capacity; elements live in slots 1..len.
(def %arr-obj-ref (prim-ref 'obj 'ref))
(def %arr-obj-set! (prim-ref 'obj 'set!))

(def-class Array ()
  (doc "A growable container: amortized O(1) push!, O(1) ref/set!, backed by a doubling VECTOR."
    (note "Mutators (push!/set!) return the array for chaining; pop! returns the removed element.")
    (example "(let ((a (Array make))) (a push! 1) (a push! 2) (a ->list))" "(1 2)")
    (see push!) (see ref))

  store  ; backing VECTOR (slot 0 = capacity)
  len    ; live element count (<= capacity)

  (static
    (method make (self . opt)
      (doc "An empty array. Pass a capacity to pre-size the backing store."
        (param opt LIST "Optional (capacity) -- initial backing size, default 8")
        (returns Array "A new empty array"))
      (def c (if (pair? opt) (first opt) 8))
      (new-from self (list 'store (Vector make c ()) 'len 0)))

    (method new (self . opt)
      (doc "Alias for make: (Array new) is (Array make) -- the generic instance allocator would build an unusable array."
        (param opt LIST "Optional (capacity), as for make")
        (returns Array "A new empty array"))
      (if (pair? opt) (self make (first opt)) (self make)))

    (method from-list (self (param lst LIST "Elements, in order"))
      (doc "Build an array from a list's elements."
        (returns Array "An array holding the list's elements")
        (example "((Array from-list (list 1 2 3)) length)" "3"))
      (def a (self make))
      (List for-each (fn (_ x) (a push! x)) lst)
      a)

    (method of (self . (param args ANY "Elements, in order"))
      (doc "Variadic literal: an array of the arguments."
        (returns Array "An array holding the arguments")
        (example "((Array of 1 2 3) ->list)" "(1 2 3)"))
      (self from-list args)))

  ; Normalize an index (negative counts from the end) and bounds-check it.
  ; N5: coerces to INT via vector.x's %vec->int (loads before us); the probe
  ; is inlined so the dynamic message is only built on the slow path.
  (method %index (self i what)
    (def i2 (if (if (null? i) #f (eq? (%vec-type-of i) %vec-int-type)) i
      (%vec->int i (Str8 append what ": index not convertible to INT"))))
    (def j (if (< i2 0) (+ (member 'len) i2) i2))
    (if (< j 0) (error (Str8 append what ": index out of range"))
      (if (< j (member 'len)) j
        (error (Str8 append what ": index out of range")))))

  (method push! (self x)
    (doc "Append an element (doubling the backing store when full); returns the array for chaining."
      (param x ANY "Element to append")
      (returns Array "self"))
    (def n (member 'len))
    (if (= n (%arr-obj-ref (member 'store) 0))
      (let ((bigger (Vector make (* 2 (%arr-obj-ref (member 'store) 0)) ())))
        (do (let go ((i 1))
              (if (> i n) ()
                (do (%arr-obj-set! bigger i (%arr-obj-ref (member 'store) i))
                    (go (+ i 1)))))
            (set-member! 'store bigger)))
      ())
    (%arr-obj-set! (member 'store) (+ n 1) x)
    (set-member! 'len (+ n 1))
    self)

  (method pop! (self)
    (doc "Remove and return the last element; errors when empty."
      (returns ANY "The removed element"))
    (def n (member 'len))
    (if (= n 0) (error "Array pop!: empty")
      (let ((x (%arr-obj-ref (member 'store) n)))
        (do (%arr-obj-set! (member 'store) n ())   ; drop the reference
            (set-member! 'len (- n 1))
            x))))

  (method ref (self i)
    (doc "The element at index i (negative counts from the end); errors out of range."
      (param i INT "Zero-based index")
      (returns ANY "Element at i"))
    (%arr-obj-ref (member 'store) (+ 1 (self %index i "Array ref"))))

  (method set! (self i x)
    (doc "Store x at index i (in place; negative counts from the end); errors out of range; returns the array for chaining."
      (param i INT "Zero-based index")
      (param x ANY "Value to store")
      (returns Array "self"))
    (%arr-obj-set! (member 'store) (+ 1 (self %index i "Array set!")) x)
    self)

  (method length (self)
    (doc "The live element count." (returns INT "Element count"))
    (member 'len))

  (method empty? (self)
    (doc "Test whether the array holds no elements." (returns BOOL "#t when empty"))
    (= 0 (member 'len)))

  (method ->list (self)
    (doc "The elements as a list, in order." (returns LIST "List of elements"))
    (let go ((i (member 'len)) (acc ()))
      (if (= i 0) acc
        (go (- i 1) (pair (%arr-obj-ref (member 'store) i) acc))))))

(doc (provide x/type/array Array)
  (note "Backing VECTOR doubles on overflow; slot 0 of the backing store is its capacity.")
  (example "((Array from-list (list 1 2)) pop!)" "2")
  "Array: the growable container -- amortized O(1) push!, O(1) indexed access, over a vector backing store.")

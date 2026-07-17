; vec.x -- Vec: a growable vector (amortized O(1) push!).
;
; The mutable, resizable sibling of the fixed-size VECTOR: a backing vector
; (doubled when full) plus a live length. The stdlib itself wanted this --
; random.x's shuffle was O(n^2) "because there is no vector-set!".

(import x/type/object)
(import x/type/vector)
(import x/type/list)

; Fetch the raw slot prims (ns `obj` is de-registered, R5). Slot 0 of the
; backing vector is its capacity; elements live in slots 1..len.
(def %vec-obj-ref (prim-ref (lit obj) (lit ref)))
(def %vec-obj-set! (prim-ref (lit obj) (lit set!)))

(def-class Vec ()
  (doc "A growable vector: amortized O(1) push!, O(1) ref/set!, backed by a doubling VECTOR."
    (note "Mutators (push!/set!) return the vec for chaining; pop! returns the removed element.")
    (example "(let ((v (Vec make))) (v push! 1) (v push! 2) (v ->list))" "(1 2)")
    (see push!) (see ref))

  store  ; backing VECTOR (slot 0 = capacity)
  len    ; live element count (<= capacity)

  (static
    (method make (self . opt)
      (doc "An empty vec. Pass a capacity to pre-size the backing store."
        (param opt LIST "Optional (capacity) -- initial backing size, default 8")
        (returns Vec "A new empty vec"))
      (def c (if (pair? opt) (first opt) 8))
      (new-from self (list 'store (Vector make c ()) 'len 0)))

    (method from-list (self (param lst LIST "Elements, in order"))
      (doc "Build a vec from a list's elements."
        (returns Vec "A vec holding the list's elements")
        (example "((Vec from-list (list 1 2 3)) length)" "3"))
      (def v (self make))
      (List for-each (fn (_ x) (v push! x)) lst)
      v))

  ; Normalize an index (negative counts from the end) and bounds-check it.
  (method %index (self i what)
    (def j (if (< i 0) (+ (member 'len) i) i))
    (if (< j 0) (error (Str8 append what ": index out of range"))
      (if (< j (member 'len)) j
        (error (Str8 append what ": index out of range")))))

  (method push! (self x)
    (doc "Append an element (doubling the backing store when full); returns the vec for chaining."
      (param x ANY "Element to append")
      (returns Vec "self"))
    (def n (member 'len))
    (if (= n (%vec-obj-ref (member 'store) 0))
      (let ((bigger (Vector make (* 2 (%vec-obj-ref (member 'store) 0)) ())))
        (do (let go ((i 1))
              (if (> i n) ()
                (do (%vec-obj-set! bigger i (%vec-obj-ref (member 'store) i))
                    (go (+ i 1)))))
            (set-member! 'store bigger)))
      ())
    (%vec-obj-set! (member 'store) (+ n 1) x)
    (set-member! 'len (+ n 1))
    self)

  (method pop! (self)
    (doc "Remove and return the last element; errors when empty."
      (returns ANY "The removed element"))
    (def n (member 'len))
    (if (= n 0) (error "Vec pop!: empty")
      (let ((x (%vec-obj-ref (member 'store) n)))
        (do (%vec-obj-set! (member 'store) n ())   ; drop the reference
            (set-member! 'len (- n 1))
            x))))

  (method ref (self i)
    (doc "The element at index i (negative counts from the end); errors out of range."
      (param i INT "Zero-based index")
      (returns ANY "Element at i"))
    (%vec-obj-ref (member 'store) (+ 1 (self %index i "Vec ref"))))

  (method set! (self i x)
    (doc "Store x at index i (in place; negative counts from the end); errors out of range; returns the vec for chaining."
      (param i INT "Zero-based index")
      (param x ANY "Value to store")
      (returns Vec "self"))
    (%vec-obj-set! (member 'store) (+ 1 (self %index i "Vec set!")) x)
    self)

  (method length (self)
    (doc "The live element count." (returns INT "Element count"))
    (member 'len))

  (method empty? (self)
    (doc "Test whether the vec holds no elements." (returns BOOL "#t when empty"))
    (= 0 (member 'len)))

  (method ->list (self)
    (doc "The elements as a list, in order." (returns LIST "List of elements"))
    (let go ((i (member 'len)) (acc ()))
      (if (= i 0) acc
        (go (- i 1) (pair (%vec-obj-ref (member 'store) i) acc))))))

(doc (provide x/type/vec Vec)
  (note "Backing VECTOR doubles on overflow; slot 0 of the backing store is its capacity.")
  (example "((Vec from-list (list 1 2)) pop!)" "2")
  "Vec: the growable vector -- amortized O(1) push!, O(1) indexed access.")

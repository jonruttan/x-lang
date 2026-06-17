; vector.x -- Vector type (#() reader) + the Vector class for its operations.
;
; The %vector TYPE machinery (reader/write/iter/call slots) is type infrastructure
; and stays as module-level defs. The 7 public operations are homed on the Vector
; class. Loads after object.x (relocated in x-core.x) so def-class is available;
; nothing before object.x uses vectors or #() literals.
(import x/core/list)
; Fetch the raw-object prims from the catalog (ns `obj` is de-registered, R5).
(def %make-obj (prim-ref (lit obj) (lit make)))
(def %obj-ref (prim-ref (lit obj) (lit ref)))
(def %obj-set! (prim-ref (lit obj) (lit set!)))

(import x/type/object)
; Fetch the type prims from the catalog (ns `type` is de-registered, R5).
(def %make-type (prim-ref (lit type) (lit make)))
(def %type-of (prim-ref (lit type) (lit of)))
(def %type? (prim-ref (lit type) (lit ?)))
; Fetch the io plumbing prims from the catalog (ns `io` partly de-registered, R5).
(def %read (prim-ref (lit io) (lit read)))
; Fetch the char/int casts from the catalog (ns `char`/`int` utility members de-registered, R5).
(def %char->integer (prim-ref (lit char) (lit ->int)))



; N+1 slot objects: slot 0 = length, slots 1..N = elements.

; Fill a vector's slots from a list (shared helper)
(def %vector-from-list
  (fn (_ type lst)
    (def len (length lst))
    (def v (%make-obj type (+ len 1)))
    (%obj-set! v 0 len)
    (def go (fn (self l i)
      (if (not (null? l))
        (do (%obj-set! v (+ i 1) (first l)) (self (rest l) (+ i 1))))))
    (go lst 0)
    v))

(def %vector-read ())

(def %vector ())
(set! %vector
  (%make-type
    "VECTOR"
    (list
      (pair
        (lit call)
        (fn (_ self . args)
          (def i (first args))
          (if (< i 0)
            (%obj-ref self (+ (%obj-ref self 0) i 1))
            (%obj-ref self (+ i 1)))))
      (pair
        (lit write)
        (fn (_ self)
          (display "#(")
          (def len (%obj-ref self 0))
          (def write-vec
            (fn (recur i sep)
              (if (< i len)
                (do
                  (if sep (display " "))
                  (write (%obj-ref self (+ i 1)))
                  (recur (+ i 1) #t)))))
          (write-vec 0 #f)
          (display ")")))
      (pair
        (lit analyse)
        (fn (_ buffer score chr)
          (if (= chr (%char->integer #\#))
            (fn (_ buf sc c0)
              (if (= c0 (%char->integer #\())
                (do (buffer-unread buf) (score-set sc 1 buf))
                ()))
            ())))
      (pair (lit read) (fn (_ . args) (%vector-read (first args))))
      (pair
        (lit from)
        (list
          (pair
            (%type-of (pair 1 ()))
            (fn (_ value) (%vector-from-list %vector value)))))
      (pair
        (lit to)
        (list
          (pair (%type-of (pair 1 ()))
            ; Outer param is `v` (not `self`): build's first param is the
            ; auto-bound self (for recursion), so naming the vector `self`
            ; here would shadow it and (%obj-ref self ...) would read the fn.
            (fn (_ v)
              (def len (%obj-ref v 0))
              (def build
                (fn (self i acc)
                  (if (< i 0) acc
                    (self (- i 1) (pair (%obj-ref v (+ i 1)) acc)))))
              (build (- len 1) ())))))
      (pair
        (lit iter)
        (fn (_ self)
          (def len (%obj-ref self 0))
          (def i 0)
          (fn (_ )
            (if (< i len)
              (let ((val (%obj-ref self (+ i 1))))
                (set! i (+ i 1))
                val)
              ())))))))

(set! %vector-read (fn (_ . args) (%vector-from-list %vector (%read))))

(def-class Vector ()
  (static
    ; --- Constructors ---
    (method of (self . args)
      (doc "Create a vector from the given arguments."
        (returns VECTOR "New vector containing the arguments")
        (example "(Vector of 1 2 3)" "#(1 2 3)"))
      (%vector-from-list %vector args))
    (method make (self (param n INT "Number of elements")
                       (param fill ANY "Value to fill each slot with"))
      (doc "Create a vector of length n, with every element set to fill."
        (returns VECTOR "New vector of length n filled with fill"))
      (def v (%make-obj %vector (+ n 1)))
      (%obj-set! v 0 n)
      (def loop
        (fn (self i)
          (if (<= i n)
            (do (%obj-set! v i fill) (self (+ i 1))))))
      (loop 1)
      v)
    ; --- Predicate ---
    (method vector? (self (param x ANY "Value to test"))
      (doc "Test whether a value is a vector." (returns BOOL "True if x is a vector"))
      (%type? x %vector))
    ; --- Access ---
    (method ref (self (param i INT "Zero-based index") (param v VECTOR "Vector"))
      (doc "Return the element at index i of a vector." (returns ANY "Element at index i"))
      (%obj-ref v (+ i 1)))
    (method length (self (param v VECTOR "Vector"))
      (doc "Return the number of elements in a vector." (returns INT "Number of elements"))
      (%obj-ref v 0))
    ; --- Conversion ---
    (method ->list (self (param v VECTOR "Vector to convert"))
      (doc "Convert a vector to a list." (returns LIST "List of the vector's elements"))
      (def len (%obj-ref v 0))
      (def build
        (fn (self i acc)
          (if (< i 0) acc
            (self (- i 1) (pair (%obj-ref v (+ i 1)) acc)))))
      (build (- len 1) ()))
    (method from-list (self (param lst LIST "List to convert"))
      (doc "Convert a list to a vector." (returns VECTOR "New vector containing the list's elements"))
      (%vector-from-list %vector lst))
    (method iter (self (param v VECTOR "Vector to iterate"))
      (doc "An iterator over the vector's elements." (returns ITER "Iterator"))
      (Iter new v))))

; Value dispatch over the existing index call handler. A symbol selector
; dispatches subject-LAST, so (v ref i) -> (Vector ref i v) and (v ->list) work;
; (v i) still indexes via the underlying call. `ref` is data-last ((self i v)),
; matching the library's Ramda data-last convention.
(%bind-call-over! (Type of (Vector of 1)) Vector)

(doc (provide x/type/vector Vector)
  (note "Literal syntax: #(1 2 3), with negative indexing via the vector's call slot.")
  (example "(Vector ref 1 (Vector of 10 20 30))" "20")
  "Fixed-size indexed vectors; operations homed on the Vector class.")

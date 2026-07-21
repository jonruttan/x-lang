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

; N5 (implicit conversion): index seats coerce to INT once at entry; only an
; unconvertible value errors (list.x's %list->int is the pattern).
(def %vec-type-of (prim-ref (lit type) (lit of)))
(def %vec-int-type (%vec-type-of 0))
(def %vec-cvt (prim-ref (lit convert) (lit to)))
(def %vec->int (fn (_ n what)
  (if (if (null? n) #f (eq? (%vec-type-of n) %vec-int-type)) n
    (let ((k (%vec-cvt n %vec-int-type)))
      (if (if (null? k) #f (eq? (%vec-type-of k) %vec-int-type)) k (error what))))))
(def %obj-set! (prim-ref (lit obj) (lit set!)))

(import x/type/class)
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

; Receiver guard for the raw-slot ops. %obj-ref reads slot 0 as the length, so
; a non-vector receiver turns the bounds check ITSELF into a read of arbitrary
; memory -- the type check has to come first for the bounds check to mean
; anything. The class layer is the guard site; the C prims stay unchecked by
; design (see docs/glossary.md "core").
(def %vec-check (fn (_ v what)
  (if (%type? v %vector) v (Err raise (lit type) what ()))))
(set! %vector
  (%make-type
    "VECTOR"
    (list
      (pair
        (lit call)
        (fn (_ self . args)
          ; Bounds-checked like (Vector ref ...): %obj-ref past the object is a
          ; raw memory read, so slot 0's length is the guard for bare (v i) too.
          (def i (%vec->int (first args) "vector: index not convertible to INT"))
          (def len (%obj-ref self 0))
          (def j (if (< i 0) (+ len i) i))
          (if (< j 0) (Err raise (lit index) "vector: index out of range" ())
            (if (< j len) (%obj-ref self (+ j 1))
              (Err raise (lit index) "vector: index out of range" ())))))
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

; GC: vectors are per-instance sized -- the dynamic-units sentinel (-1)
; tells the mark hook to read the payload count from slot 0. Without
; it, vector payloads were NEVER traced: a collect freed the buckets
; out from under any Dict held across a REPL turn (SEGV on next get).
((prim-ref (lit type) (lit set-units!))
  ((prim-ref (lit type) (lit by-atom)) %vector) -1)

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
      ; A negative n built a vector REPORTING length n (#52): every later
      ; bounds check compared against it, so the container lied its whole
      ; life. Cold constructor seat -- the guard is one compare.
      (if (< n 0) (Err raise (lit value) "Vector make: negative length" ()) ())
      (def v (%make-obj %vector (+ n 1)))
      (%obj-set! v 0 n)
      (def loop
        (fn (self i)
          (if (<= i n)
            (do (%obj-set! v i fill) (self (+ i 1))))))
      (loop 1)
      v)
    (method build (self (param n INT "Number of elements")
                        (param f ANY "Index -> element function, called as (f i) for i in [0, n)"))
      (doc "Create a vector of length n where element i is (f i). Built in place -- no intermediate list."
        (returns VECTOR "New vector of length n, element i = (f i)")
        (example "(Vector build 3 (fn (_ i) (* i i)))" "#(0 1 4)"))
      (def v (%make-obj %vector (+ n 1)))
      (%obj-set! v 0 n)
      (def loop
        (fn (self i)
          (if (< i n)
            (do (%obj-set! v (+ i 1) (f i)) (self (+ i 1))))))
      (loop 0)
      v)
    ; --- Predicate ---
    (method vector? (self (param x ANY "Value to test"))
      (doc "Test whether a value is a vector." (returns BOOL "True if x is a vector"))
      (%type? x %vector))
    ; --- Access ---
    (method ref (self (param i INT "Zero-based index; negative counts from the end") (param v VECTOR "Vector"))
      (doc "Return the element at index i of a vector; negative i counts from the end. Errors when i is out of range."
        (returns ANY "Element at index i"))
      ; %obj-ref is a raw slot read (arbitrary memory past the object), so the
      ; length in slot 0 is the x-lang bounds check. Negative normalization
      ; matches the vector's call slot, so (Vector ref -1 v) == (v -1). The
      ; nil guard makes a piped index-search miss fail loudly.
      (def i2 (%vec->int i "Vector ref: index not convertible to INT"))
      (%vec-check v "Vector ref: not a vector")
      (def len (%obj-ref v 0))
      (def j (if (< i2 0) (+ len i2) i2))
      (if (< j 0) (Err raise (lit index) "Vector ref: index out of range" ())
        (if (< j len) (%obj-ref v (+ j 1))
          (Err raise (lit index) "Vector ref: index out of range" ()))))
    (method set! (self (param i INT "Zero-based index; negative counts from the end")
                       (param x ANY "Value to store")
                       (param v VECTOR "Vector"))
      (doc "Store x at index i of a vector (in place); negative i counts from the end. Errors when i is out of range; returns the vector for chaining."
        (returns VECTOR "v")
        (example "(Vector ref 0 (Vector set! 0 99 (Vector of 1 2)))" "99"))
      ; Same guard discipline as ref: slot-0 length is the x-lang bounds
      ; check over the raw %obj-set!, and negatives normalize identically.
      (def i2 (%vec->int i "Vector set!: index not convertible to INT"))
      (%vec-check v "Vector set!: not a vector")
      (def len (%obj-ref v 0))
      (def j (if (< i2 0) (+ len i2) i2))
      (if (< j 0) (Err raise (lit index) "Vector set!: index out of range" ())
        (if (< j len) (do (%obj-set! v (+ j 1) x) v)
          (Err raise (lit index) "Vector set!: index out of range" ()))))
    (method length (self (param v VECTOR "Vector"))
      (doc "Return the number of elements in a vector." (returns INT "Number of elements"))
      (%vec-check v "Vector length: not a vector")
      (%obj-ref v 0))
    ; --- Conversion ---
    (method ->list (self (param v VECTOR "Vector to convert"))
      (doc "Convert a vector to a list." (returns LIST "List of the vector's elements"))
      (%vec-check v "Vector ->list: not a vector")
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

; Install elementwise vector equality on equal?'s extension hook (logic.x's
; %equal-others -- logic loads before this file, so equal? cannot name the
; vector type itself). Chains the previous handler; runs only after equal?'s
; identity check has already failed. %obj-ref direct (not Vector ref): both
; operands are known vectors and i is bounded by the slot-0 length.
(def %vector-equal
  (fn (_ eq a b)
    (def len (%obj-ref a 0))
    (if (= len (%obj-ref b 0))
      (let go ((i 0))
        (if (= i len) #t
          (if (eq (%obj-ref a (+ i 1)) (%obj-ref b (+ i 1)))
            (go (+ i 1)) #f)))
      #f)))
(set-first! %equal-others
  (let ((prev (first %equal-others)))
    (fn (_ eq a b)
      (if (%type? a %vector)
        (if (%type? b %vector) (%vector-equal eq a b) #f)
        (prev eq a b)))))

(doc (provide x/type/vector Vector)
  (note "Literal syntax: #(1 2 3), with negative indexing via the vector's call slot.")
  (example "(Vector ref 1 (Vector of 10 20 30))" "20")
  "Fixed-size indexed vectors; operations homed on the Vector class.")

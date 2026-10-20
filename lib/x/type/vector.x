; vector.x -- Vector type (#() reader) + the Vector class for its operations.
;
; The %vector TYPE machinery (reader/write/iter/call slots) is type infrastructure
; and stays as module-level defs. The 7 public operations are homed on the Vector
; class. Loads after object.x (relocated in x-core.x) so def-class is available;
; nothing before object.x uses vectors or #() literals.
(module x/type/vector)

(import x/core/list)
; Fetch the raw-object prims from the catalogue (ns `obj` is de-registered, R5).
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
; The integer doors, for index and length arithmetic: an index is INT once
; %vec->int has seen it and a length is slot 0's INT, so neither needs the
; tower's dispatch or the operators' nil guards.
(def %vec-int< (prim-ref (lit int) (lit <)))
(def %vec-int= (prim-ref (lit int) (lit =)))
(def %vec-int+ (prim-ref (lit int) (lit +)))
(def %vec-int- (prim-ref (lit int) (lit -)))

(import x/type/class)
; Fetch the type prims from the catalogue (ns `type` is de-registered, R5).
(def %make-type (prim-ref (lit type) (lit make)))
(def %type-of (prim-ref (lit type) (lit of)))
(def %type? (prim-ref (lit type) (lit ?)))
; Fetch the io plumbing prims from the catalogue (ns `io` partly de-registered, R5).
(def %read (prim-ref (lit io) (lit read)))
; Fetch the char/int casts from the catalogue (ns `char`/`int` utility members de-registered, R5).
(def %char->integer (prim-ref (lit char) (lit ->int)))



; N+1 slot objects: slot 0 = length, slots 1..N = elements.

; Fill a vector's slots from a list (shared helper)
(def %vector-from-list
  (fn (_ type lst)
    (def len (%length lst))
    (def v (%make-obj type (%vec-int+ len 1)))
    (%obj-set! v 0 len)
    (def go (fn (self l i)
      (if (not (null? l))
        (do (%obj-set! v (%vec-int+ i 1) (first l)) (self (rest l) (%vec-int+ i 1))))))
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

; The common index: an INT within the length of a V that is a vector,
; negative counting from the end, whose slot ref, set! and a vector's
; call read or write at once; nil for any other -- one to be converted,
; one out of range, or a V that is no vector -- which takes the checked
; road, whose errors name the caller.
(def %vec-slot
  (fn (_ i v)
    (if (if (%type? v %vector) (eq? (%vec-type-of i) %vec-int-type) #f)
      (if (%vec-int< -1 i)
        (if (%vec-int< i (%obj-ref v 0)) (%vec-int+ i 1) ())
        (if (%vec-int< -1 (%vec-int+ (%obj-ref v 0) i)) (%vec-int+ (%vec-int+ (%obj-ref v 0) i) 1) ()))
      ())))
; V with X stored in slot K, for set!
(def %vec-put! (fn (_ v k x) (%obj-set! v k x) v))

; The checked roads.  %obj-ref is a raw slot read (arbitrary memory past the
; object), so the length in slot 0 is the x-lang bounds check.  Negative
; normalization is the same for all three, so (Vector ref -1 v) == (v -1).
; The nil guard makes a piped index-search miss fail loudly.
(def %vec-ref-checked
  (fn (_ i v)
    (def i2 (%vec->int i "Vector ref: index not convertible to INT"))
    (%vec-check v "Vector ref: not a vector")
    (def len (%obj-ref v 0))
    (def j (if (%vec-int< i2 0) (%vec-int+ len i2) i2))
    (if (%vec-int< j 0) (Err raise (lit index) "Vector ref: index out of range" ())
      (if (%vec-int< j len) (%obj-ref v (%vec-int+ j 1))
        (Err raise (lit index) "Vector ref: index out of range" ())))))
(def %vec-set-checked
  (fn (_ i x v)
    (def i2 (%vec->int i "Vector set!: index not convertible to INT"))
    (%vec-check v "Vector set!: not a vector")
    (def len (%obj-ref v 0))
    (def j (if (%vec-int< i2 0) (%vec-int+ len i2) i2))
    (if (%vec-int< j 0) (Err raise (lit index) "Vector set!: index out of range" ())
      (if (%vec-int< j len) (%vec-put! v (%vec-int+ j 1) x)
        (Err raise (lit index) "Vector set!: index out of range" ())))))
(def %vec-call-checked
  (fn (_ self i0)
    (def i (%vec->int i0 "vector: index not convertible to INT"))
    (def len (%obj-ref self 0))
    (def j (if (%vec-int< i 0) (%vec-int+ len i) i))
    (if (%vec-int< j 0) (Err raise (lit index) "vector: index out of range" ())
      (if (%vec-int< j len) (%obj-ref self (%vec-int+ j 1))
        (Err raise (lit index) "vector: index out of range" ())))))
(set! %vector
  (%make-type
    "VECTOR"
    (list
      (pair
        (lit call)
        (fn (_ self . args)
          ; (v) with no index at all: `first` on () is undefined (docs/spec.md)
          ; and would dereference nil -- a stray pair of parens crashed the
          ; process. A bare vector call names no element, so it raises rather
          ; than inventing a meaning; (Vector length v) is the length door.
          (if (null? args)
            (Err raise (lit index) "vector: call with no index" ())
            ())
          ; Bounds-checked like (Vector ref ...): %obj-ref past the object is a
          ; raw memory read, so slot 0's length is the guard for bare (v i) too.
          (def k (%vec-slot (first args) self))
          (if (null? k) (%vec-call-checked self (first args)) (%obj-ref self k))))
      (pair
        (lit write)
        (fn (_ self)
          (display "#(")
          (def len (%obj-ref self 0))
          (def write-vec
            (fn (recur i sep)
              (if (%vec-int< i len)
                (do
                  (if sep (display " "))
                  (write (%obj-ref self (%vec-int+ i 1)))
                  (recur (%vec-int+ i 1) #t)))))
          (write-vec 0 #f)
          (display ")")))
      (pair
        (lit analyse)
        (fn (_ buffer score chr)
          (if (= chr (%char->integer #\#))
            (fn (_ buf sc c0)
              (if (= c0 (%char->integer #\())
                (do (%buffer-unread buf) (%score-set sc 1 buf))
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
                  (if (%vec-int< i 0) acc
                    (self (%vec-int- i 1) (pair (%obj-ref v (%vec-int+ i 1)) acc)))))
              (build (%vec-int- len 1) ())))))
      (pair
        (lit iter)
        (fn (_ self)
          (def len (%obj-ref self 0))
          (def i 0)
          (fn (_ )
            (if (%vec-int< i len)
              (do
                (def val (%obj-ref self (%vec-int+ i 1)))
                (set! i (%vec-int+ i 1))
                val)
              ())))))))

; GC: vectors are per-instance sized -- the dynamic-units sentinel (-1)
; tells the mark hook to read the payload count from slot 0. Without
; it, vector payloads were NEVER traced: a collect freed the buckets
; out from under any Dict held across a REPL turn (SEGV on next get).
((prim-ref (lit type) (lit set-units!))
  ((prim-ref (lit type) (lit by-atom)) %vector) -1)

; The read primitive answers the EOF sentinel at end of input; a vector
; literal cut off there reads as an empty vector, as it did when the
; primitive answered nil.
(set! %vector-read
  (fn (_ . args)
    (let ((%v (%read)))
      (%vector-from-list %vector
        (match
          ((same? %v %token-eof) ())
          (#t %v))))))

(def-class Vector ()
  (static
    ; --- Constructors ---
    (method of (self . args)
      (doc "Create a vector from the given arguments."
        (returns VECTOR "New vector containing the arguments")
        (example "(Vector of 1 2 3)" "#(1 2 3)"))
      (%vector-from-list %vector args))
    (method make (self (param n INTEGER "Number of elements")
                       (param fill ANY "Value to fill each slot with"))
      (doc "Create a vector of length n, with every element set to fill."
        (returns VECTOR "New vector of length n filled with fill"))
      ; n is converted to INT once, as an index is, so the length and every
      ; count below run on the integer doors.
      (def k (%vec->int n "Vector make: length not convertible to INT"))
      ; A negative n built a vector REPORTING length n (#52): every later
      ; bounds check compared against it, so the container lied its whole
      ; life. Cold constructor seat -- the guard is one compare.
      (if (%vec-int< k 0) (Err raise (lit value) "Vector make: negative length" ()) ())
      (def v (%make-obj %vector (%vec-int+ k 1)))
      (%obj-set! v 0 k)
      (def loop
        (fn (self i)
          (if (%vec-int< i (%vec-int+ k 1))
            (do (%obj-set! v i fill) (self (%vec-int+ i 1))))))
      (loop 1)
      v)
    (method build (self (param n INTEGER "Number of elements")
                        (param f ANY "Index -> element function, called as (f i) for i in [0, n)"))
      (doc "Create a vector of length n where element i is (f i). Built in place -- no intermediate list."
        (returns VECTOR "New vector of length n, element i = (f i)")
        (example "(Vector build 3 (fn (_ i) (* i i)))" "#(0 1 4)"))
      (def k (%vec->int n "Vector build: length not convertible to INT"))
      (def v (%make-obj %vector (%vec-int+ k 1)))
      (%obj-set! v 0 k)
      (def loop
        (fn (self i)
          (if (%vec-int< i k)
            (do (%obj-set! v (%vec-int+ i 1) (f i)) (self (%vec-int+ i 1))))))
      (loop 0)
      v)
    ; --- Predicate ---
    (method vector? (self (param x ANY "Value to test"))
      (doc "Test whether a value is a vector." (returns BOOL "True if x is a vector"))
      (%type? x %vector))
    ; --- Access ---
    (method ref (self (param i INTEGER "Zero-based index; negative counts from the end") (param v VECTOR "Vector"))
      (doc "Return the element at index i of a vector; negative i counts from the end. Errors when i is out of range."
        (returns ANY "Element at index i"))
      (def k (%vec-slot i v))
      (if (null? k) (%vec-ref-checked i v) (%obj-ref v k)))
    (method set! (self (param i INTEGER "Zero-based index; negative counts from the end")
                       (param x ANY "Value to store")
                       (param v VECTOR "Vector"))
      (doc "Store x at index i of a vector (in place); negative i counts from the end. Errors when i is out of range; returns the vector for chaining."
        (returns VECTOR "v")
        (example "(Vector ref 0 (Vector set! 0 99 (Vector of 1 2)))" "99"))
      (def k (%vec-slot i v))
      (if (null? k) (%vec-set-checked i x v) (%vec-put! v k x)))
    (method length (self (param v VECTOR "Vector"))
      (doc "Return the number of elements in a vector." (returns INTEGER "Number of elements"))
      (%vec-check v "Vector length: not a vector")
      (%obj-ref v 0))
    ; --- Conversion ---
    (method ->list (self (param v VECTOR "Vector to convert"))
      (doc "Convert a vector to a list." (returns LIST "List of the vector's elements"))
      (%vec-check v "Vector ->list: not a vector")
      (def len (%obj-ref v 0))
      (def build
        (fn (self i acc)
          (if (%vec-int< i 0) acc
            (self (%vec-int- i 1) (pair (%obj-ref v (%vec-int+ i 1)) acc)))))
      (build (%vec-int- len 1) ()))
    (method from-list (self (param lst LIST "List to convert"))
      (doc "Convert a list to a vector." (returns VECTOR "New vector containing the list's elements"))
      (%vector-from-list %vector lst))
    (method iter (self (param v VECTOR "Vector to iterate"))
      (doc "An iterator over the vector's elements." (returns ITER "Iterator"))
      (Iter new v))
    ; --- Traversal ---
    ; Slot walks, not ->list walks: a vector is already indexable, so
    ; materialising a list first would allocate a pair per element for nothing.
    ; filter is the exception -- its result length is unknown until the walk
    ; ends, so it accumulates and converts once.  Every inner loop names its
    ; own self slot (go), never `self`: the method's self IS the class, and
    ; shadowing it would break the (self build ...) / (self from-list ...)
    ; sends these bodies make.
    (method for-each (self (param f CALLABLE "Applied to each element for effect")
                           (param v VECTOR "Vector to traverse"))
      (doc "Apply f to each element in order, for its side effects; returns nil. Named for-each, matching List/Iter/Seq."
        (returns ANY "nil"))
      (%vec-check v "Vector for-each: not a vector")
      (def len (%obj-ref v 0))
      (def go
        (fn (go i)
          (if (%vec-int< i len) (do (f (%obj-ref v (%vec-int+ i 1))) (go (%vec-int+ i 1))))))
      (go 0))
    (method map (self (param f CALLABLE "Applied to each element")
                      (param v VECTOR "Vector to map over"))
      (doc "A new vector of (f element), in order. Built in place -- no intermediate list."
        (returns VECTOR "New vector of the same length")
        (example "(Vector map (fn (_ x) (* x 2)) (Vector of 1 2 3))" "#(2 4 6)"))
      (%vec-check v "Vector map: not a vector")
      (self build (%obj-ref v 0) (fn (_ i) (f (%obj-ref v (%vec-int+ i 1))))))
    (method filter (self (param pred CALLABLE "Kept when it answers truthy")
                         (param v VECTOR "Vector to filter"))
      (doc "A new vector of the elements satisfying pred, in order."
        (returns VECTOR "New vector, possibly shorter")
        (example "(Vector filter (fn (_ x) (> x 1)) (Vector of 1 2 3))" "#(2 3)"))
      (%vec-check v "Vector filter: not a vector")
      ; Walks backwards so the accumulated list comes out in order -- one pass,
      ; no reverse.
      (def go
        (fn (go i acc)
          (if (%vec-int< i 0) acc
            (do
              (def x (%obj-ref v (%vec-int+ i 1)))
              (go (%vec-int- i 1) (if (pred x) (pair x acc) acc))))))
      (self from-list (go (%vec-int- (%obj-ref v 0) 1) ())))
    (method fold (self (param f CALLABLE "Combiner, called (f acc element)")
                       (param acc ANY "Initial accumulator")
                       (param v VECTOR "Vector to fold over"))
      (doc "Left-fold: thread acc through the elements, left to right."
        (returns ANY "The final accumulator")
        (example "(Vector fold + 0 (Vector of 1 2 3))" "6"))
      (%vec-check v "Vector fold: not a vector")
      (def len (%obj-ref v 0))
      (def go
        (fn (go i a)
          (if (%vec-int< i len) (go (%vec-int+ i 1) (f a (%obj-ref v (%vec-int+ i 1)))) a)))
      (go 0 acc))))

; Value dispatch over the existing index call handler. A symbol selector
; dispatches subject-LAST, so (v ref i) -> (Vector ref i v) and (v ->list) work;
; (v i) still indexes via the underlying call. `ref` is data-last ((self i v)),
; matching the library's Ramda data-last convention.
(bind-call-over! (Type of (Vector of 1)) Vector)

; Install elementwise vector equality on equal?'s extension hook (logic.x's
; %equal-others, fetched from the catalogue -- logic loads before this file, so
; equal? cannot name the vector type itself). Chains the previous handler;
; runs only after equal?'s identity check has already failed. %obj-ref direct
; (not Vector ref): both operands are known vectors and i is bounded by the
; slot-0 length.
(def %vector-equal
  (fn (_ eq a b)
    (def len (%obj-ref a 0))
    (if (%vec-int= len (%obj-ref b 0))
      (let go ((i 0))
        (if (%vec-int= i len) #t
          (if (eq (%obj-ref a (%vec-int+ i 1)) (%obj-ref b (%vec-int+ i 1)))
            (go (%vec-int+ i 1)) #f)))
      #f)))
(def %equal-others (prim-ref (lit logic) (lit equal-others)))
(%set-first! %equal-others
  (let ((prev (first %equal-others)))
    (fn (_ eq a b)
      (if (%type? a %vector)
        (if (%type? b %vector) (%vector-equal eq a b) #f)
        (prev eq a b)))))


; --- Block forms ------------------------------------------------------------
; (#(1 2 3) map (i x) (* x i)) alongside (Vector map f v); see x/type/block.x.
(import x/type/block)
(Block method! Vector (lit map))
(Block method! Vector (lit filter))
(Block method! Vector (lit for-each))
(Block method! Vector (lit fold) (lit fold) 2)
; build takes the count AHEAD of the callback, as List times does, so it
; wraps at position 1: (Vector build 3 (i) (* i i)) -- #(0 1 4).
(Block method! Vector (lit build) (lit element) 0 1)

(doc (provide x/type/vector Vector)
  (note "Literal syntax: #(1 2 3), with negative indexing via the vector's call slot.")
  (example "(Vector ref 1 (Vector of 10 20 30))" "20")
  "Fixed-size indexed vectors; operations homed on the Vector class.")

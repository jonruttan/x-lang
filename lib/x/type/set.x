; set.x -- Set: membership over a Dict (unit values).
;
; The thin wrapper the hash table makes nearly free: an element is a member
; iff it is a key in the backing Dict, so Set inherits Dict's content hashing
; (symbol/string/integer/char elements), instance identity keys (class
; instances, compared with eq?), equal? comparison, and O(1) expected
; add!/has?/del!. The algebra (union/intersection/difference) and the
; predicates over it (subset?/=?) are built from has? walks, so they are
; O(n) in the smaller operand.

(import x/type/class)
(import x/type/dict)
(import x/type/list)

(def-class Set ()
  (doc "A mutable set with O(1) expected membership, backed by a Dict."
    (note "Elements follow Dict's key rules: symbols, strings, integers, and chars compare by content (equal?); class instances are identity members (eq?).")
    (note "Mutators (add!/del!) return the set for chaining; the algebra (union/intersection/difference) returns new sets and mutates neither operand.")
    (example "(let ((s (Set from-list (list 1 2 2 3)))) (s length))" "3")
    (see add!) (see has?) (see union))

  d  ; backing Dict: element -> #t

  (static
    (method set? (self (param x ANY "Value to test"))
      (doc "Test whether a value is a Set." (returns BOOL "#t when x is a Set instance"))
      (if (object? x) (instance-of? x self) #f))

    (method make (self)
      (doc "An empty set." (returns Set "A new empty set"))
      (new-from self (list 'd (Dict make))))

    (method from-list (self (param lst LIST "Elements to add (duplicates collapse)"))
      (doc "Build a set from a list's elements."
        (returns Set "A set of the list's distinct elements")
        (example "((Set from-list (list 1 2 2)) length)" "2"))
      (def s (self make))
      (List for-each (fn (_ x) (s add! x)) lst)
      s)

    (method of (self . (param args ANY "Elements (duplicates collapse)"))
      (doc "Variadic literal: a set of the arguments."
        (returns Set "A set of the distinct arguments")
        (example "((Set of 1 2 2 3) length)" "3"))
      (self from-list args)))

  ; Uninitialized guard: an instance built outside make (generic new,
  ; raw new-from) has a nil dict member; every op funnels through %d so
  ; first USE raises the teaching error instead of calling nil.
  (method %d (self)
    (when (null? (member 'd)) (Err raise 'state "Set: uninitialized instance (use Set make / from-list / of)" ()))
    (member 'd))

  ; --- membership ---------------------------------------------------------
  (method add! (self x)
    (doc "Add an element (a no-op when already present); returns the set for chaining."
      (param x ANY "Element (symbol, string, integer, char, or class instance)")
      (returns Set "self"))
    ((self %d) put! x #t)
    self)

  (method has? (self x)
    (doc "Test membership."
      (param x ANY "Element to test")
      (returns BOOL "#t when x is a member"))
    ((self %d) has? x))

  (method del! (self x)
    (doc "Remove an element (a no-op when absent); returns the set for chaining."
      (param x ANY "Element to remove")
      (returns Set "self"))
    ((self %d) del! x)
    self)

  ; --- size ---------------------------------------------------------------
  (method length (self)
    (doc "The number of members (a stored property, O(1))." (returns INT "Member count"))
    ((self %d) length))

  (method empty? (self)
    (doc "Test whether the set has no members." (returns BOOL "#t when empty"))
    ((self %d) empty?))

  ; --- algebra ------------------------------------------------------------
  (method copy (self)
    (doc "A new set with the same members (a shallow copy)."
      (returns Set "An independent set of the same members"))
    (Set from-list (self ->list)))

  (method union (self (param other Set "Set to unite with"))
    (doc "A new set of the members of either operand."
      (returns Set "The union; neither operand is mutated")
      (example "(((Set of 1 2) union (Set of 2 3)) length)" "3"))
    (def out (self copy))
    (other for-each (fn (_ x) (out add! x)))
    out)

  (method intersection (self (param other Set "Set to intersect with"))
    (doc "A new set of the members common to both operands."
      (returns Set "The intersection; neither operand is mutated")
      (example "(((Set of 1 2) intersection (Set of 2 3)) ->list)" "(2)"))
    (self filter (fn (_ x) (other has? x))))

  (method difference (self (param other Set "Set of members to exclude"))
    (doc "A new set of this set's members absent from `other`."
      (returns Set "The difference; neither operand is mutated")
      (example "(((Set of 1 2) difference (Set of 2 3)) ->list)" "(1)"))
    (self filter (fn (_ x) (not (other has? x)))))

  ; --- predicates ---------------------------------------------------------
  (method subset? (self (param other Set "Candidate superset"))
    (doc "Test whether every member of this set is in `other`."
      (returns BOOL "#t when this set is a subset of other")
      (example "((Set of 1 2) subset? (Set of 1 2 3))" "#t"))
    (List all? (fn (_ x) (other has? x)) (self ->list)))

  (method superset? (self (param other Set "Candidate subset"))
    (doc "Test whether this set contains every member of `other`."
      (returns BOOL "#t when this set is a superset of other"))
    (other subset? self))

  (method =? (self (param other Set "Set to compare with"))
    (doc "Test whether both sets hold exactly the same members."
      (returns BOOL "#t when the sets are equal")
      (example "((Set of 1 2) =? (Set of 2 1))" "#t"))
    (if (= (self length) (other length)) (self subset? other) #f))

  ; --- iteration ----------------------------------------------------------
  (method for-each (self f)
    (doc "Apply f to each member, for side effects (unordered)."
      (param f CALLABLE "Applied to each member")
      (returns ANY "nil"))
    (List for-each f (self ->list)))

  (method filter (self f)
    (doc "A new set of the members passing a predicate."
      (param f CALLABLE "Predicate over a member")
      (returns Set "A set of the members where (f x) is true")
      (example "(((Set of 1 2 3 4) filter (fn (_ x) (> x 2))) length)" "2"))
    (Set from-list (List filter f (self ->list))))

  (method map (self f)
    (doc "A new set of the images of the members (duplicate images collapse)."
      (param f CALLABLE "Applied to each member")
      (returns Set "A set of the distinct (f x)")
      (example "(((Set of 1 2 3) map (fn (_ x) (* x 0))) length)" "1"))
    (Set from-list (List map f (self ->list))))

  (method fold (self f acc)
    (doc "Fold the members into an accumulator (unordered)."
      (param f CALLABLE "Applied as (f acc member)")
      (param acc ANY "Initial accumulator")
      (returns ANY "The final accumulator")
      (example "((Set of 1 2 3) fold (fn (_ a x) (+ a x)) 0)" "6"))
    (List fold f acc (self ->list)))

  ; --- extraction ---------------------------------------------------------
  (method ->list (self)
    (doc "The members as a list (unordered)." (returns LIST "List of members"))
    ((self %d) keys)))

(doc (provide x/type/set Set)
  (note "Membership = key presence in the backing Dict; same key-type rules -- content comparison, instances by identity.")
  (example "((Set from-list (list \"a\" \"b\" \"a\")) length)" "2")
  "Set: mutable membership with O(1) expected add/has?/del, plus the set algebra, on a Dict.")

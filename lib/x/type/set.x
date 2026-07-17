; set.x -- Set: membership over a Dict (unit values).
;
; The thin wrapper the hash table makes nearly free: an element is a member
; iff it is a key in the backing Dict, so Set inherits Dict's content hashing
; (symbol/string/integer/char elements), equal? comparison, and O(1) expected
; add!/has?/del!.

(import x/type/object)
(import x/type/dict)
(import x/type/list)

(def-class Set ()
  (doc "A mutable set with O(1) expected membership, backed by a Dict."
    (note "Elements follow Dict's key rules: symbols, strings, integers, or chars, compared by content (equal?).")
    (note "Mutators (add!/del!) return the set for chaining.")
    (example "(let ((s (Set from-list (list 1 2 2 3)))) (s count))" "3")
    (see add!) (see has?))

  d  ; backing Dict: element -> #t

  (static
    (method make (self)
      (doc "An empty set." (returns Set "A new empty set"))
      (new-from self (list 'd (Dict make))))

    (method from-list (self (param lst LIST "Elements to add (duplicates collapse)"))
      (doc "Build a set from a list's elements."
        (returns Set "A set of the list's distinct elements")
        (example "((Set from-list (list 1 2 2)) count)" "2"))
      (def s (self make))
      (List for-each (fn (_ x) (s add! x)) lst)
      s))

  (method add! (self x)
    (doc "Add an element (a no-op when already present); returns the set for chaining."
      (param x ANY "Element (symbol, string, integer, or char)")
      (returns Set "self"))
    ((member 'd) put! x #t)
    self)

  (method has? (self x)
    (doc "Test membership."
      (param x ANY "Element to test")
      (returns BOOL "#t when x is a member"))
    ((member 'd) has? x))

  (method del! (self x)
    (doc "Remove an element (a no-op when absent); returns the set for chaining."
      (param x ANY "Element to remove")
      (returns Set "self"))
    ((member 'd) del! x)
    self)

  (method count (self)
    (doc "The number of members." (returns INT "Member count"))
    ((member 'd) count))

  (method empty? (self)
    (doc "Test whether the set has no members." (returns BOOL "#t when empty"))
    ((member 'd) empty?))

  (method ->list (self)
    (doc "The members as a list (unordered)." (returns LIST "List of members"))
    ((member 'd) keys)))

(doc (provide x/type/set Set)
  (note "Membership = key presence in the backing Dict; same key-type rules and content comparison.")
  (example "((Set from-list (list \"a\" \"b\" \"a\")) count)" "2")
  "Set: mutable membership with O(1) expected add/has?/del, on a Dict.")

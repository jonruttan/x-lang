; type/counter.x -- Counter: a counting map (#375).
;
; A Dict of value -> occurrence count with the counting ergonomics
; pre-built: absent keys read 0, add! increments (by 1 or n), and
; most-common hands back the tallies sorted. Key kinds are Dict's
; (symbols, strings, ints, chars by content; instances by identity).
;
; Zero top-level %-globals (new-file budget 0).

(import x/type/class)
(import x/type/dict)
(import x/type/list)

(def-class Counter ()
  (doc "A counting map: (c add! x) tallies, (c get x) reads (0 when never seen), (c most-common) ranks. Backed by Dict, so key kinds and equality are Dict's."
    (example "(let ((c (Counter from-list (list 'a 'b 'a)))) (c get 'a))" "2")
    (see add!) (see most-common))

  d  ; the backing Dict: value -> count

  (static
    (method make (self)
      (doc "An empty counter."
        (returns Counter "A new empty counter")
        (example "((Counter make) total)" "0"))
      (new-from self (list 'd (Dict make))))

    (method from-list (self (param lst LIST "Values to tally, one occurrence each"))
      (doc "A counter holding one tally per list element."
        (returns Counter "The populated counter")
        (example "((Counter from-list (list \"x\" \"y\" \"x\")) get \"x\")" "2"))
      (let ((c (Counter make)))
        (List for-each (fn (_ x) (c add! x)) lst)
        c)))

  (method add! (self (param x ANY "Value to tally")
                     . (param n INT "Tally increment; default 1 (negative decrements)"))
    (doc "Add n (default 1) to x's tally. Returns the counter for chaining; a tally may go negative -- the counter records what it is told."
      (returns Counter "self"))
    (let ((d (member 'd)))
      (d set! x (+ (d get-or 0 x) (if (null? n) 1 (first n)))))
    self)

  (method get (self (param x ANY "Value to read"))
    (doc "x's tally; 0 when x was never added -- absence and zero read alike, the counting convention."
      (returns INT "The tally"))
    ((member 'd) get-or 0 x))

  (method del! (self (param x ANY "Value to forget"))
    (doc "Drop x's tally entirely (get returns 0 afterwards). Returns the counter for chaining."
      (returns Counter "self"))
    ((member 'd) del! x)
    self)

  (method total (self)
    (doc "The sum of every tally."
      (returns INT "Sum of counts")
      (example "(let ((c (Counter from-list (list 'a 'b 'a)))) (c total))" "3"))
    (List fold (fn (_ acc e) (+ acc (rest e))) 0 ((member 'd) ->alist)))

  (method keys (self)
    (doc "Every value holding a tally (order unspecified -- the Dict's table order)."
      (returns LIST "The tallied values"))
    ((member 'd) keys))

  (method ->alist (self)
    (doc "The tallies as ((value . count) ...), order unspecified."
      (returns ALIST "(value . count) pairs"))
    ((member 'd) ->alist))

  (method most-common (self . (param n INT "How many entries; default all"))
    (doc "The tallies as ((value . count) ...) sorted by count, largest first (ties in table order -- the sort is stable); pass n for just the top n."
      (returns ALIST "(value . count) pairs, descending by count")
      (example "(let ((c (Counter from-list (list 'a 'b 'a 'c 'a 'b)))) (c most-common 2))" "(('a . 3) ('b . 2))"))
    (let ((ranked (List sort (fn (_ a b) (> (rest a) (rest b)))
                    ((member 'd) ->alist))))
      (if (null? n) ranked (List take (first n) ranked)))))

(doc (provide x/type/counter Counter)
  (note "Dict-backed: key kinds and equality are Dict's; absent keys read 0; most-common rides the stable List sort, so equal counts keep table order.")
  "A counting map, homed on the Counter class.")

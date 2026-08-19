; type/deque.x -- Deque: a double-ended queue (#375).
;
; The classic two-list deque: pushes are O(1) onto the near list; a pop
; from an empty end reverses the far list first, so every element is
; moved at most once between pops -- amortized O(1) both ends. A `len`
; member keeps length O(1).
;
; Zero top-level %-globals (new-file budget 0).

(import x/type/class)
(import x/type/list)

(def-class Deque ()
  (doc "A double-ended queue: push!/pop! work the right end, push-left!/pop-left! the left, all amortized O(1) (the two-list construction). Empty pops raise kind-'value."
    (example "(let ((d (Deque make))) (d push! 2) (d push-left! 1) (d push! 3) (d ->list))" "(1 2 3)")
    (see push!) (see pop-left!))

  front  ; left end, in order
  back   ; right end, REVERSED (its head is the rightmost value)
  len    ; element count, kept O(1)

  (static
    (method make (self)
      (doc "An empty deque."
        (returns Deque "A new empty deque")
        (example "((Deque make) length)" "0"))
      (new-from self (list 'front () 'back () 'len 0))))

  (method push-left! (self (param v ANY "Value for the left end"))
    (doc "Push onto the left end: O(1). Returns the deque for chaining."
      (returns Deque "self"))
    (set-member! 'front (pair v (member 'front)))
    (set-member! 'len (+ (member 'len) 1))
    self)

  (method push! (self (param v ANY "Value for the right end"))
    (doc "Push onto the right end: O(1). Returns the deque for chaining."
      (returns Deque "self"))
    (set-member! 'back (pair v (member 'back)))
    (set-member! 'len (+ (member 'len) 1))
    self)

  ; Rebalance so the given end is non-empty (called only when it is empty
  ; and the OTHER end holds everything): move the far list over, reversed.
  (method %feed-front! (self)
    (set-member! 'front (%reverse (member 'back)))
    (set-member! 'back ()))
  (method %feed-back! (self)
    (set-member! 'back (%reverse (member 'front)))
    (set-member! 'front ()))

  (method pop-left! (self)
    (doc "Remove and return the leftmost value: amortized O(1); raises kind-'value when empty."
      (returns ANY "The leftmost value")
      (example "(let ((d (Deque make))) (d push! 1) (d push! 2) (d pop-left!))" "1"))
    (match
      ((= (member 'len) 0) (Err raise 'value "Deque pop-left!: empty" ()))
      (#t
        (let ()
          (when (null? (member 'front)) (self %feed-front!))
          (let ((v (first (member 'front))))
            (set-member! 'front (rest (member 'front)))
            (set-member! 'len (- (member 'len) 1))
            v)))))

  (method pop! (self)
    (doc "Remove and return the rightmost value: amortized O(1); raises kind-'value when empty."
      (returns ANY "The rightmost value")
      (example "(let ((d (Deque make))) (d push! 1) (d push! 2) (d pop!))" "2"))
    (match
      ((= (member 'len) 0) (Err raise 'value "Deque pop!: empty" ()))
      (#t
        (let ()
          (when (null? (member 'back)) (self %feed-back!))
          (let ((v (first (member 'back))))
            (set-member! 'back (rest (member 'back)))
            (set-member! 'len (- (member 'len) 1))
            v)))))

  (method peek-left (self)
    (doc "The leftmost value without removing it; raises kind-'value when empty."
      (returns ANY "The leftmost value"))
    (match
      ((= (member 'len) 0) (Err raise 'value "Deque peek-left: empty" ()))
      ((pair? (member 'front)) (first (member 'front)))
      (#t (List last (member 'back)))))

  (method peek (self)
    (doc "The rightmost value without removing it; raises kind-'value when empty. O(n) when every element sits on the far list; the pops stay amortized O(1)."
      (returns ANY "The rightmost value"))
    (match
      ((= (member 'len) 0) (Err raise 'value "Deque peek: empty" ()))
      ((pair? (member 'back)) (first (member 'back)))
      (#t (List last (member 'front)))))

  (method length (self)
    (doc "How many values the deque holds (kept O(1))."
      (returns INT "The count"))
    (member 'len))

  (method empty? (self)
    (doc "Is the deque empty?"
      (returns BOOL "#t when it holds nothing"))
    (= (member 'len) 0))

  (method ->list (self)
    (doc "The deque's values, left to right, as a fresh list; the deque is untouched."
      (returns LIST "Values in deque order"))
    (List append (member 'front) (%reverse (member 'back)))))

(doc (provide x/type/deque Deque)
  (note "Two-list construction: each element moves between the lists at most once, so both ends pop amortized O(1); length rides a counter.")
  "A double-ended queue, homed on the Deque class.")

; dict.x -- Dict: a mutable hash table (buckets over a raw slot vector).
;
; THE associative container with O(1) expected lookup -- Assoc (alists) is
; O(n) and eq?-keyed, so string keys don't work there at all. Dict hashes by
; CONTENT (FNV-1a on the characters, never by pointer: GC relocates heap
; objects, so pointer hashes would rot) and compares bucket keys with equal?,
; so symbol, string, integer, and char keys all behave. Anything else errors
; loudly instead of misbehaving silently.
;
; Internals: `store` is a vector (slot 0 = capacity, the raw-obj pattern)
; whose slots 1..cap each hold an alist bucket of (key . val) pairs; `n`
; counts entries; put! doubles the table past a 3/4 load factor.

(import x/type/object)
(import x/core/hash)
(import x/type/vector)
(import x/type/list)

; Fetch the raw slot prims from the catalog (ns `obj` is de-registered, R5).
(def %dict-obj-ref (prim-ref (lit obj) (lit ref)))
(def %dict-obj-set! (prim-ref (lit obj) (lit set!)))
; Fetch the char cast (ns `char` utility members de-registered, R5).
(def %dict-char->int (prim-ref (lit char) (lit ->int)))

(def %dict-mask31 2147483647)  ; FNV-1a is 64-bit SIGNED -- mask before %

; Content hash per supported key type. Non-negative by construction, so the
; bucket index (% h cap) never goes negative (C-truncating % keeps the sign).
(def %dict-hash
  (fn (_ k)
    (match
      ((symbol? k) (& (Hash fnv-1a (symbol->str k)) %dict-mask31))
      ((str? k) (& (Hash fnv-1a k) %dict-mask31))
      ((number? k) (& k %dict-mask31))
      ((char? k) (%dict-char->int k))
      (#t (error "Dict: unhashable key -- use a symbol, string, integer, or char")))))

; Find the (key . val) entry pair in a bucket, or (). Returning the ENTRY
; (a box), not the value, keeps presence distinguishable from a stored nil.
(def %dict-find
  (fn (self k bucket)
    (match
      ((null? bucket) ())
      ((equal? k (first (first bucket))) (first bucket))
      (#t (self k (rest bucket))))))

(def %dict-remove
  (fn (self k bucket)
    (match
      ((null? bucket) ())
      ((equal? k (first (first bucket))) (rest bucket))
      (#t (pair (first bucket) (self k (rest bucket)))))))

(def-class Dict ()
  (doc "A mutable hash table: O(1) expected get/put!/del! over content-hashed keys."
    (note "Keys may be symbols, strings, integers, or chars (hashed by content, compared with equal?); anything else errors.")
    (note "Mutators (put!/del!) return the dict for chaining. get-or is presence-based: a stored nil is returned, not the default.")
    (example "(let ((d (Dict make))) (d put! \"k\" 1) (d get \"k\"))" "1")
    (see make) (see get) (see put!))

  store  ; bucket vector: slot 0 = cap, slots 1..cap = (key . val) alists
  cap    ; bucket count
  n      ; entry count

  (static
    (method dict? (self (param x ANY "Value to test"))
      (doc "Test whether a value is a Dict." (returns BOOL "#t when x is a Dict instance"))
      (if (object? x) (instance-of? x self) #f))

    (method make (self . opt)
      (doc "An empty dict. Pass a capacity to pre-size the bucket table."
        (param opt LIST "Optional (capacity) -- initial bucket count, default 8")
        (returns Dict "A new empty dict")
        (example "(Dict make)" "an empty dict"))
      (def c (if (pair? opt) (first opt) 8))
      (new-from self (list 'store (Vector make c ()) 'cap c 'n 0)))

    (method from-alist (self (param alist LIST "Alist ((key . val) ...) to load"))
      (doc "Build a dict from an alist (later duplicates overwrite earlier)."
        (returns Dict "A dict holding the alist's assocs")
        (example "((Dict from-alist (list (pair \"a\" 1))) get \"a\")" "1"))
      (def d (self make))
      (List for-each (fn (_ e) (d put! (first e) (rest e))) alist)
      d))

  ; --- internals ----------------------------------------------------------
  ; Bucket slot index (1-based; slot 0 is the capacity) for a key.
  (method %slot (self k)
    (+ 1 (% (%dict-hash k) (member 'cap))))

  ; Double the table and rehash. Entry pairs are reused (rehash moves them
  ; between buckets; it does not copy), so this is O(n) with no reallocation
  ; of the entries themselves.
  (method %grow! (self)
    (def old (member 'store))
    (def oldcap (member 'cap))
    (def newcap (* 2 oldcap))
    (set-member! 'store (Vector make newcap ()))
    (set-member! 'cap newcap)
    (let go ((i 1))
      (if (> i oldcap) ()
        (do (List for-each
              (fn (_ e)
                (let ((j (self %slot (first e))))
                  (%dict-obj-set! (member 'store) j
                    (pair e (%dict-obj-ref (member 'store) j)))))
              (%dict-obj-ref old i))
            (go (+ i 1))))))

  ; --- lookup -------------------------------------------------------------
  (method get (self k)
    (doc "The value stored under a key, or nil when absent."
      (param k ANY "Key (symbol, string, integer, or char)")
      (returns ANY "Stored value, or nil")
      (example "(let ((d (Dict make))) (d put! (lit a) 1) (d get (lit a)))" "1"))
    (let ((hit (%dict-find k (%dict-obj-ref (member 'store) (self %slot k)))))
      (if (null? hit) () (rest hit))))

  (method get-or (self d k)
    (doc "The value stored under a key, or a default only when the key is ABSENT."
      (param d ANY "Default for an absent key")
      (param k ANY "Key to look up")
      (returns ANY "Stored value (a stored nil included), or the default"))
    (let ((hit (%dict-find k (%dict-obj-ref (member 'store) (self %slot k)))))
      (if (null? hit) d (rest hit))))

  (method get-or-else (self thunk k)
    (doc "The value stored under a key, or (thunk) only when the key is ABSENT -- get-or's lazy twin (mirrors Assoc opt-get-or-else)."
      (param thunk CALLABLE "Nullary default producer; runs only on a miss")
      (param k ANY "Key to look up")
      (returns ANY "Stored value (a stored nil included), or (thunk)"))
    (let ((hit (%dict-find k (%dict-obj-ref (member 'store) (self %slot k)))))
      (if (null? hit) (thunk) (rest hit))))

  (method has? (self k)
    (doc "Test whether a key is present."
      (param k ANY "Key to test")
      (returns BOOL "#t when the key is stored"))
    (pair? (%dict-find k (%dict-obj-ref (member 'store) (self %slot k)))))

  ; --- mutation -----------------------------------------------------------
  (method put! (self k v)
    (doc "Store a value under a key (overwriting any previous value); returns the dict for chaining."
      (param k ANY "Key (symbol, string, integer, or char)")
      (param v ANY "Value to store")
      (returns Dict "self")
      (example "(((Dict make) put! (lit a) 1) get (lit a))" "1"))
    (def i (self %slot k))
    (def bucket (%dict-obj-ref (member 'store) i))
    (def hit (%dict-find k bucket))
    (if (null? hit)
      (do (%dict-obj-set! (member 'store) i (pair (pair k v) bucket))
          (set-member! 'n (+ (member 'n) 1))
          (if (> (* 4 (member 'n)) (* 3 (member 'cap)))
            (self %grow!) ()))
      (set-rest! hit v))
    self)

  (method del! (self k)
    (doc "Remove a key (a no-op when absent); returns the dict for chaining."
      (param k ANY "Key to remove")
      (returns Dict "self"))
    (def i (self %slot k))
    (def bucket (%dict-obj-ref (member 'store) i))
    (if (pair? (%dict-find k bucket))
      (do (%dict-obj-set! (member 'store) i (%dict-remove k bucket))
          (set-member! 'n (- (member 'n) 1)))
      ())
    self)

  ; --- size ---------------------------------------------------------------
  (method length (self)
    (doc "The number of stored entries (a stored property, O(1))." (returns INT "Entry count"))
    (member 'n))

  (method empty? (self)
    (doc "Test whether the dict holds no entries." (returns BOOL "#t when empty"))
    (= 0 (member 'n)))

  ; --- extraction ---------------------------------------------------------
  (method ->alist (self)
    (doc "A fresh alist snapshot of the entries (unordered)."
      (returns LIST "((key . val) ...) -- new assocs, detached from the table"))
    ; copy each entry: the live (key . val) pairs are mutated by put!, so a
    ; snapshot must not alias them
    (let go ((i 1) (acc ()))
      (if (> i (member 'cap)) acc
        (go (+ i 1)
            (List fold (fn (_ a e) (pair (pair (first e) (rest e)) a))
              acc (%dict-obj-ref (member 'store) i))))))

  (method keys (self)
    (doc "All stored keys (unordered)." (returns LIST "List of keys"))
    (List map first (self ->alist)))

  (method vals (self)
    (doc "All stored values (unordered)." (returns LIST "List of values"))
    (List map rest (self ->alist)))

  (method for-each (self f)
    (doc "Apply f to each (key . val) entry pair, for side effects."
      (param f CALLABLE "Applied to each (key . val) pair")
      (returns ANY "nil"))
    (List for-each f (self ->alist))))

(doc (provide x/type/dict Dict)
  (note "Buckets over a raw slot vector; content hashing (FNV-1a) + equal? keys; doubles past a 3/4 load factor.")
  (example "(let ((d (Dict make))) (d put! \"k\" 1) (d get \"k\"))" "1")
  "Dict: a mutable content-hashed table -- the O(1) associative container.")

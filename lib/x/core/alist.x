; alist.x -- Association list operations
(import x/core/list)
;
; Alists: ((key1 . val1) (key2 . val2) ...)
; Keys compared with eq? (symbol pointer equality)

(note "Lookup")

(doc (def assoc-get
  (fn (self (param key SYMBOL "Key to look up")
       (param alist LIST "Association list"))
    (match
      ((null? alist) ())
      ((eq? key (first (first alist))) (rest (first alist)))
      (#t (self key (rest alist))))))
  (returns ANY "Value associated with key, or nil if not found")
  "Look up a key in an alist, returning its value or nil.")

(doc (def assoc-get-or
  (fn (_ (param d ANY "Default value if key is absent")
       (param key SYMBOL "Key to look up")
       (param alist LIST "Association list"))
    (def result (assoc-get key alist))
    (if (null? result) d result)))
  (returns ANY "Value associated with key, or the default")
  "Look up a key in an alist, returning a default if not found.")

(doc (def assoc-has?
  (fn (self (param key SYMBOL "Key to check")
       (param alist LIST "Association list"))
    (match
      ((null? alist) #f)
      ((eq? key (first (first alist))) #t)
      (#t (self key (rest alist))))))
  (returns BOOL "True if key is present")
  "Test whether a key exists in an alist.")

(note "Modification")

(doc (def assoc-del
  (fn (self (param key SYMBOL "Key to remove")
       (param alist LIST "Association list"))
    (match
      ((null? alist) ())
      ((eq? key (first (first alist))) (self key (rest alist)))
      (#t (pair (first alist) (self key (rest alist)))))))
  (returns LIST "Alist without the given key")
  "Remove all entries for a key from an alist.")

(doc (def assoc-put
  (fn (_ (param key SYMBOL "Key to set")
       (param val ANY "Value to associate")
       (param alist LIST "Association list"))
    (pair (pair key val) (assoc-del key alist))))
  (returns LIST "Alist with the key set to val")
  "Set a key-value pair, replacing any existing entry for that key.")

(note "Extraction")

(doc (def assoc-keys (fn (_ (param alist LIST "Association list")) (map first alist)))
  (returns LIST "List of keys")
  "Return all keys from an alist.")

(doc (def assoc-vals (fn (_ (param alist LIST "Association list")) (map rest alist)))
  (returns LIST "List of values")
  "Return all values from an alist.")

(note "Transformation")

(doc (def assoc-map
  (fn (_ (param f CALLABLE "Function applied to each value")
       (param alist LIST "Association list"))
    (map
      (fn (_ entry) (pair (first entry) (f (rest entry))))
      alist)))
  (returns LIST "New alist with transformed values")
  "Apply a function to every value in an alist, preserving keys.")

(doc (def assoc-filter
  (fn (_ (param pred CALLABLE "Predicate: (entry) -> bool")
       (param alist LIST "Association list"))
    (filter pred alist)))
  (returns LIST "Filtered alist")
  "Keep only entries satisfying a predicate.")

(doc (def assoc-merge
  (fn (_ (param a LIST "Base alist (takes priority)")
       (param b LIST "Alist to merge in"))
    (fold
      (fn (_ acc entry)
        (if (assoc-has? (first entry) acc) acc (pair entry acc)))
      a
      b)))
  (returns LIST "Merged alist; entries in a shadow those in b")
  "Merge two alists; keys in the first take priority.")

(doc (def assoc-pick
  (fn (_ (param keys LIST "List of keys to keep")
       (param alist LIST "Association list"))
    (filter (fn (_ entry) (includes? (first entry) keys)) alist)))
  (returns LIST "Alist containing only the selected keys")
  "Select entries whose keys appear in a given list.")

(doc (def assoc-omit
  (fn (_ (param keys LIST "List of keys to exclude")
       (param alist LIST "Association list"))
    (filter
      (fn (_ entry) (not (includes? (first entry) keys)))
      alist)))
  (returns LIST "Alist without the excluded keys")
  "Remove entries whose keys appear in a given list.")

(note "Conversion")

(doc (def from-pairs
  (fn (_ (param lst LIST "List of two-element lists"))
    (map (fn (_ p) (pair (first p) (first (rest p)))) lst)))
  (returns LIST "Association list")
  "Convert a list of (key value) lists into an alist of dotted pairs.")

(doc (def to-pairs
  (fn (_ (param alist LIST "Association list"))
    (map (fn (_ entry) (list (first entry) (rest entry))) alist)))
  (returns LIST "List of two-element lists")
  "Convert an alist of dotted pairs into a list of (key value) lists.")

(doc (def evolve
  (fn (_ (param fns LIST "Alist of key -> transform function")
       (param alist LIST "Association list to transform"))
    (map
      (fn (_ entry)
        (def transform (assoc-get (first entry) fns))
        (if (null? transform)
          entry
          (pair (first entry) (transform (rest entry)))))
      alist)))
  (returns LIST "Alist with selected values transformed")
  "Apply per-key transform functions to values in an alist.")

(note "Option stores")

; An "option store" is either an alist ((k . v) ...) or a flat plist
; (k v k v ...).  %opt-cell walks one looking for `key`: the head of each step
; reveals the layout -- an alist entry is a pair, a plist key is a bare symbol,
; and keys are always symbols, so a key is never mistaken for an entry.  It
; returns a one-element box (value) when present, or () when absent, so callers
; test presence with null? (pair vs nil).  A box, NOT a value-sentinel: eq? on a
; sentinel cannot be trusted to differ from a stored 0/nil/#f.  Keys compared
; with eq?, as everywhere else in this module.
(def %opt-cell
  (fn (loop key store)
    (match
      ((null? store) ())                                 ; empty store -> absent
      ; Guards: first/rest are unchecked (UB on a non-pair -- segfaults on
      ; 32-bit), so a malformed store must be rejected before we walk it.  A
      ; non-list store (e.g. (first args) that yielded a bare symbol) and a
      ; plist key with no value cell (odd length, or the pair-valued "keys"
      ; you get from quoting names) both error cleanly instead of crashing.
      ((not (pair? store))
        (error "opt store: expected an alist or plist"))
      ((pair? (first store))                              ; alist entry (k . v)
        (if (eq? key (first (first store)))
          (list (rest (first store)))
          (loop key (rest store))))
      ((not (pair? (rest store)))                         ; plist key, no value
        (error "opt store: key without a value (use bare names, not quoted)"))
      (#t                                                 ; plist cell: k then v
        (if (eq? key (first store))
          (list (first (rest store)))
          (loop key (rest (rest store))))))))

(doc (def opt-get-or
  (fn (_ (param d ANY "Default value if key is absent")
       (param key SYMBOL "Key to look up")
       (param store LIST "Option store: alist or flat plist"))
    (let ((c (%opt-cell key store)))
      (if (null? c) d (first c)))))
  (returns ANY "Stored value, or the default")
  (example "(opt-get-or 0 (lit b) (lit (a 1)))" "0")
  "Look up a key in an option store (alist or plist); return a default if absent.")

(doc (def opt-get-or-else
  (fn (_ (param thunk CALLABLE "Nullary function producing the default")
       (param key SYMBOL "Key to look up")
       (param store LIST "Option store: alist or flat plist"))
    (let ((c (%opt-cell key store)))
      (if (null? c) (thunk) (first c)))))
  (returns ANY "Stored value, or (thunk) when the key is absent")
  "Like opt-get-or but the default is lazy: thunk runs only when the key is absent.")

; Compile one let-opts binding spec into the (name value-form) pair that let*
; expects.  The default is wrapped in a (fn () ...) thunk so opt-get-or-else
; evaluates it only when the option is absent -- a present option never runs its
; default expression.  %opt-get-form builds that lazy lookup form; %opt-binding
; dispatches on spec shape:
;   symbol         -> default (), key = name
;   (name default) -> key = name
;   (name key def) -> explicit lookup key, distinct from the bound name
(def %opt-get-form
  (fn (_ key default)
    (list (lit opt-get-or-else)
          (list (lit fn) () default)                      ; (fn () DEFAULT) -- lazy
          (list (lit lit) key)                            ; 'KEY
          (lit %opts))))

(def %opt-binding
  (fn (_ b)
    (match
      ((symbol? b)             (list b (%opt-get-form b ())))
      ((null? (rest (rest b))) (list (first b) (%opt-get-form (first b) (first (rest b)))))
      (#t                      (list (first b)
                                 (%opt-get-form (first (rest b)) (first (rest (rest b)))))))))

(doc (def let-opts
  (op (src bindings . body)
    e
    ; Expand to let*: %opts holds the evaluated source once and is visible to
    ; every lookup, and the option bindings stay local to body.  (let, unlike the
    ; older do+def expansion, does not leak the bindings into the caller frame e.)
    (tail-eval
      (pair (lit let*)
        (pair (pair (list (lit %opts) src) (map %opt-binding bindings))
              body))
      e)))
  (note "Each binding is name | (name default) | (name key default). Defaults are")
  (note "lazy (run only when the option is absent) and may reference earlier bindings.")
  (note "The source evaluates to an alist ((k . v) ...) or a flat plist (k v ...).")
  (example "(let-opts (lit (a 1)) ((a 0) (b 0)) (+ a b))" "1")
  (see opt-get-or)
  "Bind locals from an option store (alist or plist) with lazy per-binding defaults.")

(doc (provide x/core/alist
  assoc-get assoc-get-or assoc-has? assoc-del assoc-put
  assoc-keys assoc-vals assoc-map assoc-filter assoc-merge
  assoc-pick assoc-omit from-pairs to-pairs evolve
  opt-get-or opt-get-or-else let-opts)
  (note "Alist format is ((key . val) ...). Keys compared with eq?.")
  (example "(assoc-get (lit x) '((x . 1) (y . 2)))" "1")
  "Association list operations.")

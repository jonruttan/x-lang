; assoc.x -- Assoc: the association-list API as static methods.
;
; The five bootstrap operations (get/has?/del/put/keys) live in core/alist.x
; (the object system runs on them, pre-object) -- the methods here delegate.
; Everything else is implemented here. Alists are ((key . val) ...) with keys
; compared by eq?; option stores (opt-get-or...) also accept flat plists.

(import x/core/alist)
(import x/type/object)

(def-class Assoc ()
  (static
    ; --- Lookup ---
    (method get (self (param key SYMBOL "Key to look up") (param alist LIST "Association list"))
      (doc "Look up a key in an alist, returning its value or nil." (returns ANY "Value associated with key, or nil if not found"))
      (assoc-get key alist))
    (method get-or (self (param d ANY "Default value if key is absent")
                         (param key SYMBOL "Key to look up")
                         (param alist LIST "Association list"))
      (doc "Look up a key in an alist, returning a default only when the key is absent."
        (returns ANY "Value associated with key, or the default")
        (note "Presence-based: a stored nil is returned as-is, not replaced by the default."))
      ; Delegate to the box-based walker: testing (null? (assoc-get ...)) would
      ; hand back the default for a PRESENT key whose stored value is nil.
      (%opt-get-or-else (fn () d) key alist))
    (method has? (self (param key SYMBOL "Key to check") (param alist LIST "Association list"))
      (doc "Test whether a key exists in an alist." (returns BOOL "True if key is present"))
      (assoc-has? key alist))
    ; --- Modification ---
    (method del (self (param key SYMBOL "Key to remove") (param alist LIST "Association list"))
      (doc "Remove all entries for a key from an alist." (returns LIST "Alist without the given key"))
      (assoc-del key alist))
    (method put (self (param key SYMBOL "Key to set") (param val ANY "Value to associate")
                      (param alist LIST "Association list"))
      (doc "Set a key-value pair, replacing any existing entry for that key." (returns LIST "Alist with the key set to val"))
      (assoc-put key val alist))
    ; --- Extraction ---
    (method keys (self (param alist LIST "Association list"))
      (doc "Return all keys from an alist." (returns LIST "List of keys"))
      (assoc-keys alist))
    (method vals (self (param alist LIST "Association list"))
      (doc "Return all values from an alist." (returns LIST "List of values"))
      (map rest alist))
    ; --- Transformation ---
    (method map (self (param f CALLABLE "Function applied to each value")
                      (param alist LIST "Association list"))
      (doc "Apply a function to every value in an alist, preserving keys." (returns LIST "New alist with transformed values"))
      (map (fn (_ entry) (pair (first entry) (f (rest entry)))) alist))
    (method filter (self (param pred CALLABLE "Predicate: (entry) -> bool")
                         (param alist LIST "Association list"))
      (doc "Keep only entries satisfying a predicate." (returns LIST "Filtered alist"))
      (filter pred alist))
    (method merge (self (param a LIST "Base alist (takes priority)")
                        (param b LIST "Alist to merge in"))
      (doc "Merge two alists; keys in the first take priority." (returns LIST "Merged alist; entries in a shadow those in b"))
      (fold
        (fn (_ acc entry)
          (if (assoc-has? (first entry) acc) acc (pair entry acc)))
        a
        b))
    (method pick (self (param keys LIST "List of keys to keep")
                       (param alist LIST "Association list"))
      (doc "Select entries whose keys appear in a given list." (returns LIST "Alist containing only the selected keys"))
      (filter (fn (_ entry) (List includes? (first entry) keys)) alist))
    (method omit (self (param keys LIST "List of keys to exclude")
                       (param alist LIST "Association list"))
      (doc "Remove entries whose keys appear in a given list." (returns LIST "Alist without the excluded keys"))
      (filter (fn (_ entry) (not (List includes? (first entry) keys))) alist))
    ; --- Conversion ---
    (method from-pairs (self (param lst LIST "List of two-element lists"))
      (doc "Convert a list of (key value) lists into an alist of dotted pairs." (returns LIST "Association list"))
      (map (fn (_ p) (pair (first p) (first (rest p)))) lst))
    (method ->pairs (self (param alist LIST "Association list"))
      (doc "Convert an alist of dotted pairs into a list of (key value) lists." (returns LIST "List of two-element lists"))
      (map (fn (_ entry) (list (first entry) (rest entry))) alist))
    (method evolve (self (param fns LIST "Alist of key -> transform function")
                         (param alist LIST "Association list to transform"))
      (doc "Apply per-key transform functions to values in an alist." (returns LIST "Alist with selected values transformed"))
      (map
        (fn (_ entry)
          (def transform (assoc-get (first entry) fns))
          (if (null? transform)
            entry
            (pair (first entry) (transform (rest entry)))))
        alist))
    ; --- Option stores ---
    (method opt-get-or (self (param d ANY "Default value if key is absent")
                             (param key SYMBOL "Key to look up")
                             (param store LIST "Option store: alist or flat plist"))
      (doc "Look up a key in an option store (alist or plist); return a default if absent."
        (returns ANY "Stored value, or the default")
        (example "(Assoc opt-get-or 0 (lit b) (lit (a 1)))" "0"))
      (%opt-get-or-else (fn () d) key store))
    (method opt-get-or-else (self (param thunk CALLABLE "Nullary function producing the default")
                                  (param key SYMBOL "Key to look up")
                                  (param store LIST "Option store: alist or flat plist"))
      (doc "Like opt-get-or but the default is lazy: thunk runs only when the key is absent."
        (returns ANY "Stored value, or (thunk) when the key is absent"))
      (%opt-get-or-else thunk key store))))

(doc (provide x/type/assoc Assoc)
  (note "Alist format is ((key . val) ...). Keys compared with eq?.")
  (note "The get/has?/del/put/keys bootstrap globals remain in x/core/alist (the object")
  (note "system runs on them); these methods delegate to that layer.")
  (example "(Assoc get (lit x) '((x . 1) (y . 2)))" "1")
  "Association list operations, homed on the Assoc class.")

; alist.x -- Association list operations
(import x/list)
;
; Alists: ((key1 . val1) (key2 . val2) ...)
; Keys compared with eq? (symbol pointer equality)

(note "Lookup")

(doc (def assoc-get
  (fn ((param key SYMBOL "Key to look up")
       (param alist LIST "Association list"))
    (match
      ((null? alist) ())
      ((eq? key (first (first alist))) (rest (first alist)))
      (#t (assoc-get key (rest alist))))))
  (returns ANY "Value associated with key, or nil if not found")
  "Look up a key in an alist, returning its value or nil.")

(doc (def assoc-get-or
  (fn ((param d ANY "Default value if key is absent")
       (param key SYMBOL "Key to look up")
       (param alist LIST "Association list"))
    (def result (assoc-get key alist))
    (if (null? result) d result)))
  (returns ANY "Value associated with key, or the default")
  "Look up a key in an alist, returning a default if not found.")

(doc (def assoc-has?
  (fn ((param key SYMBOL "Key to check")
       (param alist LIST "Association list"))
    (match
      ((null? alist) #f)
      ((eq? key (first (first alist))) #t)
      (#t (assoc-has? key (rest alist))))))
  (returns BOOL "True if key is present")
  "Test whether a key exists in an alist.")

(note "Modification")

(doc (def assoc-del
  (fn ((param key SYMBOL "Key to remove")
       (param alist LIST "Association list"))
    (match
      ((null? alist) ())
      ((eq? key (first (first alist))) (assoc-del key (rest alist)))
      (#t (pair (first alist) (assoc-del key (rest alist)))))))
  (returns LIST "Alist without the given key")
  "Remove all entries for a key from an alist.")

(doc (def assoc-put
  (fn ((param key SYMBOL "Key to set")
       (param val ANY "Value to associate")
       (param alist LIST "Association list"))
    (pair (pair key val) (assoc-del key alist))))
  (returns LIST "Alist with the key set to val")
  "Set a key-value pair, replacing any existing entry for that key.")

(note "Extraction")

(doc (def assoc-keys (fn ((param alist LIST "Association list")) (map first alist)))
  (returns LIST "List of keys")
  "Return all keys from an alist.")

(doc (def assoc-vals (fn ((param alist LIST "Association list")) (map rest alist)))
  (returns LIST "List of values")
  "Return all values from an alist.")

(note "Transformation")

(doc (def assoc-map
  (fn ((param f CALLABLE "Function applied to each value")
       (param alist LIST "Association list"))
    (map
      (fn (entry) (pair (first entry) (f (rest entry))))
      alist)))
  (returns LIST "New alist with transformed values")
  "Apply a function to every value in an alist, preserving keys.")

(doc (def assoc-filter
  (fn ((param pred CALLABLE "Predicate: (entry) -> bool")
       (param alist LIST "Association list"))
    (filter pred alist)))
  (returns LIST "Filtered alist")
  "Keep only entries satisfying a predicate.")

(doc (def assoc-merge
  (fn ((param a LIST "Base alist (takes priority)")
       (param b LIST "Alist to merge in"))
    (fold
      (fn (acc entry)
        (if (assoc-has? (first entry) acc) acc (pair entry acc)))
      a
      b)))
  (returns LIST "Merged alist; entries in a shadow those in b")
  "Merge two alists; keys in the first take priority.")

(doc (def assoc-pick
  (fn ((param keys LIST "List of keys to keep")
       (param alist LIST "Association list"))
    (filter (fn (entry) (includes? (first entry) keys)) alist)))
  (returns LIST "Alist containing only the selected keys")
  "Select entries whose keys appear in a given list.")

(doc (def assoc-omit
  (fn ((param keys LIST "List of keys to exclude")
       (param alist LIST "Association list"))
    (filter
      (fn (entry) (not (includes? (first entry) keys)))
      alist)))
  (returns LIST "Alist without the excluded keys")
  "Remove entries whose keys appear in a given list.")

(note "Conversion")

(doc (def from-pairs
  (fn ((param lst LIST "List of two-element lists"))
    (map (fn (p) (pair (first p) (first (rest p)))) lst)))
  (returns LIST "Association list")
  "Convert a list of (key value) lists into an alist of dotted pairs.")

(doc (def to-pairs
  (fn ((param alist LIST "Association list"))
    (map (fn (entry) (list (first entry) (rest entry))) alist)))
  (returns LIST "List of two-element lists")
  "Convert an alist of dotted pairs into a list of (key value) lists.")

(doc (def evolve
  (fn ((param fns LIST "Alist of key -> transform function")
       (param alist LIST "Association list to transform"))
    (map
      (fn (entry)
        (def transform (assoc-get (first entry) fns))
        (if (null? transform)
          entry
          (pair (first entry) (transform (rest entry)))))
      alist)))
  (returns LIST "Alist with selected values transformed")
  "Apply per-key transform functions to values in an alist.")

(provide x/alist
  assoc-get assoc-get-or assoc-has? assoc-del assoc-put
  assoc-keys assoc-vals assoc-map assoc-filter assoc-merge
  assoc-pick assoc-omit from-pairs to-pairs evolve)

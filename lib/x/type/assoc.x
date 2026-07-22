; assoc.x -- Assoc: the association-list API as static methods.
;
; The five bootstrap operations (get/has?/del/put/keys) live in core/alist.x
; (the object system runs on them, pre-object) -- the methods here delegate.
; Everything else is implemented here. Alists are ((key . val) ...) with keys
; compared by eq?; option stores (opt-get-or...) also accept flat plists.

(import x/core/alist)
(import x/type/class)

; Entry guard for the public alist seats (#51, ruled from the benchmark).
; The boot walkers (%assoc-get and friends) stay documented-unchecked: a
; per-step spine guard measured +66% on the walk and +7.4% on EVERY method
; dispatch in the language (the object system routes through assoc-get),
; and was STILL incomplete -- entries must be cells too, so completeness
; extrapolates past +120%. The crashes actually reported ((Assoc get 'k 42),
; (Assoc get 'k (pair 1 2))) are misuse of THIS public API, so the check
; runs once per CALL here -- the spine head and the first entry must be
; cells -- and costs ~2 closure calls on methods that already cost ~100us.
; A dotted tail deeper in the spine remains unchecked, same status as
; first/rest. The cold/hot split is the same one Str8's `start` uses.
(def %assoc-check
  (fn (_ al what)
    (match
      ((null? al) al)
      ((not (pair? al)) (Err raise (lit type) what ()))
      ((not (pair? (first al))) (Err raise (lit type) what ()))
      (#t al))))

(def-class Assoc ()
  (static
    ; --- Lookup ---
    (method get (self (param key SYMBOL "Key to look up") (param alist LIST "Association list"))
      (doc "Look up a key in an alist, returning its value or nil." (returns ANY "Value associated with key, or nil if not found"))
      (%assoc-get key (%assoc-check alist "Assoc get: not an alist")))
    (method get-or (self (param d ANY "Default value if key is absent")
                         (param key SYMBOL "Key to look up")
                         (param alist LIST "Association list"))
      (doc "Look up a key in an alist, returning a default only when the key is absent."
        (returns ANY "Value associated with key, or the default")
        (note "Presence-based: a stored nil is returned as-is, not replaced by the default.")
        (note "Delegates to the option-store walker, so a flat plist is also accepted."))
      ; Delegate to the box-based walker: testing (null? (%assoc-get ...)) would
      ; hand back the default for a PRESENT key whose stored value is nil.
      (%opt-get-or-else (fn () d) key (%assoc-check alist "Assoc get-or: not an alist")))
    (method has? (self (param key SYMBOL "Key to check") (param alist LIST "Association list"))
      (doc "Test whether a key exists in an alist." (returns BOOL "True if key is present"))
      (%assoc-has? key (%assoc-check alist "Assoc has?: not an alist")))
    ; --- Modification ---
    (method del (self (param key SYMBOL "Key to remove") (param alist LIST "Association list"))
      (doc "Remove all entries for a key from an alist." (returns LIST "Alist without the given key"))
      (%assoc-del key (%assoc-check alist "Assoc del: not an alist")))
    (method put (self (param key SYMBOL "Key to set") (param val ANY "Value to associate")
                      (param alist LIST "Association list"))
      (doc "Set a key-value pair, replacing any existing entry for that key." (returns LIST "Alist with the key set to val"))
      (%assoc-put key val (%assoc-check alist "Assoc put: not an alist")))
    ; --- Extraction ---
    (method keys (self (param alist LIST "Association list"))
      (doc "Return all keys from an alist." (returns LIST "List of keys"))
      (%assoc-keys (%assoc-check alist "Assoc keys: not an alist")))
    (method vals (self (param alist LIST "Association list"))
      (doc "Return all values from an alist." (returns LIST "List of values"))
      (%map rest (%assoc-check alist "Assoc vals: not an alist")))
    ; --- Transformation ---
    (method map (self (param f CALLABLE "Function applied to each value")
                      (param alist LIST "Association list"))
      (doc "Apply a function to every value in an alist, preserving keys." (returns LIST "New alist with transformed values"))
      (%map (fn (_ entry) (pair (first entry) (f (rest entry)))) alist))
    (method filter (self (param pred CALLABLE "Predicate: (assoc) -> bool, applied to each (key . val) assoc")
                         (param alist LIST "Association list"))
      (doc "Keep only assocs satisfying a predicate." (returns LIST "Filtered alist"))
      (%filter pred alist))
    (method merge (self (param a LIST "Base alist (takes priority)")
                        (param b LIST "Alist to merge in"))
      (doc "Merge two alists; keys in the first take priority." (returns LIST "Merged alist; entries in a shadow those in b"))
      ; a's entries keep their original order at the FRONT, with b's additions
      ; following in b's order. Folding `pair` onto `a` directly put b's
      ; entries first and reversed among themselves (#73). Additions
      ; accumulate reversed and flip once, so this stays a single pass plus a
      ; reverse rather than an append per entry. The has? checks cover both a
      ; and the additions so far, so a duplicate key inside b keeps its first
      ; occurrence -- the same rule the growing accumulator gave before.
      (%append a
        (%reverse
          (%fold
            (fn (_ acc entry)
              (if (%assoc-has? (first entry) a) acc
                (if (%assoc-has? (first entry) acc) acc (pair entry acc))))
            ()
            b))))
    (method pick (self (param keys LIST "List of keys to keep")
                       (param alist LIST "Association list"))
      (doc "Select entries whose keys appear in a given list." (returns LIST "Alist containing only the selected keys"))
      (%filter (fn (_ entry) (List includes? (first entry) keys)) alist))
    (method omit (self (param keys LIST "List of keys to exclude")
                       (param alist LIST "Association list"))
      (doc "Remove entries whose keys appear in a given list." (returns LIST "Alist without the excluded keys"))
      (%filter (fn (_ entry) (not (List includes? (first entry) keys))) alist))
    ; --- Conversion ---
    (method from-bindings (self (param bindings LIST "Bindings list: ((key value) ...) two-element lists, the let shape"))
      (doc "Convert a bindings list into an alist of (key . val) assocs." (returns LIST "Association list"))
      (%map (fn (_ b) (pair (first b) (first (rest b)))) bindings))
    (method ->bindings (self (param alist LIST "Association list"))
      (doc "Convert an alist into a bindings list of (key value) two-element lists." (returns LIST "Bindings list"))
      (%map (fn (_ entry) (list (first entry) (rest entry))) alist))
    (method from-plist (self (param plist LIST "Flat (k v k v ...) plist"))
      (doc "Convert a flat plist into an alist of assocs." (returns LIST "Association list")
        (example "(Assoc from-plist (list 'a 1))" "(('a . 1))"))
      (match
        ((null? plist) ())
        ((null? (rest plist)) (Err raise (lit value) "Assoc from-plist: odd-length plist" ()))
        (#t (pair (pair (first plist) (first (rest plist)))
              (recur self (rest (rest plist)))))))
    (method ->plist (self (param alist LIST "Association list"))
      (doc "Convert an alist into a flat (k v k v ...) plist." (returns LIST "Plist"))
      (match
        ((null? alist) ())
        (#t (pair (first (first alist)) (pair (rest (first alist))
              (recur self (rest alist)))))))
    (method evolve (self (param fns LIST "Alist of key -> transform function")
                         (param alist LIST "Association list to transform"))
      (doc "Apply per-key transform functions to values in an alist." (returns LIST "Alist with selected values transformed"))
      (%map
        (fn (_ entry)
          (def transform (%assoc-get (first entry) fns))
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
        (example "(Assoc opt-get-or 0 'b '(a 1))" "0"))
      (%opt-get-or-else (fn () d) key store))
    (method opt-get-or-else (self (param thunk CALLABLE "Nullary function producing the default")
                                  (param key SYMBOL "Key to look up")
                                  (param store LIST "Option store: alist or flat plist"))
      (doc "Like opt-get-or but the default is lazy: thunk runs only when the key is absent."
        (returns ANY "Stored value, or (thunk) when the key is absent"))
      (%opt-get-or-else thunk key store))))

(doc (provide x/type/assoc Assoc)
  (note "An assoc is one dotted (key . val) pair; an alist is a list of assocs. Keys compared with eq?.")
  (note "The get/has?/del/put/keys bootstrap globals remain in x/core/alist (the object")
  (note "system runs on them); these methods delegate to that layer.")
  (example "(Assoc get 'x '((x . 1) (y . 2)))" "1")
  "Association list operations, homed on the Assoc class.")

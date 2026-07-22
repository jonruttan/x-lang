; alist.x -- Association-list bootstrap layer
(import x/core/list)
;
; Alists: ((key1 . val1) (key2 . val2) ...)
; Keys compared with eq? (symbol pointer equality)
;
; This file is the BOOTSTRAP layer: the five operations the object system
; itself runs on (object.x dispatches members through assoc-get/assoc-put/
; assoc-has?/assoc-keys, and assoc-put needs assoc-del), plus the let-opts
; form and its %-private runtime support. It loads before object.x, so it
; cannot reference classes. The full association API homes on the Assoc
; class (lib/x/type/assoc.x), which delegates to this layer.

(note "Lookup")

(doc (def assoc-get
  (fn (self (param key SYMBOL "Key to look up")
       (param alist LIST "Association list"))
    (match
      ((null? alist) ())
      ((eq? key (first (first alist))) (rest (first alist)))
      (#t (self key (rest alist))))))
  (returns ANY "Value associated with key, or nil if not found")
  (note "Bootstrap layer: the object system dispatches through this. Class API: (Assoc get ...).")
  "Look up a key in an alist, returning its value or nil.")

(doc (def assoc-has?
  (fn (self (param key SYMBOL "Key to check")
       (param alist LIST "Association list"))
    (match
      ((null? alist) #f)
      ((eq? key (first (first alist))) #t)
      (#t (self key (rest alist))))))
  (returns BOOL "True if key is present")
  (note "Bootstrap layer: the object system dispatches through this. Class API: (Assoc has? ...).")
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
  (note "Bootstrap layer. Class API: (Assoc del ...).")
  "Remove all entries for a key from an alist.")

(doc (def assoc-put
  (fn (_ (param key SYMBOL "Key to set")
       (param val ANY "Value to associate")
       (param alist LIST "Association list"))
    (pair (pair key val) (assoc-del key alist))))
  (returns LIST "Alist with the key set to val")
  (note "Bootstrap layer: the object system dispatches through this. Class API: (Assoc put ...).")
  "Set a key-value pair, replacing any existing entry for that key.")

(note "Extraction")

(doc (def assoc-keys (fn (_ (param alist LIST "Association list")) (%map first alist)))
  (returns LIST "List of keys")
  (note "Bootstrap layer: the object system's introspection uses this. Class API: (Assoc keys ...).")
  "Return all keys from an alist.")

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

; let-opts' runtime lookup hook: the expansion below references this %-private
; by name, so it must stay a global def in the bootstrap layer.  The public API
; is (Assoc opt-get-or ...) / (Assoc opt-get-or-else ...), which delegate here.
(def %opt-get-or-else
  (fn (_ thunk key store)
    (let ((c (%opt-cell key store)))
      (if (null? c) (thunk) (first c)))))

; Compile one let-opts binding spec into the (name value-form) pair a let
; binding expects.  The default is wrapped in a (fn () ...) thunk so %opt-get-or-else
; evaluates it only when the option is absent -- a present option never runs its
; default expression.  %opt-get-form builds that lazy lookup form; %opt-binding
; dispatches on spec shape:
;   symbol         -> default (), key = name
;   (name default) -> key = name
;   (name key def) -> explicit lookup key, distinct from the bound name
(def %opt-get-form
  (fn (_ key default)
    (list (lit %opt-get-or-else)
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

; Nest one let per binding (sequential visibility; let* is retired, #45 R6).
; bindings is never empty -- %opts always leads.
(def %opt-nest
  (fn (self bindings body)
    (if (null? (rest bindings))
      (pair (lit let) (pair (list (first bindings)) body))
      (list (lit let) (list (first bindings)) (self (rest bindings) body)))))

(doc (def let-opts
  (op (src bindings . body)
    e
    ; Expand to nested lets: %opts holds the evaluated source once and is
    ; visible to every lookup, each binding sees the ones before it, and the
    ; bindings stay local to body (no leak into the caller frame e).
    (tail-eval
      (%opt-nest (pair (list (lit %opts) src) (%map %opt-binding bindings))
                 body)
      e)))
  (note "Each binding is name | (name default) | (name key default). Defaults are")
  (note "lazy (run only when the option is absent) and may reference earlier bindings.")
  (note "The source evaluates to an alist ((k . v) ...) or a flat plist (k v ...).")
  (example "(let-opts '(a 1) ((a 0) (b 0)) (+ a b))" "1")
  (see assoc-get)
  "Bind locals from an option store (alist or plist) with lazy per-binding defaults.")

(doc (provide x/core/alist
  assoc-get assoc-has? assoc-del assoc-put assoc-keys let-opts)
  (note "The bootstrap layer the object system runs on, plus the let-opts form.")
  (note "The full association API is the Assoc class: (Assoc merge a b), (Assoc map f al), ...")
  (example "(assoc-get 'x '((x . 1) (y . 2)))" "1")
  "Association-list bootstrap: get/has?/del/put/keys and let-opts.")

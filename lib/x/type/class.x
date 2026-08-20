; class.x -- the class system: message passing, single inheritance, def-class
; (renamed from object.x, #36: it collided with obj.x, the small raw-slot
; wrapper class -- one name per concept)
(import x/core/alist)
; Fetch the string prims from the catalog (ns `str` is de-registered, R5).
(def %str-append (prim-ref (lit str) (lit append)))
(def %str->symbol (prim-ref (lit str) (lit ->sym)))
(def %display-to-str (prim-ref (lit io) (lit display-to-str)))  ; render a bad init key in errors
; Fetch the type prims from the catalog (ns `type` is de-registered, R5).
(def %make-type (prim-ref (lit type) (lit make)))
(def %make-instance (prim-ref (lit type) (lit make-instance)))
(def %type? (prim-ref (lit type) (lit ?)))
(def %type-by-atom (prim-ref (lit type) (lit by-atom)))
(def %type-call-top (prim-ref (lit type) (lit call-top)))
(def %type-push-call (prim-ref (lit type) (lit push-call)))


;
; CLASSES ARE OBJECTS. A class is a callable %class object; an instance is a
; callable %object. Dispatch mirrors one level up:
;
;            (obj name ...)                 (Class name ...)
;   method   instance method (from class)   static method
;   member   instance member get/set        class-wide member get/set
;   self     the instance                   the class
;
; A class's data is an alist:
;   ((name . N) (fields . MEM) (methods . IM) (parent . P)
;    (s-methods . SM) (statics . STATICS-BOX))
; -- the `fields` key holds the instance members as a (name . default-value) alist;
; IM the instance methods; SM the static methods; STATICS-BOX a one-cell mutable box
; holding the class-wide (static) member alist. An instance's slot 0 holds
; (class . field-box); the field-box is a one-cell mutable (name . value) alist.
;
; Selectors are literal -- both dispatch handlers are OPERATIVES, so (obj name)
; needs no quote, while args evaluate in the caller's env.

(note "Accessors (internal plumbing)")

(def %obj-class  (fn (_ inst) (first (first inst))))   ; an instance's class object
(def %obj-box    (fn (_ inst) (rest  (first inst))))   ; instance field box
(def %obj-fields (fn (_ inst) (first (%obj-box inst))))
(def %class-data (fn (_ c) (first c)))                 ; a class object's alist

; In-place write into a boxed alist: mutate the existing entry when the key
; is present (the common case -- every declared member exists from
; construction), else prepend a fresh entry. Replaces the %assoc-put path,
; which copied the whole alist per write and reordered the written key to
; the head: the update path now allocates nothing and field order stays
; construction order. An in-flight iteration over the alist sees the update
; (live view, not a snapshot).
(def %box-put!
  (fn (_ box key v)
    (let ((entry (%assq key (first box))))
      (if (null? entry)
        (%set-first! box (pair (pair key v) (first box)))
        (%set-rest! entry v))
      v)))

; Raw field accessors injected into every instance-method body (closing over
; `self`), so a method can bypass a same-named override to reach a field's
; storage -- the "private data" pattern. Method-local only.
;   (member 'name) / (set-member! 'name v)
(def %method-raw-bindings
  (lit
    ((member     (fn (_ n) (%assoc-get n (%obj-fields self))))
     (set-member! (fn (_ n v) (%box-put! (%obj-box self) n v))))))

(note "Flat dispatch tables (the hot path)")

; Unique sentinel marking a FIELD entry in a flat table (a method entry is
; the method closure itself). A fresh pair, compared by eq? -- unforgeable.
(def %field-tag (list (lit %field)))

; Privacy wrapper sentinel: a table entry (%priv-tag vis defining . inner)
; guards inner behind the dispatch-door check below. Same unforgeable-pair
; trick as %field-tag.
(def %priv-tag (list (lit %priv)))

; The ambient caller-class probe. Every method body lexically rebinds
; %this-class to a one-cell box holding its DEFINING class (filled by
; def-class once the class object exists); evaluated from a non-method
; context it resolves to this nil. super derives its parent from the same
; box, replacing the old direct %super-class binding at zero added
; per-call bindings.
(def %this-class ())

; Find `sel` in a flat table and self-organize: a hit DEEPER THAN POSITION
; TWO swaps its (sel . entry) pair with the head's via two %set-first!, so a
; hot selector is a front hit from its second call on. The top-2 exemption
; matters: a method that reads a field alternates two hot selectors, and
; unconditional move-to-front made them ping-pong the head slot -- two swap
; writes per call, measured slower than no table at all. With the exemption
; an alternating pair settles into the top two and never swaps again.
; Returns the entry (a method closure or %field-tag) or nil. `head` is the
; table's first spine cell; callers pass the table twice.
(def %tab-find!
  (fn (loop cell head sel)
    (unless (null? cell)
      (let ((p (first cell)))
        (if (eq? (first p) sel)
          (do
            (unless (if (eq? cell head) #t (eq? cell (rest head)))
              (%set-first! cell (first head))
              (%set-first! head p))
            (rest p))
          (loop (rest cell) head sel))))))

; Build a class's hot record: flat, chain-merged dispatch tables plus the
; construction caches, shape
;   (itab stab fields ctor-names)
; itab holds instance methods + instance-field markers; stab holds static
; methods + static-member markers, both chain-merged. An OWN static member
; marks as the bare %field-tag; an INHERITED one as (%field-tag . OWNER),
; the nearest ancestor whose box holds it -- reads go to the owner's box,
; matching what (help) has always displayed. A static member named `new`
; is dropped at every level: it never shadowed the new builtin. fields is
; the %all-fields (name . default-thunk) alist and ctor-names the
; positional constructor order. Most-derived wins: the chain walk records a
; name on first sight only, and a method beats a same-named field marker
; exactly as dispatch always had it. Every spine pair and (sel . entry)
; pair is freshly consed -- %tab-find! reorders the table in place, so it
; must share no structure with the cold class alists (slot 0), which stay
; the single authoritative source help and introspection read.
(def %flatten-class
  (fn (_ class)
    ; local + cold on purpose: activation-scoped mid-body defs (only TAIL
    ; defs leak globally under TCO), the %build-class pattern.
    (def %seen?
      (fn (loop n tab)
        (if (null? tab) #f
          (if (eq? n (first (first tab))) #t (loop n (rest tab))))))
    (def %fold-rows                       ; add (k . (mk row)) on first sight
      (fn (loop al mk acc)
        (if (null? al) acc
          (loop (rest al) mk
            (if (%seen? (first (first al)) acc)
              acc
              (pair (pair (first (first al)) (mk (first al))) acc))))))
    (def %not-new? (fn (_ row) (not (eq? (first row) (lit new)))))
    ; Visibility wrap: a name listed in the defining level's vis alist
    ; ((name . private|protected) ...) gets its entry guarded as
    ; (%priv-tag vis defining . inner); anything else passes bare.
    (def %vis-wrap
      (fn (_ c visal name inner)
        (let ((v (%assoc-get name visal)))
          (if (null? v) inner
            (pair %priv-tag (pair v (pair c inner)))))))
    (def %ivis-of (fn (_ c) (%assoc-get (lit ivis) (%class-data c))))
    (def %svis-of (fn (_ c) (%assoc-get (lit svis) (%class-data c))))
    (def %walk-methods                    ; `key` method alists, derived first
      (fn (loop c key visf acc)
        (if (null? c) acc
          (loop (%assoc-get (lit parent) (%class-data c)) key visf
            (let ((visal (visf c)))
              (%fold-rows (%assoc-get key (%class-data c))
                (fn (_ row) (%vis-wrap c visal (first row) (rest row)))
                acc))))))
    (def %walk-ifields                    ; instance-field markers, derived first
      (fn (loop c acc)
        (if (null? c) acc
          (loop (%assoc-get (lit parent) (%class-data c))
            (let ((visal (%ivis-of c)))
              (%fold-rows (%assoc-get (lit fields) (%class-data c))
                (fn (_ row) (%vis-wrap c visal (first row) %field-tag))
                acc))))))
    (def %walk-statics                    ; ancestor static members, nearest first
      (fn (loop c acc)
        (if (null? c) acc
          (loop (%assoc-get (lit parent) (%class-data c))
            (let ((visal (%svis-of c)))
              (%fold-rows (%filter %not-new? (%class-statics c))
                (fn (_ row) (%vis-wrap c visal (first row) (pair %field-tag c)))
                acc))))))
    (let ((fields (%all-fields class)))
      (list (%walk-ifields class (%walk-methods class (lit methods) %ivis-of ()))
            (%walk-statics (%assoc-get (lit parent) (%class-data class))
              (let ((visal (%svis-of class)))
                (%fold-rows (%filter %not-new? (%class-statics class))
                  (fn (_ row) (%vis-wrap class visal (first row) %field-tag))
                  (%walk-methods class (lit s-methods) %svis-of ()))))
            fields
            (%ctor-member-names class)))))

; Every class ever built, for table invalidation: a shadow-write (or, later
; in this arc, runtime method addition) clears every class's slot 1 with
; %classes-invalidate!, and each rebuilds on its next dispatch. Classes
; carry no child links, so "which descendants are stale" is unanswerable
; locally -- and mutation is cold, so clearing everything is the cheap side
; of the trade (the hot path keeps ZERO staleness checks). The registry
; pins redefined class objects; redefinition is a REPL affair and the cold
; alists are small.
(def %class-registry (list ()))
(def %classes-invalidate!
  (fn (_)
    (def %go
      (fn (loop cs)
        (unless (null? cs)
          (do (%set-rest! (first cs) ())
              (loop (rest cs))))))
    (%go (first %class-registry))))

; Add a method row to a class's cold alist (key = methods | s-methods) and
; invalidate every hot table. Prepend, so the newest registration wins over
; both an earlier addition and the def-class-time definition (the flattener
; records first sight per level). Returns nil: a mutation, not a value.
(def %class-add!
  (fn (_ class key sel f)
    (unless (symbol? sel)
      (error "def-method!: selector must be a symbol"))
    (let ((row (%assq key (%class-data class))))
      (%set-rest! row (pair (pair sel f) (rest row))))
    (%classes-invalidate!)
    ()))

; Unwrap a privacy wrapper to its inner entry, NO access check -- for the
; runtime's own protocol-hook lookups (%init, %missing), which fire on the
; instance's behalf whatever the hook's declared visibility.
(def %entry-inner
  (fn (_ entry)
    (if (if (pair? entry) (eq? (first entry) %priv-tag) #f)
      (rest (rest (rest entry)))
      entry)))

; The dispatch-door privacy check. The caller's class comes from the
; lexical %this-class box every method body binds; from a non-method
; context the ambient nil makes the answer "outside". private = the same
; class only; protected = chain-related in EITHER direction, so a parent
; method calling down into a subclass-protected override stays legal, as
; does the ordinary inherited-helper call up.
(def %vis-allowed?
  (fn (_ vis defining e)
    (let ((b (eval (lit %this-class) e)))
      (let ((caller (if (null? b) () (first b))))
        (match
          ((null? caller) #f)
          ((eq? vis (lit private)) (same? caller defining))
          ((%class-ancestor? caller defining) #t)
          (#t (%class-ancestor? defining caller)))))))

; A pair entry reaching a dispatch method branch is a privacy wrapper
; (%priv-tag vis defining . inner): check access, then process inner
; exactly as the plain branches would. Guarded members are the cold side
; by construction, so the method path uses plain apply -- no trampoline
; subtleties inside a helper fn.
(def %priv-entry
  (fn (_ target class entry selector args e static?)
    (let ((vis (first (rest entry)))
          (defining (first (rest (rest entry))))
          (inner (rest (rest (rest entry)))))
      (unless (%vis-allowed? vis defining e)
        (error (%str-append (symbol->str (class-name class))
          (%str-append ": " (%str-append (symbol->str selector)
            (%str-append (if (eq? vis (lit private)) " is private to " " is protected to ")
              (symbol->str (class-name defining))))))))
      (match
        ((eq? inner %field-tag)
          (if static?
            (match
              ((null? args) (%assoc-get selector (%class-statics class)))
              (#t (%box-put! (%class-statics-box class) selector (eval (first args) e))))
            (match
              ((null? args) (%assoc-get selector (%obj-fields target)))
              (#t (%box-put! (%obj-box target) selector (eval (first args) e))))))
        ((if (pair? inner) (eq? (first inner) %field-tag) #f)   ; inherited static
          (match
            ((null? args) (%assoc-get selector (%class-statics (rest inner))))
            (#t
              (let ((v (eval (first args) e)))
                (%box-put! (%class-statics-box class) selector v)
                (%classes-invalidate!)
                v))))
        (#t (apply inner (pair target (%map1 (fn (_ a) (eval a e)) args))))))))

; Entry discrimination for the cold resolvers (method-of, method-ref, the
; value-call handlers): a callable PUBLIC method entry, or nil for a miss,
; a field marker, an inherited-static marker, or a privacy-guarded entry --
; the resolvers are reachable from anywhere, so they never hand out a
; guarded method.
(def %entry-method
  (fn (_ entry)
    (match
      ((null? entry) ())
      ((eq? entry %field-tag) ())
      ((if (pair? entry) #t #f) ())
      (#t entry))))

; Forwarder engine for the `delegates` def-class form: resolve `sel` on
; the delegate value's own tables per call (late-bound, like method-ref)
; and apply directly on the already-evaluated args. Methods only: a
; delegate's FIELD is reached by writing the one-line method by hand.
(def %delegate-call
  (fn (_ target sel args)
    (let ((entry
            (if (object? target)
              (let ((itab (first (%class-hot (%obj-class target)))))
                (%entry-method (%tab-find! itab itab sel)))
              (if (class? target)
                (let ((stab (first (rest (%class-hot target)))))
                  (%entry-method (%tab-find! stab stab sel)))
                ()))))
      (if (null? entry)
        (error (%str-append "delegates: no such method " (symbol->str sel)))
        (apply entry (pair target args))))))

; A class's hot record, built on first dispatch. Lives in the class
; object's SLOT 1 -- the free traced slot make-instance leaves nil -- while
; slot 0 keeps the cold authoritative alist. No staleness probe on the hot
; path: classes are immutable after def-class today, and a redefinition
; mints a fresh class object (fresh empty slot 1). The open-classes phase
; adds mutators; they must clear slot 1 (via a class registry) rather than
; tax every dispatch with a generation compare.
(def %class-hot
  (fn (_ class)
    (let ((hot (rest class)))
      (if (null? hot)
        (let ((fresh (%flatten-class class)))
          (%set-rest! class fresh)
          fresh)
        hot))))

; Total dispatch miss, one seam. The %missing protocol hook fires first
; when the chain defines it: (method %missing (self sel args) ...) --
; instance side resolves it through the flat itab, static side through the
; stab, so it inherits like any method. `target` is the receiver (instance
; or class), `args` the RAW argument forms, evaluated here (cold path)
; before the hook sees them as a list. Without a hook, a named error.
; The generic-dispatch trapdoor interposes here in a later phase.
(def %dispatch-miss
  (fn (_ target class selector args e static?)
    (let ((tab (if static?
                 (first (rest (%class-hot class)))
                 (first (%class-hot class)))))
      (let ((m (%entry-method (%entry-inner (%tab-find! tab tab (lit %missing))))))
        (if (null? m)
          (error (%str-append (symbol->str (class-name class))
            (%str-append (if static? ": no such static member " ": no such member ")
              (symbol->str selector))))
          (apply m (list target selector
                     (%map1 (fn (_ a) (eval a e)) args))))))))

(note "Member lookup (walks the single-inheritance parent chain)")

; Look `selector` up in table `key` (methods | s-methods) along the class chain.
(def %lookup
  (fn (loop class key selector)
    (unless (null? class)
      (let ((data (%class-data class)))
        (let ((hit (%assoc-get selector (%assoc-get key data))))
          (if (null? hit)
            (loop (%assoc-get (lit parent) data) key selector)
            hit))))))

; Unwrap a quoted 'x (i.e. (lit x)) to the bare symbol x, so (obj x) and (obj 'x)
; both name the member x.
(def %selector
  (fn (_ s)
    (if (if (pair? s) (eq? (first s) (lit lit)) #f)
      (first (rest s))
      s)))

; Reject an init key that names no declared member, so (new Cell 1 2) -- where 1
; is read as a member name -- fails loudly instead of silently using defaults.
; `fields` is the %all-fields alist (member name . default).
(def %check-init-key
  (fn (_ key fields class)
    (unless (%assoc-has? key fields)
      (error (%str-append "new: " (%str-append (%display-to-str key)
        (%str-append " is not a member of " (%display-to-str (class-name class)))))))))

; Walk an init store (plist `name val ...` OR alist `((name . val) ...)`),
; checking every key, before %init-fields uses it. Mirrors %opt-cell's walk and
; its malformed-store guards so the two agree on what counts as a key.
(def %check-init-keys
  (fn (loop store fields class)
    (match
      ((null? store) ())
      ((not (pair? store)) (error "new: init store must be an alist or plist"))
      ((pair? (first store))                              ; alist entry (k . v)
        (do (%check-init-key (first (first store)) fields class)
            (loop (rest store) fields class)))
      ((not (pair? (rest store)))                         ; plist key with no value
        (error "new: init key without a value (use bare member names)"))
      (#t                                                 ; plist cell: k then v
        (do (%check-init-key (first store) fields class)
            (loop (rest (rest store)) fields class))))))

; Names in `names` not already in `seen`, in order -- the subclass-additions
; step of the constructor order below.
(def %names-minus
  (fn (loop names seen)
    (unless (null? names)
      (if (%memq? (first names) seen)
        (loop (rest names) seen)
        (pair (first names) (loop (rest names) seen))))))

; Instance members in CONSTRUCTOR order: the root ancestor's members first,
; then each subclass's own additions; an override keeps its ancestor's slot
; (the child's default still wins, via %all-fields). This is the order a
; positional (new C v1 v2 ...) fills -- %all-fields keeps the child-first
; order introspection shows.
(def %ctor-member-names
  (fn (loop class)
    (unless (null? class)
      (let ((up (loop (%assoc-get (lit parent) (%class-data class)))))
        (%append2 up
          (%names-minus (%assoc-keys (%assoc-get (lit fields) (%class-data class))) up))))))

; The keyword tail of a new call begins at `inits` when its head form is a
; (name . val) pair headed by a declared member (dotted-alist form), or a bare
; member name WITH a value form after it (plist form). A TRAILING bare member
; name is a positional value -- the common constructor arg named after the
; member it fills: (def root ...) (Distances new root). The residual footgun,
; documented on new: a NON-trailing positional value spelled as a bare member
; name (or a call headed by one) still reads as the keyword tail.
(def %keyword-tail?
  (fn (_ inits fields)
    (let ((form (first inits)))
      (match
        ; (name . val) dotted-alist entry: keyword when its head names a member
        ((pair? form) (and (symbol? (first form)) (%assoc-has? (first form) fields)))
        ; a bare member name opens the keyword tail only when a VALUE form
        ; follows it; a TRAILING one is a positional value ((Distances new root))
        ((symbol? form) (and (%assoc-has? form fields) (pair? (rest inits))))
        (#t #f)))))

; Split a new op's args into positional prefix + keyword tail: positional
; forms are paired with %ctor-member-names as (name . form) alist entries, and
; the tail passes through as-is -- %check-init-keys and %opt-cell both walk
; the resulting mixed store.
(def %positional->store
  (fn (loop inits names fields class)
    (match
      ((null? inits) ())
      ((%keyword-tail? inits fields) inits)              ; keyword tail begins
      ((null? names)
        (error (%str-append "new: too many positional values for "
          (%display-to-str (class-name class)))))
      (#t (pair (pair (first names) (first inits))
            (loop (rest inits) (rest names) fields class))))))

; Build an instance: instance fields (across the chain) initialised from inits.
; eval? selects how supplied values are treated (see %init-fields): #t = code
; evaluated in e (the new ops, whose args may open with a positional prefix),
; #f = data used as-is (new-from; keyword store only).
(def %instantiate
  (fn (_ class inits e eval?)
    ; fields (the %all-fields template) and the positional ctor order both
    ; come from the class's hot record -- computed once per table build, not
    ; re-walked per construction.
    (let ((hot (%class-hot class)))
      (let ((fields (first (rest (rest hot)))))
        (let ((store (if eval?
                       (%positional->store inits (first (rest (rest (rest hot)))) fields class)
                       inits)))
          (%check-init-keys store fields class)
          (let ((inst (%make-instance %object
                        (list class (%init-fields fields store e eval?)))))
            ; %init protocol hook (the initialize slot): a class's %init
            ; method, if any, runs once the fields are built -- construction
            ; logic beyond plain field values. Resolved through the flat
            ; table, so a child's override wins and (super self %init)
            ; chains as usual. Fires on every construction door (new,
            ; class-dispatch new, new-from).
            (let ((itab (first hot)))
              (let ((m (%entry-inner (%tab-find! itab itab (lit %init)))))
                (unless (if (null? m) #t (eq? m %field-tag))
                  (apply m (list inst)))))
            inst))))))

(note "Dispatch handlers")

; Instance dispatch: resolve the selector in the class's flat table -- ONE
; walk decides method vs field vs miss (a field read no longer pays a full
; method-chain miss first). A method entry is re-driven through tail-eval:
; the closure self-evaluates as head, the instance self-evaluates in arg
; position, and C evaluates the raw arg forms once in the caller's env --
; no per-arg eval closure, no apply save/restore. (Stack semantics are the
; trampoline's, unchanged: the old apply path already rode it -- measured,
; both dispatches complete a 30k-deep method recursion.)
; A table miss still consults the instance's own fields: set-member! can
; add an undeclared key to ONE instance, which the class-wide table cannot
; know about. NOTE: `rest` is the caller's raw form tail and is often a
; C-BUILT STRUCTURAL SPINE (method bodies are), for which pair? answers #f
; -- never pair?-test it; a dotted tail surfaces through %map1's improper-
; list guard exactly as it always did.
(def %object-dispatch
  (op (self sel-raw . args) e
    (let ((selector (%selector sel-raw))
          (itab (first (%class-hot (%obj-class self)))))
      (let ((entry (%tab-find! itab itab selector)))
        (match
          ((eq? entry %field-tag)
            (match
              ((null? args) (%assoc-get selector (%obj-fields self)))
              (#t (%box-put! (%obj-box self) selector (eval (first args) e)))))
          ((not (null? entry))
            (if (pair? entry)                          ; privacy wrapper
              (%priv-entry self (%obj-class self) entry selector args e #f)
              (tail-eval (pair entry (pair self args)) e)))
          ((%assoc-has? selector (%obj-fields self))   ; ad-hoc instance key
            (match
              ((null? args) (%assoc-get selector (%obj-fields self)))
              (#t (%box-put! (%obj-box self) selector (eval (first args) e)))))
          (#t (%dispatch-miss self (%obj-class self) selector args e #f)))))))

; The de-dispatch door (#332): resolve a method ONCE and call it inside
; a hot loop with self as argument 0.  A stored method is a plain fn
; closure and is APPLICATIVE at direct call -- args evaluate exactly
; once (verified: procedure call evaluates the arg list before the
; WRAP-flag branch).  Callers must NOT (wrap ...) the handle: that adds
; a SECOND evaluation pass over the already-evaluated values -- wasted
; work for self-evaluating values, a re-resolution bug for symbols.
; Resolution goes through the flat table, so it is chain-aware (a
; subclass override keeps winning); the traversals in protocol/seq.x
; are the canonical
; users -- (self done? ...) per ELEMENT paid a selector, a chain walk,
; an arg-list allocation and an apply, per element, per traversal.
(doc (def method-of
  (fn (_ (param class CLASS "Class to resolve against")
       (param sel SYMBOL "Static-method selector"))
    (let ((stab (first (rest (%class-hot class)))))
      (%entry-method (%tab-find! stab stab sel)))))
  (returns CALLABLE "The resolved static method closure, or nil")
  (note "The sanctioned de-dispatch door: resolve once, call directly in the hot")
  (note "loop with the class as argument 0 -- ((method-of C 'step) C cur v).")
  (note "Do NOT (wrap ...) the handle; a stored method already evaluates its")
  (note "args exactly once at direct call.")
  (see method-ref)
  "Resolve a static method to a bare closure for hot-loop direct calls.")

(def %class-method-of method-of)   ; historical internal name, same door

(def %class-statics-box (fn (_ class) (%assoc-get (lit statics) (%class-data class))))
(def %class-statics     (fn (_ class) (first (%class-statics-box class))))

; Class dispatch: one flat-table walk decides static method vs class-wide
; member vs the new builtin -- the same tail-eval re-drive as instance
; dispatch. A static METHOD named new is in the table and shadows the
; builtin (as always); a static MEMBER named new was dropped at flatten,
; so the builtin still wins there (as always).
(def %class-dispatch
  (op (self sel-raw . args) e
    (let ((selector (%selector sel-raw))
          (stab (first (rest (%class-hot self)))))
      (let ((entry (%tab-find! stab stab selector)))
        (match
          ((eq? entry %field-tag)                     ; own static member
            (match
              ((null? args) (%assoc-get selector (%class-statics self)))
              (#t (%box-put! (%class-statics-box self) selector (eval (first args) e)))))
          ((if (pair? entry) (eq? (first entry) %field-tag) #f)
            ; inherited static member: reads go to the owning ancestor's box
            ; (nearest wins, matching help's display); a write SHADOWS into
            ; our own box -- the parent's value is never mutated through a
            ; child; spell a deliberate parent write (Parent name v). The
            ; shadow invalidates every hot table: descendants' markers may
            ; point past this class.
            (match
              ((null? args) (%assoc-get selector (%class-statics (rest entry))))
              (#t
                (let ((v (eval (first args) e)))
                  (%box-put! (%class-statics-box self) selector v)
                  (%classes-invalidate!)
                  v))))
          ((not (null? entry))
            (if (pair? entry)                              ; privacy wrapper
              (%priv-entry self self entry selector args e #t)
              (tail-eval (pair entry (pair self args)) e)))
          ((eq? selector (lit new))                   ; (Class new k v ...): values are code
            (%instantiate self args e #t))
          ; Runtime method addition -- the open-class doors. Built-ins like
          ; `new`: a static method of the same name shadows them (checked
          ; above via the table). sel and fn are ordinary evaluated args, so
          ; selectors can be computed (a runtime-defined command language
          ; needs exactly that). The fn is stored AS-IS -- no super/member
          ; injection; it receives (self . args) and uses (self f) access.
          ; The cold alist is mutated (single source of truth: help and
          ; introspection see the addition immediately) and every hot table
          ; clears -- descendants must refold to see it.
          ((eq? selector (lit def-method!))
            (%class-add! self (lit methods) (eval (first args) e) (eval (first (rest args)) e)))
          ((eq? selector (lit def-static!))
            (%class-add! self (lit s-methods) (eval (first args) e) (eval (first (rest args)) e)))
          (#t (%dispatch-miss self self selector args e #t)))))))

; --- Value-to-class call dispatch ---
; Build a TYPE call handler so an instance, called as (inst method . args),
; dispatches to a bound CLASS's static method with the instance as the LAST
; positional argument -- the SUBJECT-LAST convention that matches the library's
; Ramda-style data-last methods. So (1/2 numerator) -> (Rational numerator 1/2),
; ("a,b,c" split ",") -> (Str8 split "," "a,b,c"), (lst map f) -> (List map f
; lst). Commutative ops read naturally ((1/2 + 1/3) -> (Rational + 1/3 1/2) ->
; 5/6); non-commutative ones are subject-last too (use the prefix (- a b) form).
; Install via type-push-call: (%type-push-call (%type-by-atom %rational)
; (%class-call-handler Rational)). An `op` (not fn) so the method selector stays
; unevaluated while the remaining args evaluate in the caller's env.
; Data-form echo for the non-selector paths below (#69 ruled: a non-callable
; head was never a call, so DATA IN, DATA OUT). Evaluates each element of the
; proper prefix -- self-evaluating data is identity, and x_prim_iter's
; re-evaluation path needs exactly that -- and a DOTTED tail is evaluated and
; preserved in place, so (1 . 2) echoes unchanged just like (1 2 3) does.
; %map1 cannot be used here: its improper-list guard (#51) is right for a
; real map over a list argument, but this walk reproduces a FORM, and a
; dotted form is data here, not an error.
(def %data-echo
  (fn (self f xs)
    (match
      ((null? xs) ())
      ((not (pair? xs)) (f xs))
      (#t (pair (f (first xs)) (self f (rest xs)))))))

(def %class-call-handler
  (fn (_ class)
    (op (obj . args) e
      ; A method call has a SYMBOL selector as its first arg ((1/2 numerator)).
      ; Anything else is a data list whose head happens to be a value of this
      ; type, re-evaluated as a call -- (1/2 1/3), or a bare (1) -- where dispatch
      ; must NOT fire; reproduce the data form so the list passes through
      ; unchanged, exactly as a non-callable head would. (x_prim_iter
      ; re-evaluates the list it iterates, which is why this path exists.)
      ; args can be a bare ATOM -- (1 . 2) binds args to 2 via the dotted
      ; spec -- so the pair? test comes BEFORE any first/rest touches it
      ; (#69: (first args) on the atom was the crash).
      (if (null? args)
        (list obj)
        (if (not (pair? args))
          (pair obj (eval args e))
          (let ((sel (%selector (first args))))
            (if (symbol? sel)
              ; Static-method resolve via the flat table; a static-member
              ; marker is not callable here (same miss as before). The call
              ; is re-driven through tail-eval: raw arg forms evaluate once
              ; in the caller's env, and the receiver rides LAST, spliced as
              ; (lit obj) so a list-valued subject is data, never a call.
              (let ((stab (first (rest (%class-hot class)))))
                (let ((m (%entry-method (%tab-find! stab stab sel))))
                  (if (null? m)
                    (error (%str-append "object: no such method " (symbol->str sel)))
                    (tail-eval
                      (pair m (pair class (%append (rest args) (list (list (lit lit) obj)))))
                      e))))
              (pair obj (%data-echo (fn (_ a) (eval a e)) args)))))))))

; Variant for types that ALREADY have a call handler (indexing/matching): a
; SYMBOL selector dispatches to the class method (subject-LAST, as above);
; anything else DELEGATES to the PRIOR handler (captured at install), so the
; existing call form keeps working. So a string gets both ("hi" split ",")
; (method) and ("hi" 0) (code point); a vector both (v ->list) and (v 0).
; Install with %bind-call-over! (below), which captures the current top handler
; before pushing this one.
(def %class-call-handler-over
  (fn (_ class prior)
    (op (obj . args) e
      ; Same atom-tail guard as %class-call-handler (#69): a dotted form
      ; binds args to a bare atom, which no prior handler can index into
      ; either -- echo it as data rather than delegating.
      (if (null? args)
        (apply prior (list obj))
        (if (not (pair? args))
          (pair obj (eval args e))
          (let ((sel (%selector (first args))))
            (if (symbol? sel)
              ; Static-method resolve via the flat table; a static-member
              ; marker is not callable here (same miss as before). The call
              ; is re-driven through tail-eval: raw arg forms evaluate once
              ; in the caller's env, and the receiver rides LAST, spliced as
              ; (lit obj) so a list-valued subject is data, never a call.
              (let ((stab (first (rest (%class-hot class)))))
                (let ((m (%entry-method (%tab-find! stab stab sel))))
                  (if (null? m)
                    (error (%str-append "object: no such method " (symbol->str sel)))
                    (tail-eval
                      (pair m (pair class (%append (rest args) (list (list (lit lit) obj)))))
                      e))))
              (apply prior (pair obj (%data-echo (fn (_ a) (eval a e)) args))))))))))

; Install value-to-class method dispatch OVER a type's existing call handler:
; symbol selector -> the class's static method (subject-last); anything else
; falls through to whatever the type's call slot did before.
(def %bind-call-over!
  (fn (_ type-handle class)
    (let ((ts (%type-by-atom type-handle)))
      (%type-push-call ts (%class-call-handler-over class (%type-call-top ts))))))

(note "Write handlers")

(def %write-fields
  (fn (loop al)
    (if (not (null? al))
      (do
        (display " " (first (first al)) "=")
        (write (rest (first al)))
        (loop (rest al))))))

; An object's write/display ops are not standalone globals -- they live ON the
; type (below) and ask the INSTANCE to render itself: the type / class / instance
; triad, no global print function. %write-fields above is the default dump's
; field walker.
;   write   -> a class's %repr method (returning a string) controls inspection;
;              otherwise the type's default #<Class field=val ...> dump.
;   display -> a class's %str method (returning a string) gives a human-readable
;              form (e.g. a Grid's ASCII art); otherwise it falls back to write,
;              so a class with only %repr prints the same for both (as before).
; This mirrors Python's __repr__/__str__. The `%` marks both as runtime-invoked
; protocol hooks, not everyday methods -- the convention used throughout the lib.

(def %class-write
  (fn (_ self)
    (display "#<class " (class-name self) ">")))

; Default dump for a class that defines no %repr.
(def %object-default-write
  (fn (_ self)
    (display "#<" (class-name self))
    (%write-fields (%obj-fields self))
    (display ">")))

(def %object-write
  (fn (_ self)
    (if (null? (%lookup (%obj-class self) (lit methods) (lit %repr)))
      (%object-default-write self)
      (display (self %repr)))))

(def %object-display
  (fn (_ self)
    (if (null? (%lookup (%obj-class self) (lit methods) (lit %str)))
      (%object-write self)
      (display (self %str)))))

(def %object
  (%make-type "OBJECT"
    (list
      (pair (lit call) %object-dispatch)
      (pair (lit write) %object-write)
      (pair (lit display) %object-display))))
(def %class  (%make-type "CLASS"  (list (pair (lit call) %class-dispatch)  (pair (lit write) %class-write))))

(note "Inheritance")

(doc (def super
  (op (self-expr sel-raw . args) e
    (let ((inst (eval self-expr e)) (selector (%selector sel-raw)))
      (if (not (object? inst))
        (error "object: super works only inside an instance method")
        ; The parent comes from %this-class -- the box every method body
        ; binds to its DEFINING class -- so super resolves to the right
        ; level even when the method is inherited by a deeper subclass:
        ; no self-recursion.
        ; Resolution goes through the parent's flat itab (chain-merged, so a
        ; grandparent method is found exactly as the old chain walk did); a
        ; field marker is not a method. tail-eval re-drives the call: raw
        ; arg forms evaluate once, with no per-arg eval closure or apply.
        (let ((sc (let ((b (eval (lit %this-class) e)))
                    (if (null? b) () (class-parent (first b))))))
          (let ((method (if (null? sc) ()
                          (let ((itab (first (%class-hot sc))))
                            (%tab-find! itab itab selector)))))
            (if (if (null? method) #t (eq? method %field-tag))
              (error "object: super has no parent method")
              (tail-eval (pair method (pair inst args)) e))))))))
  (note "Selector is literal: (super self method args...). Instance methods only.")
  (note "Resolves from the parent of the method's DEFINING class, so it is correct")
  (note "through multi-level inheritance.")
  (sample "(super self total)" "the parent total method's result")
  (see def-class)
  "Invoke the parent class's version of a method.")

; method-ref: turn a method into a first-class function value -- the complement
; of a bare (Target sel ...) call. (method-ref Target sel) evaluates Target (a
; class or instance) and the literal selector sel, and returns a closure that,
; when applied, re-drives the normal dispatch: (Target sel . args). It does NOT
; introspect the method tables -- it just defers the call -- so it works for
; static methods, instance methods, and members uniformly, with any arity.
;   (%map (method-ref Str upcase) lst)
;   (regex-replace rx s (method-ref Str upcase))
; Each captured value (target, selector, and every applied arg) is spliced as a
; (lit V) literal so the rebuilt call dispatches on the values, not re-evaluation.
(doc (def method-ref
  (op (target-expr sel) e
    (let ((target (eval target-expr e)))
      (fn (_ . args)
        ; Late-bound by contract: resolve per call (so a rebuilt table is
        ; honoured), but through the flat tables -- a method hit applies the
        ; closure directly on the already-evaluated args, no form rebuild.
        ; A member (field marker) or non-class target falls back to driving
        ; the normal dispatch form, values spliced as (lit V) literals so
        ; nothing re-evaluates.
        (let ((entry
                (%entry-method
                  (if (class? target)
                    (let ((stab (first (rest (%class-hot target)))))
                      (%tab-find! stab stab sel))
                    (if (object? target)
                      (let ((itab (first (%class-hot (%obj-class target)))))
                        (%tab-find! itab itab sel))
                      ())))))
          (if (null? entry)
            (eval
              (pair (list (lit lit) target)
                (pair (list (lit lit) sel)
                  (%map1 (fn (_ a) (list (lit lit) a)) args)))
              e)
            (apply entry (pair target args))))))))
  (note "Selector is literal: (method-ref Class method). Works for static and instance methods.")
  (example "(List map (method-ref Str upcase) (list \"a\" \"b\"))" "(\"A\" \"B\")")
  (see def-class)
  "Make a class/instance method usable as a first-class function value.")

(note "Predicates and introspection")

(doc (def object? (fn (_ (param x ANY "Value to test")) (%type? x %object)))
  (returns BOOL "True if x is an object instance")
  (see class?)
  "Test whether a value is an object instance.")

(doc (def class? (fn (_ (param x ANY "Value to test")) (%type? x %class)))
  (returns BOOL "True if x is a class")
  (see object?)
  "Test whether a value is a class.")

(doc (def class-of
  (fn (_ (param inst OBJECT "Instance"))
    (if (object? inst) (%obj-class inst) (error "class-of: not an instance"))))
  (returns CLASS "The class an instance belongs to")
  (see class-name)
  "Return the class an instance belongs to (itself a callable class object).")

(doc (def class-name
  (fn (_ (param x ANY "An instance or a class"))
    (%assoc-get (lit name) (%class-data (if (class? x) x (%obj-class x))))))
  (returns SYMBOL "The class name")
  (see class-of)
  "Return the name symbol of a class, or of an instance's class.")

(doc (def class-parent
  (fn (_ (param c CLASS "A class"))
    (%assoc-get (lit parent) (%class-data c))))
  (returns CLASS "The parent class, or nil for a root class")
  (see class-name)
  "Return a class's parent class (the one it extends), or nil if it has none.")

(def %class-ancestor?
  (fn (loop c target)
    (if (null? c)
      #f
      (if (same? c target)                 ; class identity, not value equality
        #t
        (loop (%assoc-get (lit parent) (%class-data c)) target)))))

(doc (def instance-of?
  (fn (_ (param inst OBJECT "Instance") (param class CLASS "Class"))
    (%class-ancestor? (%obj-class inst) class)))
  (returns BOOL "True if inst is a class or one of its subclasses")
  (see object?)
  "Test whether an instance belongs to a class or any of its descendants.")

(note "Introspection -- member/method names (own, not inherited), used by help")

(doc (def class-members
  (fn (_ (param c CLASS "A class")) (%assoc-keys (%assoc-get (lit fields) (%class-data c)))))
  (returns LIST "This class's own instance-member names")
  (see class-methods)
  "List a class's own instance member names (not inherited).")

(doc (def class-methods
  (fn (_ (param c CLASS "A class")) (%assoc-keys (%assoc-get (lit methods) (%class-data c)))))
  (returns LIST "This class's own instance-method names")
  (see class-members)
  "List a class's own instance method names (not inherited).")

(doc (def class-static-members
  (fn (_ (param c CLASS "A class")) (%assoc-keys (%class-statics c))))
  (returns LIST "This class's own static-member names")
  (see class-static-methods)
  "List a class's own static (class-wide) member names (not inherited).")

(doc (def class-static-methods
  (fn (_ (param c CLASS "A class")) (%assoc-keys (%assoc-get (lit s-methods) (%class-data c)))))
  (returns LIST "This class's own static-method names")
  (see class-static-members)
  "List a class's own static method names (not inherited).")

(note "Class definition")

(def %make-class
  (fn (_ name fields methods parent s-methods statics interface ivis svis)
    (%make-instance %class
      (list
        (pair (lit name) name)
        (pair (lit fields) fields)
        (pair (lit methods) methods)
        (pair (lit parent) parent)
        (pair (lit s-methods) s-methods)
        (pair (lit interface) interface)           ; declared (interface ...) names, or ()
        (pair (lit ivis) ivis)                     ; instance-side (name . private|protected)
        (pair (lit svis) svis)                     ; static-side visibility alist
        (pair (lit statics) (list statics))))))   ; statics in a one-cell mutable box

; Find a top-level body form whose head is `tag`, returning its rest (or ()).
; Find the (tag ...) form in a class body, returning its tail (or () if absent).
; pair?-guarded: a bare-symbol member (links, north, ...) is not a tagged form,
; and an unchecked (first symbol) is silently wrong on 64-bit / a SIGSEGV on the
; 32-bit Pi -- so skip non-pairs instead of reading their car. (cf. %find-doc-form)
(def %find-form
  (fn (loop body tag)
    (unless (null? body)
      (if (if (pair? (first body)) (eq? (first (first body)) tag) #f)
        (rest (first body))
        (loop (rest body) tag)))))

; --- Method documentation ---
; A method may carry an optional leading (doc "desc" (param ...) (returns ...)
; (example ...) ...) as its FIRST body form, and annotate its parameters inline:
;   (method upcase (self (param s STRING "the string"))
;     (doc "Uppercase ASCII" (returns STRING "uppercased"))
;     BODY...)
; The doc is registered under the symbol  Class/method  (e.g. Str8/upcase) so
; (help Class method) finds it. The (doc ...) form and inline (param ...) are
; stripped before the method closure is built. We stash a %bare pending entry
; on the shared doc pipeline (same path the top-level `doc` op uses), so it
; rides the normal lazy %doc-commit! -- no new registry machinery.

; #t if the first body form is a (doc ...) clause.
(def %method-has-doc?
  (fn (_ form)
    (let ((body (rest (rest (rest form)))))
      (if (null? body) #f
        (if (pair? (first body)) (eq? (first (first body)) (lit doc)) #f)))))

; Compose the doc key symbol: Class/method.
(def %method-doc-key
  (fn (_ class-name method-name)
    (%str->symbol (%str-append (symbol->str class-name)
                   (%str-append "/" (symbol->str method-name))))))

; Stash a method's (doc "desc" meta...) as a %bare pending entry. The doc clause
; is (doc DESC META...); DESC may be absent. Inline (param ...) forms from the
; signature are appended to the meta so help shows the parameters too.
(def %stash-method-doc!
  (fn (_ class-name form)
    (let ((mname (first (rest form)))
          (sig   (first (rest (rest form))))
          (dform (first (rest (rest (rest form))))))   ; (doc DESC meta...)
      (let ((dargs (rest dform)))
        ; description = leading string (or ""); meta = the rest + inline params
        (let ((desc (if (null? dargs) ""
                      (if (str? (first dargs)) (first dargs) "")))
              (meta (unless (null? dargs)
                      (if (str? (first dargs)) (rest dargs) dargs))))
          (%set-first! %doc-pending-cell
            (pair (pair (lit %bare)
                     (pair (%method-doc-key class-name mname)
                           (pair desc (%append2 meta (%sig-params sig)))))
                  (first %doc-pending-cell))))))))

; A class body holds two kinds of (doc ...) form, told apart by the first element
; after `doc`: a STRING is the class summary (doc "..." meta...); a symbol or a
; (NAME default) declaration is a member's doc (doc NAME "..." meta...). Members
; thus carry NO positional description -- documentation always decorates, exactly
; like the top-level `doc` op wraps a (def ...). pair?-guarded so a bare-symbol
; member (links, north, ...) never reaches an unchecked (first symbol) -- which
; is silently wrong on 64-bit and a crash on the 32-bit Pi.
(def %doc-form?
  (fn (_ f) (if (pair? f) (eq? (first f) (lit doc)) #f)))
(def %class-doc-form?
  (fn (_ f)
    (if (%doc-form? f)
      (if (null? (rest f)) #f (str? (first (rest f))))
      #f)))
(def %member-doc-form?
  (fn (_ f)
    (if (%doc-form? f)
      (if (null? (rest f)) #f (not (str? (first (rest f)))))
      #f)))

; Stash a member's doc from its (doc DECL "desc" meta...) form, keyed Class/NAME
; (same namespace as methods; a same-named method shadows it, matching dispatch).
; DESC may be absent; meta (see/example/...) rides through like a method's doc.
(def %stash-member-doc!
  (fn (_ class-name member-name dform)
    (let ((dargs (rest (rest dform))))               ; skip `doc` and the DECL
      (let ((desc (if (null? dargs) "" (if (str? (first dargs)) (first dargs) "")))
            (meta (unless (null? dargs) (if (str? (first dargs)) (rest dargs) dargs))))
        (%set-first! %doc-pending-cell
          (pair (pair (lit %bare)
                   (pair (%method-doc-key class-name member-name)
                         (pair desc meta)))
                (first %doc-pending-cell)))))))

; The class-level (doc "desc" meta...) form in a class body, or () if absent.
(def %find-doc-form
  (fn (_ body) (%find %class-doc-form? body)))

; Stash a class-level (doc "desc" meta...) under the bare class name, so
; (help Class) shows a summary above the member/method sections. DESC may be
; absent; meta (note/see/example) rides through like a method's doc.
(def %stash-class-doc!
  (fn (_ class-name dform)
    (let ((dargs (rest dform)))
      (let ((desc (if (null? dargs) "" (if (str? (first dargs)) (first dargs) "")))
            (meta (unless (null? dargs) (if (str? (first dargs)) (rest dargs) dargs))))
        (%set-first! %doc-pending-cell
          (pair (pair (lit %bare) (pair class-name (pair desc meta)))
                (first %doc-pending-cell)))))))

; Extract the inline (param ...) forms from a method signature (self . params).
; A variadic tail is written dotted -- (self . (param args ...)) or
; (self k . (param rest ...)) -- so the (param ...) form can arrive as `sig`
; itself (the improper tail), not only as a list element; collect it either way.
(def %sig-params
  (fn (loop sig)
    (unless (null? sig)
      (when (pair? sig)
        (if (eq? (first sig) (lit param))
          (list sig)                                   ; dotted (param ...) tail
          (if (if (pair? (first sig)) (eq? (first (first sig)) (lit param)) #f)
            (pair (first sig) (loop (rest sig)))
            (loop (rest sig))))))))

; Strip inline (param name TYPE "desc") annotations from a signature, leaving
; the bare parameter names the fn closure needs.
(def %strip-sig-params
  (fn (loop sig)
    (unless (null? sig)
      (if (pair? sig)
        ; A dotted (param ...) tail arrives as `sig` itself (e.g. the rest in
        ; (self . (param args ...))); strip it to its NAME as the improper tail
        ; so the fn keeps its variadic arg, rather than splicing param/TYPE/desc
        ; in as extra fixed parameters.
        (if (eq? (first sig) (lit param))
          (first (rest sig))              ; dotted (param NAME ...) tail -> NAME
          (pair
            (if (if (pair? (first sig)) (eq? (first (first sig)) (lit param)) #f)
              (first (rest (first sig)))    ; (param NAME ...) -> NAME
              (first sig))
            (loop (rest sig))))
        sig))))   ; dotted-rest tail passes through

; Build a method closure from (NAME (self . params) body...). The body is
; wrapped in a let binding %this-class -- a one-cell box def-class fills
; with the class object once it exists (methods are built BEFORE the class;
; the box breaks the cycle). super reads the defining class's parent from
; it; the privacy check reads the caller's class from it. For instance
; methods (raw? true) the raw member/set-member! accessors ride the same
; let. A leading (doc ...) body form and inline (param ...) signature
; annotations are stripped here (their registration happens in
; %collect-methods). The box is spliced as (lit BOX): a raw pair in value
; position would evaluate as a form.
(def %make-method
  (fn (_ form raw? tbox e)
    (let ((sig  (%strip-sig-params (first (rest (rest form)))))
          (body (if (%method-has-doc? form)
                  (rest (rest (rest (rest form))))     ; drop leading (doc ...)
                  (rest (rest (rest form))))))
      (eval
        (list (lit fn)
          (pair (lit recur) sig)                       ; (recur . user-params)
          (pair (lit let)
            (pair (pair (list (lit %this-class) (list (lit lit) tbox))
                    (when raw? %method-raw-bindings))
                  body)))
        e))))

; Collect the (method ...) forms in `forms` into a methods alist. raw? injects the
; raw accessors (instance methods); parent is the defining class's parent (for
; super). class-name keys any per-method docs. Registers a doc entry for each
; documented method as a side effect.
(def %collect-methods
  (fn (loop class-name forms raw? tbox e)
    (unless (null? forms)
      ; Guard the head test: a bare member name is a SYMBOL, and first on a
      ; non-pair is unchecked -- (first 'x) yields the name buffer as an
      ; "object", so the eq? below would read past a 2-byte allocation
      ; (ASan heap-buffer-overflow; the 32-bit/Pi segfault class).
      (if (if (pair? (first forms)) (eq? (first (first forms)) (lit method)) #f)
        (do
          (when (%method-has-doc? (first forms))
            (%stash-method-doc! class-name (first forms)))
          (pair (pair (first (rest (first forms)))
                      (%make-method (first forms) raw? tbox e))
                (loop class-name (rest forms) raw? tbox e)))
        (loop class-name (rest forms) raw? tbox e)))))

; A member declaration is  NAME  |  (NAME default).  Its doc, if any, comes from
; a separate (doc DECL "desc" meta...) form (see %member-doc-form? above), so a
; member never carries a description positionally.
(def %member-name (fn (_ form) (if (pair? form) (first form) form)))
(def %member-value
  (fn (_ form e)
    (when (if (pair? form) (not (null? (rest form))) #f)
      (eval (first (rest form)) e))))                                          ; bare name / (NAME) -> nil default

; Instance-member default: the EXPRESSION wrapped as a nullary closure over the
; defining env, so %init-fields evaluates it once PER CONSTRUCTION -- a mutable
; default like (links (Set make)) is fresh for every instance, never shared.
; Statics keep %member-value's once-at-definition evaluation: they ARE the
; class-wide shared state.
(def %member-default-thunk
  (fn (_ form e)
    (when (if (pair? form) (not (null? (rest form))) #f)
      (eval (list (lit fn) (list (lit _)) (first (rest form))) e))))

; The member declaration a body form carries: the form itself, or -- for a
; member-doc form (doc DECL ...) -- the wrapped DECL.
(def %member-decl
  (fn (_ f) (if (%member-doc-form? f) (first (rest f)) f)))

; Collect member declarations from `forms` into a (name . value) alist, skipping
; (method ...), (static ...), and the class summary (doc "..."). A member-doc
; form (doc DECL "desc" ...) declares its member AND registers the doc.
; thunk? selects the default representation: #t (instance members) stores the
; default as a per-construction thunk; #f (statics) evaluates it here, once.
(def %collect-members
  (fn (loop class-name forms e thunk?)
    (unless (null? forms)
      (let ((f (first forms)))
        (if (if (pair? f)
              (if (eq? (first f) (lit method)) #t
                (if (eq? (first f) (lit static)) #t
                  (if (eq? (first f) (lit interface)) #t
                    (if (eq? (first f) (lit with)) #t
                      (if (eq? (first f) (lit delegates)) #t
                        (%class-doc-form? f))))))    ; skip methods/statics/interface/with/delegates/class doc
              #f)
          (loop class-name (rest forms) e thunk?)
          (let ((decl (%member-decl f)))
            (when (%member-doc-form? f)
              (%stash-member-doc! class-name (%member-name decl) f))
            (pair (pair (%member-name decl)
                    (if thunk? (%member-default-thunk decl e) (%member-value decl e)))
                  (loop class-name (rest forms) e thunk?))))))))

(def %resolve-parent
  (fn (_ parent e)
    (unless (null? parent)
      (do
        ; The documented parent slot is () or (extends Class) (see the
        ; def-class doc).  Anything else -- a bare (Parent) list, a bare
        ; symbol, (extends) with no class -- used to reach (first ())
        ; through the UNCHECKED C first and segfault at class-def time;
        ; refuse loudly instead.
        (unless (if (pair? parent)
                  (if (eq? (first parent) (lit extends))
                    (pair? (rest parent)) #f)
                  #f)
          (error "def-class: parents are declared () or (extends Class)"))
        (eval (first (rest parent)) e)))))

; A body form is a member NAME (symbol), or a list headed by a symbol --
; (method ...), (static ...), or a (NAME value ...) member declaration.
(def %valid-head?
  (fn (_ form)
    (if (symbol? form) #t
      (if (pair? form) (symbol? (first form)) #f))))

(def %validate-body
  (fn (loop body)
    (unless (null? body)
      (do
        (let ((f (first body)))
          (if (if (pair? f) (eq? (first f) (lit fields)) #f)
            (error "def-class: the (fields ...) wrapper was removed -- declare members directly, e.g. (def-class C () x y (method m (self) ...))")
            (unless (%valid-head? f)
              (error "def-class: invalid body form -- expected a member name, (name value), (doc ...), (interface ...), (method ...), or (static ...)"))))
        (loop (rest body))))))

; --- Interface (contract) enforcement --------------------------------------
; A class declares the methods its concrete subclasses MUST provide:
;   (interface start done? step ...)
; Declaring an interface makes the class itself abstract. A CONCRETE subclass --
; one that declares no (interface ...) of its own -- is checked at def-class time:
; every method named in an ancestor's interface must have a concrete impl in the
; chain (a class that lists it among its methods but NOT in its own interface, so
; the declarer's abstract stub does not count). A miss errors at definition, not
; cryptically at call time. Classes with no interface in their chain are untouched.

(def %class-interface (fn (_ c) (%assoc-get (lit interface) (%class-data c))))


; m is among c's OWN methods -- instance OR static (the string protocol's
; primitives are static; instance-based interfaces use instance methods).
(def %defines?
  (fn (_ c m)
    (if (%memq? m (%assoc-keys (%assoc-get (lit methods) (%class-data c)))) #t
      (%memq? m (%assoc-keys (%assoc-get (lit s-methods) (%class-data c)))))))

; #t if c's chain provides a concrete impl of method m: some class defines m
; (instance or static) but does NOT list it in its own interface (so the abstract
; declarer's stub is excluded).
(def %implements?
  (fn (loop c m)
    (if (null? c) #f
      (if (if (%defines? c m) (not (%memq? m (%class-interface c))) #f)
        #t
        (loop (%assoc-get (lit parent) (%class-data c)) m)))))

(def %check-impls!
  (fn (loop cls reqs)
    (unless (null? reqs)
      (do
        (unless (%implements? cls (first reqs))
          (error (%str-append (symbol->str (class-name cls))
            (%str-append ": missing interface method " (symbol->str (first reqs))))))
        (loop cls (rest reqs))))))

(def %check-ancestors!
  (fn (loop cls anc)
    (unless (null? anc)
      (do
        (%check-impls! cls (%class-interface anc))
        (loop cls (%assoc-get (lit parent) (%class-data anc)))))))

(def %check-interface!
  (fn (_ cls)
    (when (null? (%class-interface cls))           ; concrete -> enforce inherited interface(s)
      (%check-ancestors! cls (%assoc-get (lit parent) (%class-data cls))))))                                      ; declares an interface -> abstract -> skip

; Resolve the parent once, validate the body, build the class object, and enforce
; any inherited interface. Kept out of the def-class op body so the op's tail
; stays the bare tail-eval (see below).
(def %build-class
  (fn (_ name parent body0 e)
    (do
      ; Explode (private ...) / (protected ...) declaration blocks: their
      ; tail forms splice in place and each declared name is recorded in a
      ; visibility alist for the flattener. Blocks work at the body top
      ; level (instance side) and inside (static ...); nesting the other
      ; way round is refused. LOCAL fns, mid-body on purpose (the
      ; %check-dups! pattern below).
      (def %block-vis
        (fn (_ f)
          (if (pair? f)
            (if (eq? (first f) (lit private)) (lit private)
              (if (eq? (first f) (lit protected)) (lit protected) ()))
            ())))
      (def %decl-name
        (fn (_ f)
          (if (if (pair? f) (eq? (first f) (lit method)) #f)
            (first (rest f))
            (%member-name (%member-decl f)))))
      (def %explode-vis                    ; forms -> (spliced-forms . vis-alist)
        (fn (loop fs)
          (match
            ((null? fs) (pair () ()))
            ((not (null? (%block-vis (first fs))))
              (let ((vis (%block-vis (first fs)))
                    (bodyf (rest (first fs)))
                    (outer (loop (rest fs))))
                (do
                  (%map (fn (_ f)
                          (when (if (pair? f) (eq? (first f) (lit static)) #f)
                            (error "def-class: declare (private ...) inside (static ...), not the reverse")))
                    bodyf)
                  (pair (%append2 bodyf (first outer))
                        (%append2 (%map (fn (_ f) (pair (%decl-name f) vis)) bodyf)
                                  (rest outer))))))
            (#t
              (let ((outer (loop (rest fs))))
                (pair (pair (first fs) (first outer)) (rest outer)))))))
      (def %ix (%explode-vis body0))
      (def body (first %ix))
      (def ivis (rest %ix))
      (%validate-body body)
      ; A member name declared twice in ONE class body is always a mistake
      ; -- the common shape is a bare declaration beside its (doc NAME ...)
      ; form, which ALSO declares (see %collect-members).  The duplicate is
      ; silent poison: positional construction fills the doubled slot twice
      ; and a LATER member stays nil (found via (Type wrap ...): `raw`
      ; stayed nil and a downstream (first nil) segfaulted).  Subclass
      ; overrides are unaffected -- one body's own list only, never the
      ; chain.  LOCAL fns, mid-body on purpose: the file's %-global budget
      ; is spent, class building is cold, and a mid-body def is
      ; activation-scoped (only TAIL defs leak globally under TCO).
      (def %member-key?
        (fn (loop n ms)
          (if (null? ms) #f
            (if (eq? n (first (first ms))) #t (loop n (rest ms))))))
      (def %check-dups!
        (fn (loop ms)
          (unless (null? ms)
            (do
              (when (%member-key? (first (first ms)) (rest ms))
                (error (%str-append (symbol->str name)
                  (%str-append ": duplicate member "
                    (%str-append (symbol->str (first (first ms)))
                      " -- declared twice in one class body (a (doc NAME ...) form also declares)")))))
              (loop (rest ms))))))
      (let ((dform (%find-doc-form body)))           ; class-level (doc ...) -> doc registry
        (unless (null? dform) (%stash-class-doc! name dform)))
      (def %sx (%explode-vis (%find-form body (lit static))))
      ; Traits (x/type/trait): every (with T...) form's traits, in order.
      ; Their stored method FORMS build with the ordinary builder against
      ; THIS class's box -- super resolves on the host's chain -- in the
      ; TRAIT's captured env, so the body's free names resolve where the
      ; trait was written. Contributions append AFTER own methods: the
      ; flattener's first-sight rule makes own > trait > inherited. Two
      ; traits supplying one selector with no own override refuse here,
      ; naming both. `delegates` forwarders ride the same append.
      (def %with-traits
        (fn (loop fs acc)
          (match
            ((null? fs) acc)
            ((if (pair? (first fs)) (eq? (first (first fs)) (lit with)) #f)
              (loop (rest fs)
                (%append2 acc
                  (%map (fn (_ tx)
                          (let ((t (eval tx e)))
                            ; the trait tag is a pair whose head is the
                            ; interned symbol %trait (trait.x's unforgeable
                            ; list); shape-checked here because the tag
                            ; value itself lives in a later-loading module
                            (if (if (pair? t)
                                  (if (pair? (first t)) (eq? (first (first t)) (lit %trait)) #f)
                                  #f)
                              t
                              (error "def-class: (with ...) takes trait values (see def-trait)"))))
                    (rest (first fs))))))
            (#t (loop (rest fs) acc)))))
      (def %trait-conflict!
        (fn (loop rows own seen)
          (unless (null? rows)
            (do
              (let ((sel (first (first rows))))
                (unless (%member-key? sel own)
                  (when (%member-key? sel seen)
                    (error (%str-append (symbol->str name)
                      (%str-append ": traits collide on "
                        (%str-append (symbol->str sel) " -- add an own override")))))))
              (loop (rest rows) own (pair (first rows) seen))))))
      (def %delegates-methods
        (fn (loop fs acc)
          (match
            ((null? fs) acc)
            ((if (pair? (first fs)) (eq? (first (first fs)) (lit delegates)) #f)
              (let ((acc2 (%append2 acc
                            (%map (fn (_ spec)
                                    (let ((theirs (if (pair? spec) (first spec) spec))
                                          (ours (if (pair? spec) (first (rest spec)) spec)))
                                      (pair ours
                                        (eval
                                          (list (lit fn)
                                            (pair (lit _) (pair (lit self) (lit args)))
                                            (list (lit %delegate-call)
                                              (list (lit self) (list (lit lit) (first (rest (first fs)))))
                                              (list (lit lit) theirs)
                                              (lit args)))
                                          e))))
                              (first (rest (rest (first fs))))))))
                (loop (rest fs) acc2)))
            (#t (loop (rest fs) acc)))))
      (let ((p (%resolve-parent parent e))
            (sblock (first %sx))
            (svis (rest %sx))
            (traits (%with-traits body ()))
            (tbox (list ())))                          ; %this-class box, filled below
        (let ((imems (%collect-members name body e #t))    ; instance members: per-construction defaults
              (smems (%collect-members name sblock e #f))) ; static members: once, class-wide
          (do
            (%check-dups! imems)
            (%check-dups! smems)
            (let ((own-im (%collect-methods name body #t tbox e))
                  (own-sm (%collect-methods name sblock #f tbox e))
                  (t-im (%fold (fn (_ acc t)
                                 (%append2 acc (%collect-methods name (first (rest (rest (rest t)))) #t tbox
                                                 (first (rest (rest (rest (rest (rest t)))))))))
                          () traits))
                  (t-sm (%fold (fn (_ acc t)
                                 (%append2 acc (%collect-methods name (first (rest (rest (rest (rest t))))) #f tbox
                                                 (first (rest (rest (rest (rest (rest t)))))))))
                          () traits)))
              (%trait-conflict! t-im own-im ())
              (%trait-conflict! t-sm own-sm ())
              (let ((cls (%make-class
                           name
                           imems
                           (%append2 own-im (%append2 t-im (%delegates-methods body ())))
                           p
                           (%append2 own-sm t-sm)
                           smems
                           (%find-form body (lit interface))          ; declared interface (or ())
                           ivis svis)))
                (%set-first! tbox cls)                             ; methods can now see their class
                (%check-interface! cls)                            ; error if a contract method is unmet
                ; Trait requirements: each (require SEL...) name needs a
                ; concrete definition somewhere on the chain (trait- and
                ; delegate-supplied methods are in the tables by now).
                (%for-each
                  (fn (_ t) (%check-impls! cls (first (rest (rest t)))))
                  traits)
                (%set-first! %class-registry (pair cls (first %class-registry)))
                cls))))))))

(doc (def def-class
  (op (name parent . body)
    e
    ; tail-eval must be the op's direct tail so the (def NAME ...) it runs persists
    ; in the caller's env even under (eval form env) (e.g. the spec harness), not
    ; only the REPL's eval!. %build-class does the work (validate, resolve, build).
    (tail-eval
      (list (lit def) name (list (lit lit) (%build-class name parent body e)))
      e)))
  (note "Names are literal (no quotes). Body forms (members and methods intermixed):")
  (note "  NAME | (NAME default)                    instance member (default optional, nil if omitted;")
  (note "                                           evaluated per construction, so (links (Set make)) is fresh each time)")
  (note "  (doc DECL \"desc\" meta..)                 document a member; DECL is NAME or (NAME default)")
  (note "  (method NAME (self . args) body...)      instance method")
  (note "  (static MEMBER... (method ...)...)       class-wide members + static methods")
  (note "  (interface NAME...)                      abstract: a concrete subclass must implement each NAME")
  (note "  (private DECL...) | (protected DECL...)  visibility blocks (members and methods; also inside (static ...)):")
  (note "                                           private = defining class's methods only; protected = its chain.")
  (note "                                           Enforced at the dispatch door; introspection and (help) still list them.")
  (note "  (doc \"summary\" (note ..) (see ..) (example ..))   class-level docs, shown by (help Class)")
  (note "A method shadows a member of the same name. Parent: () or (extends Class).")
  (note "Inside a method, (self m) accesses members; (member 'm)/(set-member! 'm v) are raw.")
  (note "A (method %init (self) ...) runs after every construction, fields built --")
  (note "the initialize hook; a child's override wins, (super self %init) chains.")
  (example "(do (def-class C () (static (n 7) (method get (self) (self n)))) (C get))" "7")
  (see new)
  "Define a class (a callable class object) with fields, methods, and statics.")

(doc (def new
  (op (class-expr . inits)
    e
    (%instantiate (eval class-expr e) inits e #t)))
  (note "Inline construction: member names are literal (bare, not quoted) and")
  (note "values are expressions, evaluated in the caller's env:")
  (note "  (new C name val name val ...)   plist form -- the usual one")
  (note "  (new C (name . val) ...)        dotted-alist form (val is an expression)")
  (note "  (new C v1 v2 ... name val ...)  positional prefix: values fill members in")
  (note "    constructor order (root ancestor's members first, then each subclass's own),")
  (note "    until the first bare declared-member name starts the keyword tail.")
  (note "A TRAILING bare member name is positional ((new Distances root) passes the root")
  (note "variable); the footgun: a NON-trailing positional value spelled as a bare member")
  (note "name (or a call headed by one) reads as the keyword tail -- use keywords there.")
  (note "For a computed/quoted store (a list of ready values) use new-from.")
  (example "(do (def-class P () x) ((new P x 5) x))" "5")
  (see new-from)
  "Construct an instance inline; names literal, values evaluated.")

(doc (def new-from
  (fn (_ (param class CLASS "The class to instantiate")
       (param store LIST "Ready-value store: alist ((k . v) ...) or plist (k v ...)"))
    (%instantiate class store () #f)))
  (note "Data counterpart to new: the store is evaluated (new-from is a fn) and its")
  (note "values are used as-is, not re-evaluated -- so pass a quoted list, a variable,")
  (note "or a built alist/plist.  Unknown keys fall back to declared defaults.")
  (example "(do (def-class P () x y) ((new-from P '(x 1 y 2)) x))" "1")
  (see new)
  "Instantiate a class from a computed option store (alist or plist) of values.")

; Reject entries from alist `al` whose name is already a key in `known`.
(def %reject-known
  (fn (loop al known)
    (unless (null? al)
      (if (%assoc-has? (first (first al)) known)
        (loop (rest al) known)
        (pair (first al) (loop (rest al) known))))))

; All instance members across the inheritance chain as a (name . default) alist;
; a member redefined in a subclass overrides the inherited one (child wins).
(def %all-fields
  (fn (loop class)
    (unless (null? class)
      (let ((own (%assoc-get (lit fields) (%class-data class))))
        (%append2 own
          (%reject-known (loop (%assoc-get (lit parent) (%class-data class))) own))))))

; Build the instance field box: each member takes its init value if supplied --
; from a flat plist `name val ...` OR an alist `((name . val) ...)` -- otherwise
; its declared default.  eval? selects how a supplied value is treated: #t (the
; (new ...) ops, whose values are code) evaluates it in caller env e; #f (new-from,
; whose store is data) uses it as-is.  An absent key (%opt-cell returns ()) falls
; back to the declared default -- a thunk over the defining env, called NOW, so
; a constructing default ((Set make), (list 1 2)) is fresh per instance while a
; quoted one ('(1 2)) is the one literal, exactly as quote means; null? on the
; box distinguishes a supplied 0/nil from a missing key.
(def %init-fields
  (fn (loop members inits e eval?)
    (unless (null? members)
      (let ((name (first (first members)))
            (default (rest (first members))))
        (let ((cell (%opt-cell name inits)))
          (pair (pair name
                  (if (null? cell)
                    (unless (null? default) (default))
                    (if eval? (eval (first cell) e) (first cell))))
                (loop (rest members) inits e eval?)))))))

(doc (provide x/type/class
  def-class new new-from super method-ref method-of
  object? class? class-of class-name class-parent instance-of?
  class-members class-methods class-static-members class-static-methods
  %class-call-handler %bind-call-over!)
  (note "Instances: (obj name args...) -- method wins, else member (obj m)/(obj m v).")
  (note "Classes are callable: (Class name args...) -- static method, (Class new ...) to")
  (note "instantiate, else class-wide member (Class m)/(Class m v). Use classes as")
  (note "namespaces of static methods. Raw member access in methods: (member 'm)/(set-member! 'm v).")
  (note "%class-call-handler / %bind-call-over! are the PUBLIC value-call extension hooks")
  (note "(the % marks handler-layer machinery, not module privacy): (%bind-call-over! (Type of v) Class)")
  (note "routes a value's symbol-selector calls to the class's statics, subject-LAST.")
  (example "(do (def-class P () x (method get (self) (self x))) ((new P x 5) get))" "5")
  "Object-oriented class system: classes-as-objects, message passing, single inheritance.")

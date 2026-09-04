; type/type.x -- Type: the type-system reflection API.
;
; The mechanism lives in lib/x/type/struct.x (pre-object, %-private) and is
; filed in the catalog under ns `type`, beside the C entries (make,
; make-instance, ?, of, name). This class presents it: reflection and
; wiring are cold operations, so every method fetches inline with
; (prim-ref ...) per the caching rule. Modules that wire types at load
; fetch-and-cache the helpers they use instead of calling the class:
;   (def %type-push-op (prim-ref (lit type) (lit push-op)))

(import x/type/class)

(def-class Type ()
  (doc "Type-system reflection: construction, lookup, struct navigation, and handler-stack wiring. (Type wrap t) clothes a handle or struct as an interactive instance: (t name), (t cell 'type-write-stack), (t push-write f)."
    (example "((Type wrap (Type of 0)) name)" "\"INTEGER\""))
  (doc handle "The type's handle atom -- the name atom (Type of) answers and the type-alist keys.")
  (doc raw "The raw type -- what the cell walkers and push-* wiring consume.")
  (method name (self)
    (doc "This type's registered name."
      (returns STRING "The name")
      (example "((Type wrap (Type of 0)) name)" "\"INTEGER\""))
    ((prim-ref (lit type) (lit name)) (self handle)))
  (method cell (self (param fname SYMBOL "A type field name -- see (Type fields)"))
    (doc "The object the layout contract's path addresses for fname, walked from this type's struct. A handler-stack cell's first slot is the handler list."
      (returns ANY "The addressed cell/object")
      (example "(null? ((Type wrap (Type of 0)) cell 'type-write-stack))" "#f"))
    (Type %layout-cell (self raw) fname (lit type)))
  (method fields (self)
    (doc "Every type field name from the layout contract."
      (returns LIST "Field name symbols, contract order"))
    (Type %layout-fields (lit type)))
  (method push-write (self (param f CALLABLE "Write handler (fn (_ obj) ...)"))
    (doc "Push a write handler onto this type's write stack (shadows the current one)." (returns ANY "nil"))
    ((prim-ref (lit type) (lit push-write)) (self raw) f))
  (method push-display (self (param f CALLABLE "Display handler"))
    (doc "Push a display handler onto this type's display stack." (returns ANY "nil"))
    ((prim-ref (lit type) (lit push-display)) (self raw) f))
  (method push-call (self (param f CALLABLE "Call handler (fn (_ obj . args) ...)"))
    (doc "Push a call handler onto this type's call stack (overrides how (obj ...) dispatches)." (returns ANY "nil"))
    ((prim-ref (lit type) (lit push-call)) (self raw) f))
  (method push-op (self (param op ATOM "Operator symbol, e.g. '+")
                        (param f CALLABLE "Binary handler (fn (_ a b) ...)"))
    (doc "Register a binary generic-operator handler on this type." (returns ANY "nil"))
    ((prim-ref (lit type) (lit push-op)) (self raw) op f))
  (method %repr (self)
    (doc "Inspection form: #<type:NAME>." (returns STRING "The repr string"))
    (Str8 append "#<type:"
      (Str8 append ((prim-ref (lit type) (lit name)) (self handle)) ">")))
  (static
    ; --- layout-contract walkers (shared: type/base.x calls these; homed
    ; here as %-statics per the percent-globals budget -- classes ARE
    ; namespaces).  Contract rows (engine/tools/contract/base-paths.x) are
    ; (name root step...).  Cell resolution REFUSES a name whose root
    ; walks a different shape: a type-rooted name stepped from a base (or
    ; vice versa) addresses arbitrary spine words, and a consumer
    ; mutating "its cell" would overwrite live interpreter state.
    (method %layout-entry (self fname paths)
      (doc "The contract row for fname, or nil." (returns ANY "The (name root step...) row"))
      (match
        ((null? paths) ())
        ((eq? (first (first paths)) fname) (first paths))
        (#t (recur self fname (rest paths)))))
    (method %layout-cell (self o fname root)
      (doc "The object addressed by fname's contract path, walked from o; errors unless the row's root is `root`."
        (returns ANY "The addressed cell/object"))
      (let ((e (Type %layout-entry fname %base-paths)))
        (match
          ((null? e) (error (pair (lit layout-cell-unknown-field) fname)))
          ((not (eq? (first (rest e)) root))
            (error (pair (lit layout-cell-wrong-root) fname)))
          (#t (%reflect-step o (rest (rest e)))))))
    (method %layout-fields (self root)
      (doc "Every contract field name whose row has root `root`, contract order."
        (returns LIST "Name symbols"))
      (def %go
        (fn (loop paths)
          (match
            ((null? paths) ())
            ((eq? (first (rest (first paths))) root)
              (pair (first (first paths)) (loop (rest paths))))
            (#t (loop (rest paths))))))
      (%go %base-paths))
    (method wrap (self (param t ANY "A type handle (from Type of) or the type itself (from Type by-atom)"))
      (doc "Clothe a type as a Type instance for interactive use."
        (returns OBJECT "The Type instance; handle/raw members hold both forms")
        (example "((Type wrap (Type of 0)) name)" "\"INTEGER\""))
      (match
        ((null? t) (error (lit type-wrap-nil)))
        ((eq? (%reflect-type-word t) %reflect-spair-tw)
          (let ((handle (%reflect-type-name-atom t)) (raw t))
            (new Type handle handle raw raw)))
        (#t
          (let ((handle t) (raw ((prim-ref (lit type) (lit by-atom)) t)))
            (new Type handle handle raw raw)))))
    (method %kind-code (self (param k SYMBOL "A unit kind"))
      (doc "The engine's numeric code for a unit kind." (returns INT "0..3"))
      (match
        ((eq? k (lit ref)) 0)
        ((eq? k (lit word)) 1)
        ((eq? k (lit bytes)) 2)
        ((eq? k (lit foreign)) 3)
        (#t (error (pair (lit type-shape-unknown-kind) k)))))
    (method %kind-mask (self (param kinds LIST "Unit kinds, unit 0 first"))
      (doc "Pack kinds into the engine's two-bits-per-unit mask."
        (returns INT "The mask"))
      (let ((%go
              (fn (loop ks acc scale)
                (if (null? ks)
                    acc
                    (loop (rest ks)
                          (+ acc (* scale (Type %kind-code (first ks))))
                          (* scale 4))))))
        (%go kinds 0 1)))
    (method set-shape! (self (param ts ANY "Type struct (from Type by-atom)")
                             (param n INT "Unit count -- fixed, or -k for the slot-0-counted convention")
                             (param kinds LIST "One kind per unit (ref word bytes foreign); the last repeats"))
      (doc "Declare what each of a type's units IS, not just how many there are. The collector traces `ref` units and leaves the rest alone -- which is what makes a unit holding bytes or a foreign address declarable at all, since the marker writes through any pointer it is handed."
        (note "A fixed count describes its own units; a count of -k describes k leading units plus the kind of the slot-0-counted payload that follows, so (Type set-shape! ts -1 '(word ref)) is the vector.")
        (returns ANY "The type struct")
        (example "(Type set-shape! (Type by-atom (Type of \"s\")) 1 '(bytes))" "<type>"))
      ((prim-ref (lit type) (lit set-shape!)) ts n (Type %kind-mask kinds)))
    (method fields (self)
      (doc "Every type field name in the layout contract (type-rooted rows of engine/tools/contract/base-paths.x)."
        (returns LIST "Field name symbols, contract order"))
      (Type %layout-fields (lit type)))
    (method cell (self (param ts ANY "Type struct (from Type by-atom)")
                       (param fname SYMBOL "A field name -- see (Type fields)"))
      (doc "The layout-contract cell for name, walked from struct ts. Refuses non-type-rooted names."
        (returns ANY "The addressed cell/object"))
      (Type %layout-cell ts fname (lit type)))
    (method make (self (param name STRING "Type name (e.g. \"POINT\")")
                       (param slots LIST "Handler alist: (call write display analyse read delimit iter ops from to ...)"))
      (doc "Create a new custom type with the given handler slots; the reader checks it before the built-ins."
        (returns ANY "The new type's handle atom"))
      ((prim-ref (lit type) (lit make)) name slots))
    (method make-instance (self (param ts ANY "Type handle (from Type make)")
                                (param value ANY "Instance payload"))
      (doc "Create an instance of a custom type wrapping VALUE."
        (returns ANY "The new instance (self-evaluating)"))
      ((prim-ref (lit type) (lit make-instance)) ts value))
    (method ? (self (param v ANY "Value to test") (param ts ANY "Type handle"))
      (doc "Test whether V is an instance of the type named by TS."
        (returns BOOL "#t if V's type is TS"))
      ((prim-ref (lit type) (lit ?)) v ts))
    (method of (self (param v ANY "Value"))
      (doc "Return the type handle of a value (nil for nil)."
        (returns ATOM "The type's handle atom"))
      ((prim-ref (lit type) (lit of)) v))
    (method name (self (param handle ATOM "Type handle (from Type of)"))
      (doc "Return the name string of a type handle."
        (returns STRING "The type's registered name"))
      ((prim-ref (lit type) (lit name)) handle))
    (method alist (self)
      (doc "Return the interpreter's type alist from the base object."
        (returns LIST "The ((handle . struct) ...) registry, reader-priority order"))
      ((prim-ref (lit type) (lit alist))))
    (method by-atom (self (param handle ATOM "Type handle (from Type of)"))
      (doc "Look up a type by its handle atom."
        (returns ANY "The type, or nil if unregistered"))
      ((prim-ref (lit type) (lit by-atom)) handle))
    (method io (self (param ts ANY "Type struct (from Type by-atom)"))
      (doc "Navigate to a type's IO group: (analyse (delimit (read (write (display)))))."
        (returns ANY "The IO group"))
      ((prim-ref (lit type) (lit io)) ts))
    (method cvt (self (param ts ANY "Type struct"))
      (doc "Navigate to a type's conversion group: (from (to))."
        (returns ANY "The CVT group"))
      ((prim-ref (lit type) (lit cvt)) ts))
    (method proc (self (param ts ANY "Type struct"))
      (doc "Navigate to a type's PROC group: (call-stack eval-stack)."
        (returns ANY "The PROC group"))
      ((prim-ref (lit type) (lit proc)) ts))
    (method write-cell (self (param ts ANY "Type struct"))
      (doc "The write-handler stack cell of a type." (returns ANY "The cell (%set-first! to mutate)"))
      ((prim-ref (lit type) (lit write-cell)) ts))
    (method display-cell (self (param ts ANY "Type struct"))
      (doc "The display-handler stack cell of a type." (returns ANY "The cell"))
      ((prim-ref (lit type) (lit display-cell)) ts))
    (method analyse-cell (self (param ts ANY "Type struct"))
      (doc "The analyse-handler (tokenizer scoring) stack cell of a type." (returns ANY "The cell"))
      ((prim-ref (lit type) (lit analyse-cell)) ts))
    (method from-cell (self (param ts ANY "Type struct"))
      (doc "The from-conversion alist cell of a type (see the Convert class)." (returns ANY "The cell"))
      ((prim-ref (lit type) (lit from-cell)) ts))
    (method to-cell (self (param ts ANY "Type struct"))
      (doc "The to-conversion alist cell of a type (see the Convert class)." (returns ANY "The cell"))
      ((prim-ref (lit type) (lit to-cell)) ts))
    (method call-cell (self (param ts ANY "Type struct"))
      (doc "The call-handler stack cell of a type (how (obj ...) dispatches)." (returns ANY "The cell"))
      ((prim-ref (lit type) (lit call-cell)) ts))
    (method call-top (self (param ts ANY "Type struct"))
      (doc "The current (top) call handler -- capture before pushing to delegate to it."
        (returns CALLABLE "The handler"))
      ((prim-ref (lit type) (lit call-top)) ts))
    (method delimit-cell (self (param ts ANY "Type struct"))
      (doc "The delimit-handler stack cell of a type." (returns ANY "The cell"))
      ((prim-ref (lit type) (lit delimit-cell)) ts))
    (method read-cell (self (param ts ANY "Type struct"))
      (doc "The read-handler stack cell of a type." (returns ANY "The cell"))
      ((prim-ref (lit type) (lit read-cell)) ts))
    (method iter-cell (self (param ts ANY "Type struct"))
      (doc "The iter-handler stack cell of a type (how (iter obj) builds an iterator)." (returns ANY "The cell"))
      ((prim-ref (lit type) (lit iter-cell)) ts))
    (method ops-cell (self (param ts ANY "Type struct"))
      (doc "The generic-operator alist stack cell of a type: ((op-sym . handler) ...)." (returns ANY "The cell"))
      ((prim-ref (lit type) (lit ops-cell)) ts))
    (method push-write (self (param ts ANY "Type struct") (param f CALLABLE "Write handler (fn (_ obj) ...)"))
      (doc "Push a write handler onto a type's write stack (shadows the current one)." (returns ANY "nil"))
      ((prim-ref (lit type) (lit push-write)) ts f))
    (method pop-write (self (param ts ANY "Type struct"))
      (doc "Pop the top write handler from a type's write stack." (returns ANY "nil"))
      ((prim-ref (lit type) (lit pop-write)) ts))
    (method push-display (self (param ts ANY "Type struct") (param f CALLABLE "Display handler"))
      (doc "Push a display handler onto a type's display stack." (returns ANY "nil"))
      ((prim-ref (lit type) (lit push-display)) ts f))
    (method push-call (self (param ts ANY "Type struct") (param f CALLABLE "Call handler (fn (_ obj . args) ...)"))
      (doc "Push a call handler onto a type's call stack (overrides how (obj ...) dispatches)." (returns ANY "nil"))
      ((prim-ref (lit type) (lit push-call)) ts f))
    (method push-analyse (self (param ts ANY "Type struct") (param f CALLABLE "Analyse handler (fn (_ buffer score chr) ...)"))
      (doc "Push an analyse (tokenizer scoring) handler onto a type's analyse stack." (returns ANY "nil"))
      ((prim-ref (lit type) (lit push-analyse)) ts f))
    (method push-delimit (self (param ts ANY "Type struct") (param f CALLABLE "Delimit handler"))
      (doc "Push a delimit handler onto a type's delimit stack." (returns ANY "nil"))
      ((prim-ref (lit type) (lit push-delimit)) ts f))
    (method push-read (self (param ts ANY "Type struct") (param f CALLABLE "Read handler (fn (_ buffer) ...)"))
      (doc "Push a read handler onto a type's read stack." (returns ANY "nil"))
      ((prim-ref (lit type) (lit push-read)) ts f))
    (method push-iter (self (param ts ANY "Type struct") (param f CALLABLE "Iter handler (fn (_ obj) -> iterator)"))
      (doc "Push an iter handler onto a type's iter stack -- sets how (iter obj) builds an iterator." (returns ANY "nil"))
      ((prim-ref (lit type) (lit push-iter)) ts f))
    (method push-op (self (param ts ANY "Type struct") (param op ATOM "Operator symbol, e.g. '+")
                          (param f CALLABLE "Binary handler (fn (_ a b) ...); owns coercing a plain operand"))
      (doc "Register a binary generic-operator handler on a type; the C operators (+ - * / % = <) dispatch here. A re-registration shadows the older handler."
        (returns ANY "nil"))
      ((prim-ref (lit type) (lit push-op)) ts op f))
    (method cast! (self (param obj ANY "Object to retag") (param src ANY "Object whose type tag to copy"))
      (doc "LOW-LEVEL: overwrite OBJ's type tag with SRC's (raw pointer write)."
        (returns ANY "OBJ, retagged"))
      ((prim-ref (lit type) (lit cast!)) obj src))))

; --- Shapes for the engine's own atom types ---------------------------------
;
; Each of these carries ONE data unit that is not a reference: an integer or
; character holds the value itself, a string or symbol holds a pointer to
; bytes, a primitive or pointer holds an address C owns.  None of them
; declared anything before, which left the unit count -- the thing an image
; writer or any reflective walker needs to know where an object ends --
; recorded nowhere but the C constructors.
;
; The count could not simply be declared: the collector's fallback traverses
; every declared unit with x_heap_tree_mark, which sets the mark bit THROUGH
; the pointer before it can establish the pointer is on the heap, so a traced
; `bytes` unit writes into the bytes it names.  Declaring the KIND is what
; makes the count safe to state -- and safe by construction here, because a
; type with no units was never traversed at all and a type whose units are
; all non-`ref` is not traversed either.  Same behaviour, more information.
; The coordinate is an engine capability: an engine that predates it answers
; nil for (type set-shape!), and the types simply stay undeclared -- the state
; every engine was in before this.  Guarded rather than required so the
; platform still boots on the pinned engine while the shape release lands.
; SHAPES ARE PER-BASE, and that is the reason this is data rather than a run of
; calls.  A fresh (Base make) carries none of them, and a type with no mask
; means "every unit is a reference" -- so anything reading units generically
; then dereferences a PROCEDURE's call pointer.  Declaring them on another base
; is walking its own type alist, which needs the rows, not the samples.
(def %type-shape-rows
  (lit (("INTEGER"   1 (word))       ; the value word
        ("CHARACTER" 1 (word))       ; the code point
        ("STRING"    1 (bytes))      ; pointer to its bytes
        ("SYMBOL"    1 (bytes))      ; pointer to its name
        ("PRIMITIVE" 1 (foreign))    ; a C function address
        ("POINTER"   1 (foreign))    ; an address C owns
        ; The two callables are [fn-ptr][state]: slot 0 is a raw C function
        ; pointer, NOT a heap object.  x-type/procedure.h and
        ; x-type/operative.h both say so, and both warn that marking it as one
        ; would corrupt the GC free list.  State is slot 1.
        ("PROCEDURE" 2 (foreign ref))
        ("OPERATIVE" 2 (foreign ref)))))

(def %type-shape-find
  (fn (self rows nm)
    (if (null? rows) ()
      (if (str=? (first (first rows)) nm) (first rows) (self (rest rows) nm)))))
(def %type-shape-row!
  (fn (_ ts)
    ((fn (_ row)
       (if (null? row) ()
         (Type set-shape! ts (first (rest row)) (first (rest (rest row))))))
     (%type-shape-find %type-shape-rows ((Type wrap ts) name)))))
(def %type-declare-shapes!
  (fn (self alist)
    (if (null? alist) ()
      (do (%type-shape-row! (rest (first alist))) (self (rest alist))))))

(if (null? (prim-ref (lit type) (lit set-shape!)))
  ()
  (%type-declare-shapes! (first %reflect-type-alist-cell)))

(doc (provide x/type/type Type)
  (note "Mechanism in lib/x/type/struct.x, filed under catalog ns `type`; load-time wiring fetch-and-caches the helpers instead of calling the class.")
  (note "(Type wrap t) makes a type interactive: (t name), (t cell 'type-write-stack), (t fields), (t push-write f). Field names come from the layout contract (engine/tools/contract/base-paths.x); (Type fields) lists them.")
  "Type-system reflection: construction, lookup, struct navigation, and handler-stack wiring on the Type class.")

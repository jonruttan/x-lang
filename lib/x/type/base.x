; base.x -- Base: execution-context ("base") objects via the object system.
;
; (Base make) answers a Base INSTANCE wrapping the raw C base object (the
; `raw` field), so a base is interactive: (b eval ...), (b bind ...),
; (b cell 'line).  Every static accepts either form -- raw-of unwraps --
; so plumbing that holds raw bases (logo's entry doors, tool scratch
; bases, the C prims' own returns) is untouched; the tokenizer seams
; (Tok read-str, Xon's base walks) unwrap the same way.
;
; The base C prims are de-registered (no bare names); each method hands
; its evaluated args to the matching prim, captured from the catalogue.
; Field reflection walks the layout contract (engine/tools/contract/base-paths.x)
; through type/type.x's %layout-* helpers (that module loads earlier).

(import x/type/class)
(import x/core/doors int->ptr obj->ptr obj-ref obj-set! ptr->int ptr->obj str-append)

(def-class Base ()
  (doc "Execution-context / sandbox objects: each base is a whole, isolated interpreter -- its own environment, type registry, and reader state -- wrapped as a Base instance."
    (note "CONTRACT: a fresh base is the bare C ISA -- no display/write, no reader macros, no catalogue protocol. Reach in with parent closures or (b bind ...); see core/sandbox specs.")
    (note "An instance renders as #<base:objs N>; the raw C base it wraps (the `raw` field) renders as the opaque #<obj:BASE>.")
    (note "Field access walks the layout contract: (b cell 'line), names from (Base fields).")
    (example "(let ((b (Base make))) (b eval '(+ 1 2)))" "3"))
  (doc raw "The raw C base object this instance wraps -- what the C prims and tokenizer doors consume. Read it to hand the base to raw plumbing; (Base wrap r) re-clothes one.")
  (method eval (self (param expr ANY "The form to evaluate (quote it -- it is a value here)"))
    (doc "Evaluate expr inside this base, isolated from the outer env. An error raised inside propagates to the caller's guard; the base's env is restored to its pre-eval structure on the way out."
      (returns ANY "The result of the evaluation")
      (example "(let ((b (Base make))) (b eval '(+ 1 2)))" "3"))
    ((prim-ref (lit base) (lit eval)) (self raw) expr))
  (method bind (self (param name SYMBOL "The name to define")
                     (param val ANY "The value to bind"))
    (doc "Define name as val in this base's environment, visible to subsequent evals -- the door for handing a child selected capabilities."
      (returns ANY "val")
      (example "(let ((b (Base make))) (b bind 'x 5) (b eval 'x))" "5"))
    ((prim-ref (lit base) (lit bind)) (self raw) name val))
  (method make-type (self (param name STRING "The new type's name")
                          (param h LIST "Handler alist: (verb . handler) pairs, e.g. 'write"))
    (doc "Register a custom type on this base -- cross-base make-type. Handler closures are built in the CALLING base and travel with instances; this base is marked shared so the caller's GC never sweeps them."
      (returns ANY "The type handle, for use inside this base"))
    ((prim-ref (lit base) (lit make-type)) (self raw) name h))
  (method cell (self (param fname SYMBOL "A base field name -- see (Base fields)"))
    (doc "The object the layout contract's path addresses for fname, walked from this base. A cell-label field's value sits in the cell's first slot; refuses non-base-rooted names."
      (returns ANY "The addressed cell/object")
      (note "What it hands back is raw engine structure. Some of it is a C-built spine -- the type-alist field is one -- whose nodes answer #f to pair?; walk those with the bare first/rest/null? accessors, never the List or Iter walkers, which refuse them.")
      (example "(let ((b (Base make))) (%cell-int (first (b cell 'line))))" "1"))
    (Type %layout-cell (self raw) fname (lit base)))
  (method fields (self)
    (doc "Every base field name from the layout contract."
      (returns LIST "Field name symbols, contract order"))
    (Type %layout-fields (lit base)))
  (method %repr (self)
    (doc "Inspection form: #<base:objs N> (N = the base's live allocation count)."
      (returns STRING "The repr string"))
    (Str8 append "#<base:objs "
      (Str8 append (%number->str (%cell-int (first (self cell (lit alloc-count))))) ">")))
  (static
    (method make (self)
      (doc "Create a fully initialized, isolated interpreter base, wrapped as a Base instance: the built-in types, the C prims, and a read buffer -- no lib is loaded."
        (returns OBJECT "A Base instance; its raw field is the C base object")
        (example "(let ((b (Base make))) (b eval '(* 6 7)))" "42"))
      (let ((raw ((prim-ref (lit base) (lit make))))) (new Base raw raw)))
    (method make-tok (self)
      (doc "Create a minimal tokenizer base, wrapped as a Base instance: no types, no prims -- only the boolean singletons are inherited. For custom tokenizer type registration on an isolated base."
        (returns OBJECT "A Base instance"))
      (let ((raw ((prim-ref (lit base) (lit make-tok))))) (new Base raw raw)))
    (method wrap (self (param r ANY "A raw base object (from the C prims or plumbing)"))
      (doc "Clothe a raw base object as a Base instance." (returns OBJECT "The instance"))
      (let ((raw r)) (new Base raw raw)))
    (method base? (self (param v ANY "Any value"))
      (doc "Test whether v is a Base instance."
        (returns BOOL "#t for Base instances only")
        (example "(Base base? 5)" "#f"))
      (if (object? v) (eq? (class-of v) Base) #f))
    (method raw-of (self (param v ANY "A Base instance or raw base"))
      (doc "The raw base object of either form -- instances unwrap, anything else passes through. The seam the statics and tokenizer doors use."
        (returns ANY "The raw base object"))
      (if (Base base? v) (v raw) v))
    (method eval (self (param target ANY "The base to evaluate in (instance or raw)")
                       (param expr ANY "The form to evaluate (quote it -- it is a value here)"))
      (doc "Evaluate expr inside target, isolated from the outer env. An error raised in target propagates to the caller's guard; target's env is restored to its pre-eval structure on the way out."
        (returns ANY "The result of evaluating expr in target")
        (example "(let ((b (Base make))) (Base eval b '(+ 1 2)))" "3"))
      ((prim-ref (lit base) (lit eval)) (Base raw-of target) expr))
    (method bind (self (param target ANY "The base to bind in (instance or raw)")
                       (param name SYMBOL "The name to define")
                       (param val ANY "The value to bind"))
      (doc "Define name as val in target's environment, visible to subsequent (Base eval target ...) forms."
        (returns ANY "val")
        (example "(let ((b (Base make))) (Base bind b 'x 5) (Base eval b 'x))" "5"))
      ((prim-ref (lit base) (lit bind)) (Base raw-of target) name val))
    (method make-type (self (param target ANY "The base to register the type on (instance or raw)")
                            (param name STRING "The new type's name")
                            (param h LIST "Handler alist: (verb . handler) pairs, e.g. 'write"))
      (doc "Register a custom type on target -- cross-base make-type. Handler closures are built in the CALLING base and travel with instances; target is marked shared so the caller's GC never sweeps them."
        (returns ANY "The type handle, for use inside target")
        (sample "(Base make-type b \"POINT\" (list (pair 'write (fn (_ o) (display \"<point>\")))))" "the POINT type handle"))
      ((prim-ref (lit base) (lit make-type)) (Base raw-of target) name h))
    (method cell (self (param target ANY "The base to walk (instance or raw)")
                       (param fname SYMBOL "A base field name -- see (Base fields)"))
      (doc "The layout-contract cell for fname, walked from target. Refuses non-base-rooted names."
        (note "What it hands back is raw engine structure. Some of it is a C-built spine -- the type-alist field is one -- whose nodes answer #f to pair?; walk those with the bare first/rest/null? accessors, never the List or Iter walkers, which refuse them.")
        (returns ANY "The addressed cell/object"))
      (Type %layout-cell (Base raw-of target) fname (lit base)))
    (method fields (self)
      (doc "Every base field name in the layout contract (base-rooted rows of engine/tools/contract/base-paths.x)."
        (returns LIST "Field name symbols, contract order"))
      (Type %layout-fields (lit base)))
    (method slots (self)
      (doc "The positions in a base's slot vector, from the engine's contract (engine/tools/contract/base-slots.x): one row a slot, (position name (argument...) (type...)). A routine in a slot has the engine's one signature, (base args), where args is a run of words, one an argument, each an object, an integer or a string as the row gives it."
        (returns LIST "The contract rows, position order"))
      %base-slots)
    (method %slot-position (self name)
      (doc "The contract position of slot name; refuses a name the contract does not list."
        (returns INTEGER "The position"))
      (def %go
        (fn (loop rows)
          (match
            ((null? rows)
              (Err raise (lit value) (str-append "Base slot: no such slot: " (symbol->str name)) ()))
            ((eq? (first (rest (first rows))) name) (first (first rows)))
            (#t (loop (rest rows))))))
      (%go %base-slots))
    (method slot (self (param target ANY "The base whose slot vector to read (instance or raw)")
                       (param name SYMBOL "A slot name -- see (Base slots)"))
      (doc "The address of the routine in target's slot name: the function pointer the engine calls through that position, as an integer."
        (returns INTEGER "The routine's address"))
      (ptr->int (obj->ptr (obj-ref (obj-ref (Base raw-of target) 1)
                                   (+ (Base %slot-position name) 1)))))
    (method slot! (self (param target ANY "The base whose slot vector to write (instance or raw)")
                        (param name SYMBOL "A slot name -- see (Base slots)")
                        (param routine ANY "A callable, or a routine's address as an integer"))
      (doc "Store routine in target's slot name, so the engine calls it through that position from its next call on, in target alone. A callable's function pointer is what is stored, and the caller keeps the callable alive for as long as the slot holds it. Storing back the address this answers restores the routine it replaced."
        (returns INTEGER "The address the slot held"))
      (let ((prev (Base slot target name))
            (addr (if (number? routine) routine (ptr->int (obj->ptr (obj-ref routine 0))))))
        (obj-set! (obj-ref (Base raw-of target) 1) (+ (Base %slot-position name) 1)
          (ptr->obj (int->ptr addr)))
        prev))))

(doc (provide x/type/base Base)
  (note "(Base make) -> a Base instance wrapping a fresh execution-context; (b eval expr) / (Base eval b expr) evaluates expr inside it, isolated from the outer env.")
  (note "CONTRACT: a fresh base is the bare C ISA -- no display/write, no catalogue protocol. Reach in with parent closures or (b bind ...); see core/sandbox specs.")
  (note "Field reflection: (b cell 'line) walks the layout contract; (Base fields) lists the names. The raw C base rides the `raw` field; statics and tokenizer seams accept either form.")
  (example "(let ((b (Base make))) (b eval '(+ 1 2)))" "3")
  "Base: execution-context / sandbox objects, via the Base class.")

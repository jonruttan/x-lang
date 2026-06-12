; type/type.x -- Type: the type-system reflection API.
;
; The mechanism lives in lib/x/sys/type.x (pre-object, %-private) and is
; filed in the catalog under ns `type`, beside the C entries (make,
; make-instance, ?, of, name). This class presents it: reflection and
; wiring are cold operations, so every method fetches inline with
; (prim-ref ...) per the caching rule. Modules that wire types at load
; fetch-and-cache the helpers they use instead of calling the class:
;   (def %type-push-op (prim-ref (lit type) (lit push-op)))

(import x/type/object)

(def-class Type ()
  (static
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
        (returns BOOLEAN "#t if V's type is TS"))
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
      (doc "Look up a type struct by its handle atom."
        (returns ANY "The type struct, or nil if unregistered"))
      ((prim-ref (lit type) (lit by-atom)) handle))
    (method io (self (param ts ANY "Type struct (from Type by-atom)"))
      (doc "Navigate to a type struct's IO group: (analyse (delimit (read (write (display)))))."
        (returns ANY "The IO group"))
      ((prim-ref (lit type) (lit io)) ts))
    (method cvt (self (param ts ANY "Type struct"))
      (doc "Navigate to a type struct's conversion group: (from (to))."
        (returns ANY "The CVT group"))
      ((prim-ref (lit type) (lit cvt)) ts))
    (method proc (self (param ts ANY "Type struct"))
      (doc "Navigate to a type struct's PROC group: (call-stack eval-stack)."
        (returns ANY "The PROC group"))
      ((prim-ref (lit type) (lit proc)) ts))
    (method write-cell (self (param ts ANY "Type struct"))
      (doc "The write-handler stack cell of a type." (returns ANY "The cell (set-first! to mutate)"))
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
    (method push-op (self (param ts ANY "Type struct") (param op ATOM "Operator symbol, e.g. (lit +)")
                          (param f CALLABLE "Binary handler (fn (_ a b) ...); owns coercing a plain operand"))
      (doc "Register a binary generic-operator handler on a type; the C operators (+ - * / % = <) dispatch here. A re-registration shadows the older handler."
        (returns ANY "nil"))
      ((prim-ref (lit type) (lit push-op)) ts op f))
    (method cast! (self (param obj ANY "Object to retag") (param src ANY "Object whose type tag to copy"))
      (doc "LOW-LEVEL: overwrite OBJ's type tag with SRC's (raw pointer write)."
        (returns ANY "OBJ, retagged"))
      ((prim-ref (lit type) (lit cast!)) obj src))))

(doc (provide x/type/type Type)
  (note "Mechanism in lib/x/sys/type.x, filed under catalog ns `type`; load-time wiring fetch-and-caches the helpers instead of calling the class.")
  "Type-system reflection: construction, lookup, struct navigation, and handler-stack wiring on the Type class.")

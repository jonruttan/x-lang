; base.x -- Base: execution-context ("base") objects via the object system.
; The base C prims are de-registered (no bare names); each static method below
; hands its evaluated args to the matching prim, captured from the catalog.

(import x/type/class)

(def-class Base ()
  (doc "Execution-context / sandbox objects: each base is a whole, isolated interpreter -- its own environment, type registry, and reader state."
    (note "CONTRACT: a fresh base is the bare C ISA -- no display/write, no reader macros, no catalog protocol. Reach in with parent closures or (Base bind); see core/sandbox specs.")
    (note "A base renders as the opaque #<obj:BASE>; observe one by evaluating inside it.")
    (example "(let ((b (Base make))) (Base eval b '(+ 1 2)))" "3"))
  (static
    (method make (self)
      (doc "Create a fully initialized, isolated interpreter base: the built-in types, the C prims, and a read buffer -- no lib is loaded."
        (returns BASE "A fresh execution-context (base) object")
        (example "(let ((b (Base make))) (Base eval b '(* 6 7)))" "42"))
      ((prim-ref (lit base) (lit make))))
    (method eval (self (param target BASE "The base to evaluate in")
                       (param expr ANY "The form to evaluate (quote it -- it is a value here)"))
      (doc "Evaluate expr inside target, isolated from the outer env. An error raised in target propagates to the caller's guard; target's env is restored to its pre-eval shape on the way out."
        (returns ANY "The result of evaluating expr in target")
        (example "(let ((b (Base make))) (Base eval b '(+ 1 2)))" "3"))
      ((prim-ref (lit base) (lit eval)) target expr))
    (method bind (self (param target BASE "The base to bind in")
                       (param name SYMBOL "The name to define")
                       (param val ANY "The value to bind"))
      (doc "Define name as val in target's environment, visible to subsequent (Base eval target ...) forms -- the door for handing a child selected capabilities."
        (returns ANY "val")
        (example "(let ((b (Base make))) (Base bind b 'x 5) (Base eval b 'x))" "5"))
      ((prim-ref (lit base) (lit bind)) target name val))
    (method make-type (self (param target BASE "The base to register the type on")
                            (param name STRING "The new type's name")
                            (param h LIST "Handler alist: (verb . handler) pairs, e.g. 'write"))
      (doc "Register a custom type on target -- cross-base make-type. Handler closures are built in the CALLING base and travel with instances; target is marked shared so the caller's GC never sweeps them."
        (returns ANY "The type handle, for use inside target")
        (sample "(Base make-type b \"POINT\" (list (pair 'write (fn (_ o) (display \"<point>\")))))" "the POINT type handle"))
      ((prim-ref (lit base) (lit make-type)) target name h))
    (method make-tok (self)
      (doc "Create a minimal tokenizer base: no types, no prims -- only the boolean singletons are inherited. For custom tokenizer type registration on an isolated base."
        (returns BASE "A bare token base object"))
      ((prim-ref (lit base) (lit make-tok))))))

(doc (provide x/type/base Base)
  (note "(Base make) -> a fresh execution-context (base) object; (Base eval target expr) evaluates expr inside target, isolated from the outer env.")
  (note "CONTRACT: a fresh base is the bare C ISA -- no display/write, no catalog protocol. Reach in with parent closures or (Base bind); see core/sandbox specs.")
  (note "(Base bind target name val); (Base make-type target name handlers); (Base make-tok).")
  (example "(let ((b (Base make))) (Base eval b '(+ 1 2)))" "3")
  "Base: execution-context / sandbox objects, via the Base class.")

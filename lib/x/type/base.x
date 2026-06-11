; base.x -- Base: execution-context ("base") objects via the object system.
; The base C prims are de-registered (no bare names); each static method below
; hands its evaluated args to the matching prim, captured from the catalog.

(import x/type/object)

(def-class Base ()
  (static
    (method make      (self)                 ((prim-ref (lit base) (lit make))))
    (method eval      (self target expr)     ((prim-ref (lit base) (lit eval)) target expr))
    (method bind      (self target name val) ((prim-ref (lit base) (lit bind)) target name val))
    (method make-type (self target name h)   ((prim-ref (lit base) (lit make-type)) target name h))
    (method make-tok  (self)                 ((prim-ref (lit base) (lit make-tok))))))

(doc (provide x/type/base Base)
  (note "(Base make) -> a fresh execution-context (base) object.")
  (note "(Base eval target expr) evaluates expr inside target, isolated from the outer env.")
  (note "(Base bind target name val); (Base make-type target name handlers); (Base make-tok).")
  (example "(let ((b (Base make))) (Base eval b (lit (+ 1 2))))" "3")
  "Base: execution-context / sandbox objects, via the Base class.")

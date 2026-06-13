; --- Promises (lazy evaluation) ---
;
; delay creates a promise that captures an expression and its environment.
; force evaluates the promise (once), caching the result for subsequent forces.
; delay stays a global operative (a form); the operations home on the Promise
; class. Loads after object.x (needs def-class); nothing earlier uses promises.

(import x/type/object)
; Fetch the type prims from the catalog (ns `type` is de-registered, R5).
(def %make-type (prim-ref (lit type) (lit make)))
(def %make-instance (prim-ref (lit type) (lit make-instance)))
(def %type? (prim-ref (lit type) (lit ?)))


(def %promise
  (%make-type
    (lit PROMISE)
    (list
      (pair (lit write) (fn (_ _) (display "#<promise>"))))))

(doc (def delay
  (op (expr)
    env
    (let ((forced #f) (result #f))
      (%make-instance
        %promise
        (fn (_ )
          (if forced
            result
            (let ((val (eval expr env)))
              (set! forced #t)
              (set! result val)
              val)))))))
  "Create a promise that delays evaluation of an expression until forced.")

(def-class Promise ()
  (static
    (method promise? (self (param x ANY "Value to test"))
      (doc "Test whether a value is a promise." (returns BOOL "True if x is a promise"))
      (%type? x %promise))
    (method force (self (param p ANY "Promise or value"))
      (doc "Force a promise, returning its cached value. Non-promises pass through."
        (returns ANY "The forced value, or p itself if not a promise")
        (example "(Promise force (delay (+ 1 2)))" "3"))
      (if (Promise promise? p) ((first p)) p))))

(doc (provide x/type/promise Promise delay)
  (note "Promises are memoized -- forced only once.")
  (example "(Promise force (delay (+ 1 2)))" "3")
  "Lazy evaluation: the delay form plus the Promise class.")

; --- Promises (lazy evaluation) ---
;
; delay creates a promise that captures an expression and its environment.
; force evaluates the promise (once), caching the result for subsequent forces.

(def %promise
  (make-type
    (lit PROMISE)
    (list
      (pair (lit write) (fn (self) (display "#<promise>"))))))

(note "Predicates")

(doc (def promise? (fn ((param x ANY "Value to test")) (type? x %promise)))
  (returns BOOL "True if x is a promise")
  "Test whether a value is a promise.")

(note "Construction and evaluation")

(doc (def delay
  (op (expr)
    env
    (let ((forced #f) (result #f))
      (make-instance
        %promise
        (fn ()
          (if forced
            result
            (let ((val (eval expr env)))
              (set! forced #t)
              (set! result val)
              val)))))))
  "Create a promise that delays evaluation of an expression until forced.")

(doc (def force (fn ((param p ANY "Promise or value")) (if (promise? p) ((first p)) p)))
  (returns ANY "The forced value, or p itself if not a promise")
  "Force a promise, returning its cached value. Non-promises pass through.")

(doc (provide x/promise promise? delay force)
  (note "Promises are memoized -- forced only once.")
  (example "(force (delay (+ 1 2)))" "3")
  "Lazy evaluation with delay/force.")

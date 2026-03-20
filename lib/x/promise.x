; --- Promises (lazy evaluation) ---
;
; delay creates a promise that captures an expression and its environment.
; force evaluates the promise (once), caching the result for subsequent forces.

(def %promise
  (make-type
    (lit PROMISE)
    (list
      (pair (lit write) (fn (self) (display "#<promise>"))))))

(def promise? (fn (x) (type? x %promise)))

(def delay
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

(def force (fn (p) (if (promise? p) ((first p)) p)))

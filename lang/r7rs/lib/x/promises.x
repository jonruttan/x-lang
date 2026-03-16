; --- Promises (R7RS §4.2.5) ---

(define
  %promise
  (make-type
    (lit PROMISE)
    (list
      (pair (lit write) (lambda (self) (display "#<promise>"))))))
(define (promise? x) (type? x %promise))
(define
  delay
  (op (expr)
    env
    (let ((forced #f) (result #f))
      (make-instance
        %promise
        (lambda
          ()
          (if forced
            result
            (let ((val (eval expr env)))
              (set! forced #t)
              (set! result val)
              val)))))))
(define
  (make-promise x)
  (if (promise? x)
    x
    (let ((val x)) (make-instance %promise (lambda () val)))))
; delay-force: for iterative forcing of tail-recursive promise chains
(define
  delay-force
  (op (expr)
    env
    (let ((forced #f) (result #f))
      (make-instance
        %promise
        (lambda
          ()
          (if forced
            result
            (let ((val (eval expr env)))
              (set! forced #t)
              (set! result val)
              (if (promise? val) (force val) val))))))))

; force: iteratively force promise chains
(define (force p)
  (if (promise? p)
    (let ((val ((first p))))
      (if (promise? val) (force val) val))
    p))

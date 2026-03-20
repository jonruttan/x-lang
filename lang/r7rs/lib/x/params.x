; --- Parameters (R7RS §4.2.6) ---

(define (make-parameter init . converter)
  (let ((conv (if (null? converter) #f (car converter))))
    (let ((val (if conv (conv init) init)))
      (lambda args
        (cond
          ((null? args) val)
          ((and (pair? args) (pair? (cdr args)))
           ; internal protocol: (param new-val 'set) -> set and return old
           (let ((old val))
             (set! val (if conv (conv (car args)) (car args)))
             old))
          (#t (set! val (if conv (conv (car args)) (car args)))))))))

; parameterize: bind parameters within body, restore on exit.
; Uses dynamic-wind for continuation safety.
(define
  parameterize
  (op (bindings . body)
    env
    (let ((params (map (lambda (b) (eval (car b) env)) bindings))
          (vals (map (lambda (b) (eval (cadr b) env)) bindings)))
      (let ((old-vals (map (lambda (p v) (p v (lit set!))) params vals)))
        (dynamic-wind
          (lambda ()
            (for-each (lambda (p v) (p v (lit set!))) params vals))
          (lambda ()
            (eval (cons (lit begin) body) env))
          (lambda ()
            (set! vals (map (lambda (p) (p)) params))
            (for-each (lambda (p v) (p v (lit set!))) params old-vals)))))))

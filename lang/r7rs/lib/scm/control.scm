; --- Control extensions (R7RS §4.2.2) ---

; let-values: destructure multiple-value returns
; (let-values (((a b) (values 1 2))) body ...)
(define let-values
  (op (bindings . body)
    env
    (if (null? bindings)
      (eval (cons (lit begin) body) env)
      (let ((binding (car bindings))
            (rest-bindings (cdr bindings)))
        (let ((formals (car binding))
              (producer (cadr binding)))
          (call-with-values
            (lambda () (eval producer env))
            (lambda vals
              (let loop ((fs formals) (vs vals) (e env))
                (cond
                  ((null? fs)
                   (eval (list (lit let-values) rest-bindings
                           (cons (lit begin) body)) e))
                  ((symbol? fs)
                   ; rest-arg: bind remaining values as list
                   (eval (list (lit let-values) rest-bindings
                           (cons (lit begin) body))
                     (cons (cons fs vs) e)))
                  (#t
                   (loop (cdr fs) (cdr vs)
                     (cons (cons (car fs) (car vs)) e))))))))))))

; let*-values: like let-values but sequential
(define let*-values
  (op (bindings . body)
    env
    (if (null? bindings)
      (eval (cons (lit begin) body) env)
      (eval
        (list (lit let-values) (list (car bindings))
          (cons (lit let*-values) (cons (cdr bindings) body)))
        env))))

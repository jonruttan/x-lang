; --- Derived expression types (R5RS §4.2) ---

; when / unless (initial versions using (lit do) = x-lang begin)

(def when
  (op (test . body)
    e
    (if (eval test e) (tail-eval (pair (lit do) body) e))))
(def unless
  (op (test . body)
    e
    (if (not (eval test e)) (tail-eval (pair (lit do) body) e))))

; --- let* ---

(def let*
  (op (bindings . body)
    e
    (if (null? bindings)
      (tail-eval (pair (lit do) body) e)
      (tail-eval
        (list
          (lit let)
          (list (first bindings))
          (pair (lit let*) (pair (rest bindings) body)))
        e))))

; --- letrec ---

(def letrec
  (op (bindings . body)
    e
    (tail-eval
      (pair
        (lit let)
        (pair
          (map (lambda (b) (list (first b) ())) bindings)
          (append
            (map
              (lambda (b) (list (lit set!) (first b) (cadr b)))
              bindings)
            body)))
      e)))

; --- Named let ---

(def %let let)
(def let
  (op (first-arg . rest-args)
    e
    (if (symbol? first-arg)
      (tail-eval
        (list
          (lit letrec)
          (list
            (list
              first-arg
              (pair
                (lit lambda)
                (pair (map car (first rest-args)) (rest rest-args)))))
          (pair first-arg (map cadr (first rest-args))))
        e)
      (tail-eval (pair (lit %let) (pair first-arg rest-args)) e))))

; --- do ---

; (do ((var init step) ...) (test expr ...) command ...)

(define
  do
  (op (bindings test-and-result . body)
    env
    (let ((vars (map car bindings))
           (inits (map (lambda (b) (list-ref b 1)) bindings))
           (steps
             (map
               (lambda (b) (if (> (length b) 2) (list-ref b 2) (car b)))
               bindings))
           (test (car test-and-result))
           (result (cdr test-and-result)))
      (tail-eval
        (cons
          (list
            (lit lambda)
            ()
            (cons
              (lit letrec)
              (cons
                (list
                  (list
                    (lit %do-loop)
                    (cons
                      (lit lambda)
                      (cons
                        vars
                        (list
                          (list
                            (lit if)
                            test
                            (if (null? result)
                              (list (lit if) #f #f)
                              (cons (lit begin) result))
                            (append
                              (cons (lit begin) body)
                              (list (cons (lit %do-loop) steps)))))))))
                (list (cons (lit %do-loop) inits)))))
          ())
        env))))

; --- Override forms that used (lit do) to use (lit begin) instead ---

; (do was just redefined as the R5RS iteration form)

(define
  when
  (op (test . body)
    e
    (if (eval test e) (tail-eval (pair (lit begin) body) e))))
(define
  unless
  (op (test . body)
    e
    (if (not (eval test e)) (tail-eval (pair (lit begin) body) e))))
(define
  let*
  (op (bindings . body)
    e
    (if (null? bindings)
      (tail-eval (pair (lit begin) body) e)
      (tail-eval
        (list
          (lit let)
          (list (first bindings))
          (pair (lit let*) (pair (rest bindings) body)))
        e))))

; --- R5RS cond (multi-expression clause bodies + => syntax) ---

(define
  cond
  (op clauses
    e
    (let %cond-loop
      ((cls clauses))
      (if (null? cls)
        ()
        (let ((clause (first cls)))
          (if (eq? (first clause) (lit else))
            (tail-eval (pair (lit begin) (rest clause)) e)
            (let ((test-val (eval (first clause) e)))
              (if test-val
                (if (and (pair? (rest clause)) (eq? (cadr clause) (lit =>)))
                  ((eval (caddr clause) e) test-val)
                  (tail-eval (pair (lit begin) (rest clause)) e))
                (%cond-loop (rest cls))))))))))

; --- Promises ---

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
(define (force p) (if (promise? p) ((first p)) p))

; --- case (multi-expression clause bodies) ---

(def case
  (op (key . clauses)
    e
    (def case-val (eval key e))
    (def case-match?
      (fn (datum)
        (if (number? case-val)
          (= case-val datum)
          (eq? case-val datum))))
    (def case-check-datums
      (fn (datums)
        (match
          ((null? datums) ())
          ((case-match? (first datums)) #t)
          (#t (case-check-datums (rest datums))))))
    (def case-loop
      (fn (cls)
        (match
          ((null? cls) ())
          ((or
             (eq? (first (first cls)) (lit else))
             (case-check-datums (first (first cls))))
            (tail-eval (pair (lit begin) (rest (first cls))) e))
          (#t (case-loop (rest cls))))))
    (case-loop clauses)))

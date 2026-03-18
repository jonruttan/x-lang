; --- R5RS Derived expression types (§4.2) ---
;
; General-purpose constructs (when, unless, let*, letrec, named let,
; cond, case, delay/force) are now in lib/x/derived.x and lib/x/promise.x.
;
; This file provides only:
;   1. R5RS do (iteration) — redefines x-lang's do (= begin)
;   2. Post-override patches for forms that used (lit do) for sequencing

; --- do (R5RS iteration) ---

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

; (do was just redefined as the R5RS iteration form, so any construct
; that used (lit do) for sequential evaluation must switch to (lit begin))

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
                (if (and (pair? (rest clause))
                         (eq? (first (rest clause)) (lit =>)))
                  ((eval (first (rest (rest clause))) e) test-val)
                  (tail-eval (pair (lit begin) (rest clause)) e))
                (%cond-loop (rest cls))))))))))
(define
  case
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

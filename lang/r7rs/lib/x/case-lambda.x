; --- case-lambda (R7RS §4.2.9) ---

(define
  case-lambda
  (op clauses
    env
    (eval
      (list
        (lit lambda)
        (lit %cl-args)
        (cons
          (lit cond)
          (append
            (map
              (lambda
                (clause)
                (list
                  (list
                    (lit =)
                    (list (lit length) (lit %cl-args))
                    (length (car clause)))
                  (list
                    (lit apply)
                    (cons (lit lambda) clause)
                    (lit %cl-args))))
              clauses)
            (list
              (list
                #t
                (list (lit error) "case-lambda: no matching clause"))))))
      env)))

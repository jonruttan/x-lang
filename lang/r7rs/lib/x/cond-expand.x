; --- cond-expand (R7RS §4.2.1) ---

(define %features (list (lit r7rs) (lit x-lang) (lit ieee-float)))

(define (%feature-match? req)
  (cond
    ((symbol? req) (memq req %features))
    ((and (pair? req) (eq? (car req) (lit and)))
     (let loop ((rs (cdr req)))
       (or (null? rs)
           (and (%feature-match? (car rs)) (loop (cdr rs))))))
    ((and (pair? req) (eq? (car req) (lit or)))
     (let loop ((rs (cdr req)))
       (and (pair? rs)
            (or (%feature-match? (car rs)) (loop (cdr rs))))))
    ((and (pair? req) (eq? (car req) (lit not)))
     (not (%feature-match? (cadr req))))
    (#t #f)))

(define
  cond-expand
  (op clauses
    env
    (let loop ((cs clauses))
      (cond
        ((null? cs) (error "cond-expand: no matching clause"))
        ((eq? (caar cs) (lit else))
         (eval (cons (lit begin) (cdar cs)) env))
        ((%feature-match? (caar cs))
         (eval (cons (lit begin) (cdar cs)) env))
        (#t (loop (cdr cs)))))))

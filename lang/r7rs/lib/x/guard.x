; --- R7RS guard (§4.2.7) ---
; (guard (var clause ...) body ...)
; Each clause is (test expr ...) or (else expr ...)
; Transforms clauses into a cond form for the C guard handler.

(define %c-guard guard)

(define
  guard
  (op (clause . body)
    env
    (let ((var (car clause))
          (clauses (cdr clause)))
      ; Build: (%c-guard (var (cond clauses ...)) body ...)
      (eval
        (cons (lit %c-guard)
          (cons
            (list var (cons (lit cond) clauses))
            body))
        env))))

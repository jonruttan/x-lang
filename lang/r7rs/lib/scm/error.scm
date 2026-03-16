; --- Error objects (R7RS §6.11) ---
; Error objects are tagged lists: (%error-object message irritants)

(define %error-tag (cons (lit %error) (lit object)))

(define %c-error error)
(define (error message . irritants)
  (%c-error (list %error-tag message irritants)))

(define (error-object? obj)
  (and (pair? obj) (eq? (car obj) %error-tag)))

(define (error-object-message obj)
  (if (error-object? obj) (cadr obj) obj))

(define (error-object-irritants obj)
  (if (error-object? obj) (caddr obj) ()))

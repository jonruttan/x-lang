; --- Error objects (R7RS §6.11) ---

(define (error-object? obj) (string? obj))
(define (error-object-message obj) obj)
(define (error-object-irritants obj) ())

; --- Port extensions (R7RS §6.13) ---

(define (port? x) (or (input-port? x) (output-port? x)))
(define (close-port p)
  (cond ((input-port? p) (close-input-port p))
        ((output-port? p) (close-output-port p))))

; --- Control features (R5RS §6.4) ---

; --- Multiple values ---

(define
  %values
  (make-type
    (lit VALUES)
    (list
      (pair
        (lit write)
        (lambda
          (self)
          (for-each
            (lambda (v) (display " ") (write v))
            (first self)))))))
(define
  (values . args)
  (if (= (length args) 1)
    (car args)
    (make-instance %values args)))
(define
  (call-with-values producer consumer)
  (let ((result (producer)))
    (if (type? result %values)
      (apply consumer (first result))
      (consumer result))))

; --- First-class continuations with dynamic-wind ---
; call/cc is a stack-copying C primitive; wrap it to support
; dynamic-wind before/after thunk transitions.

(define %wind-stack (list))
(define %c-call/cc call/cc)

; Find longest common tail of two wind stacks.
(define (%wind-common-tail a b)
  (let ((la (length a)) (lb (length b)))
    (let ((a (if (> la lb) (list-tail a (- la lb)) a))
          (b (if (> lb la) (list-tail b (- lb la)) b)))
      (let loop ((a a) (b b))
        (if (eq? a b) a
          (loop (cdr a) (cdr b)))))))

; Exit from current wind stack to common tail (after thunks).
(define (%wind-exit current common)
  (if (not (eq? current common))
    (begin
      (set! %wind-stack (cdr current))
      ((cdr (car current)))
      (%wind-exit (cdr current) common))))

; Enter from common tail to target wind stack (before thunks).
; Recurse first so outermost before runs first.
(define (%wind-enter target common)
  (if (not (eq? target common))
    (begin
      (%wind-enter (cdr target) common)
      (set! %wind-stack target)
      ((car (car target))))))

(define (call-with-current-continuation proc)
  (let ((saved-winds %wind-stack))
    (%c-call/cc
      (lambda (k)
        (proc
          (lambda args
            (let ((common (%wind-common-tail %wind-stack saved-winds)))
              (%wind-exit %wind-stack common)
              (%wind-enter saved-winds common))
            (apply k args)))))))
(define call/cc call-with-current-continuation)

(define (dynamic-wind before thunk after)
  (before)
  (set! %wind-stack (cons (cons before after) %wind-stack))
  (let ((result (thunk)))
    (set! %wind-stack (cdr %wind-stack))
    (after)
    result))

; --- Environment procedures ---

(define %current-env (op () e e))
(define (scheme-report-environment version)
  (if (= version 5) (%current-env)
    (error "unsupported version")))
(define (null-environment version)
  (if (= version 5) (%current-env)
    (error "unsupported version")))
(define (interaction-environment) (%current-env))

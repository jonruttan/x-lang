; r5rs-harness.x -- Function-based test harness for R5RS tests
;
; Replaces the define-syntax harness in r5rs-tests.scm.
; Uses simple functions since all args are evaluated before the call.

(define *tests-run* 0)
(define *tests-passed* 0)
(define *tests-failed* 0)

;; test: 2-arg (test expect expr) or 3-arg (test name expect expr)
;; All args are evaluated before calling test.
;; write that handles nil safely
(define (%safe-write x)
  (if (null? x) (display "()") (write x)))

(define (test . args)
  (set! *tests-run* (+ *tests-run* 1))
  (let* ((a (if (null? (cddr args)) args (cdr args)))
         (expect (car a))
         (res (cadr a)))
    (display *tests-run*)
    (display ". ")
    (if (equal? res expect)
      (begin
        (set! *tests-passed* (+ *tests-passed* 1))
        (display " [PASS]")
        (newline))
      (begin
        (set! *tests-failed* (+ *tests-failed* 1))
        (display " [FAIL]")
        (newline)
        (display "    expected ") (%safe-write expect)
        (display " but got ") (%safe-write res) (newline)))))

(define (test-assert expr) (test #t expr))

(define (test-begin . name) #f)

(define (test-end)
  (newline)
  (display *tests-passed*) (display " out of ")
  (display *tests-run*) (display " passed (")
  (display (/ (* 100 *tests-passed*) *tests-run*))
  (display "%)")
  (newline))

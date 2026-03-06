;; No shebangs...yet
;;#!/usr/bin/env rs.sh

;; # rs.c Test Suite
;;
;; Run tests with:
;;     
;;     ./tests.rs

(define Errors 0)

; ANSI Terminal Colors
(define bold  (string #esc "[0;1m"))
(define red   (string #esc "[0;31m"))
(define green (string #esc "[0;32m"))
(define reset (string #esc "[0m"))

(define (lambda (check src expr result)
;  (write src) (display " ==> ") (write expr) (newline)
  (if (not (eq expr result))
      (begin (write src)
             (display " FAILED!")
             (newline)
             (display "Expected: ")
             (write result)
             (newline)
             (display "But got:  ")
             (write expr)
             (newline)
             (set! Errors (+ 1 Errors))))))

(display green "hi" reset)

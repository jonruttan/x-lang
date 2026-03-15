## complete c*r compositions (3-letter)

### cadar
```scheme
(cadar '((1 2 3) 4))
```
---
    2

### cdaar
```scheme
(cdaar '(((1 2) 3) 4))
```
---
    (2)

### cdadr
```scheme
(cdadr '(1 (2 3) 4))
```
---
    (3)

### cddar
```scheme
(cddar '((1 2 3) 4))
```
---
    (3)

## complete c*r compositions (4-letter)

### caaaar
```scheme
(caaaar '((((1 2) 3) 4) 5))
```
---
    1

### cadadr
```scheme
(cadadr '(1 (2 3 4) 5))
```
---
    3

### cadddr
```scheme
(cadddr '(1 2 3 4 5))
```
---
    4

### cddddr
```scheme
(cddddr '(1 2 3 4 5))
```
---
    (5)

### cdddar
```scheme
(cdddar '((1 2 3 4) 5))
```
---
    (4)

### cadaar
```scheme
(cadaar '(((1 2) 3) 4))
```
---
    2

## vector-fill!

### vector-fill! sets all elements
```scheme
(define v (vector 1 2 3))
(vector-fill! v 0)
v
```
---
    #(0 0 0)

### vector-fill! on empty vector
```scheme
(define v (make-vector 0))
(vector-fill! v 99)
v
```
---
    #()

## string-set!

### string-set! replaces character
```scheme
(string-set! "hello" 1 #\a)
```
---
    "hallo"

### string-set! at beginning
```scheme
(string-set! "abc" 0 #\z)
```
---
    "zbc"

### string-set! at end
```scheme
(string-set! "abc" 2 #\z)
```
---
    "abz"

## string-fill!

### string-fill! fills all characters
```scheme
(string-fill! "hello" #\x)
```
---
    "xxxxx"

### string-fill! on single char
```scheme
(string-fill! "a" #\z)
```
---
    "z"

## numerator and denominator

### numerator of positive integer
```scheme
(numerator 5)
```
---
    5

### numerator of zero
```scheme
(numerator 0)
```
---
    0

### numerator of negative
```scheme
(numerator -3)
```
---
    -3

### denominator of integer
```scheme
(denominator 5)
```
---
    1

### denominator of zero
```scheme
(denominator 0)
```
---
    1

## dynamic-wind

### dynamic-wind calls all three thunks
```scheme
(define log '())
(define result
  (dynamic-wind
    (lambda () (set! log (cons 'before log)))
    (lambda () (set! log (cons 'during log)) 42)
    (lambda () (set! log (cons 'after log)))))
(list result (reverse log))
```
---
    (42 (before during after))

### dynamic-wind returns thunk result
```scheme
(dynamic-wind
  (lambda () #f)
  (lambda () (+ 1 2))
  (lambda () #f))
```
---
    3

## escape-only call/cc

### call/cc basic escape
```scheme
(call-with-current-continuation
  (lambda (k) (k 42) 99))
```
---
    42

### call/cc no escape returns normally
```scheme
(call-with-current-continuation
  (lambda (k) 77))
```
---
    77

### call/cc in arithmetic context
```scheme
(+ 1 (call/cc (lambda (k) (+ 2 (k 3)))))
```
---
    4

### call/cc early exit from for-each (R5RS example)
```scheme
(call-with-current-continuation
  (lambda (exit)
    (for-each (lambda (x)
                (if (negative? x) (exit x)))
              '(54 0 37 -3 245 19))
    #t))
```
---
    -3

### call/cc procedure? returns true
```scheme
(procedure? call-with-current-continuation)
```
---
    #t

### call/cc alias works
```scheme
(eq? call/cc call-with-current-continuation)
```
---
    #t

## environment procedures

### scheme-report-environment usable with eval
```scheme
(eval '(+ 1 2) (scheme-report-environment 5))
```
---
    3

### null-environment usable with eval
```scheme
(eval '(if #t 1 2) (null-environment 5))
```
---
    1

### interaction-environment usable with eval
```scheme
(eval '(+ 3 4) (interaction-environment))
```
---
    7

### eval with scheme-report-environment
```scheme
(eval '(* 6 7) (scheme-report-environment 5))
```
---
    42

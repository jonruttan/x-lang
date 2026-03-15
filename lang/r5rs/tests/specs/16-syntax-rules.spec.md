## define-syntax

### defines a simple macro

```scheme
(define-syntax my-if
  (syntax-rules ()
    ((_ test then else)
     (cond (test then) (else else)))))
(my-if #t 1 2)
```
---
    1

### macro with single-arm pattern

```scheme
(define-syntax my-const
  (syntax-rules ()
    ((_ x) 42)))
(my-const anything)
```
---
    42

### macro expands in correct scope

```scheme
(define-syntax my-add
  (syntax-rules ()
    ((_ x y) (+ x y))))
(my-add 3 4)
```
---
    7

### macro works with nested expressions

```scheme
(define-syntax my-square
  (syntax-rules ()
    ((_ x) (* x x))))
(my-square (+ 2 3))
```
---
    25

## syntax-rules hygiene

### introduced bindings use definition environment (pitfall 3.1)

```scheme
(let-syntax ((foo
              (syntax-rules ()
                ((_ expr) (+ expr 1)))))
  (let ((+ *))
    (foo 3)))
```
---
    4

### macro-defined variable does not leak (pitfall 3.2)

```scheme
(let-syntax ((foo (syntax-rules ()
                     ((_ var) (define var 1)))))
   (let ((x 2))
     (begin (define foo +))
     (cond (else (foo x)))
     x))
```
---
    2

### nested let-syntax preserves hygiene (pitfall 3.3)

```scheme
(let ((x 1))
  (let-syntax
      ((foo (syntax-rules ()
              ((_ y) (let-syntax
                           ((bar (syntax-rules ()
                                 ((_) (let ((x 2)) y)))))
                       (bar))))))
    (foo x)))
```
---
    1

### empty syntax-rules is valid (pitfall 3.4)

```scheme
(let-syntax ((x (syntax-rules ()))) 1)
```
---
    1

## let-syntax

### basic local syntax binding

```scheme
(let-syntax ((double (syntax-rules ()
                       ((_ x) (+ x x)))))
  (double 5))
```
---
    10

### multiple let-syntax bindings

```scheme
(let-syntax ((add1 (syntax-rules () ((_ x) (+ x 1))))
             (sub1 (syntax-rules () ((_ x) (- x 1)))))
  (+ (add1 10) (sub1 10)))
```
---
    20

### let-syntax does not leak into outer scope

```scheme
(define result
  (let-syntax ((local-mac (syntax-rules () ((_ x) (+ x 100)))))
    (local-mac 5)))
result
```
---
    105

### let-syntax body sees outer bindings

```scheme
(define outer-val 42)
(let-syntax ((get-outer (syntax-rules () ((_) outer-val))))
  (get-outer))
```
---
    42

## syntax-rules with literals

### literal keyword matching

```scheme
(define-syntax my-arrow
  (syntax-rules (=>)
    ((_ x => y) (+ x y))))
(my-arrow 3 => 4)
```
---
    7

### literal prevents variable capture

```scheme
(define-syntax my-when
  (syntax-rules ()
    ((_ test body)
     (if test body ()))))
(my-when #t 42)
```
---
    42

### literal in wrong position fails to match

```scheme
(define-syntax choose
  (syntax-rules (from)
    ((_ x from y) (+ x y))
    ((_ x y) (* x y))))
(choose 3 5)
```
---
    15

## syntax-rules multiple clauses

### first matching clause wins

```scheme
(define-syntax my-op
  (syntax-rules ()
    ((_ x) (+ x 1))
    ((_ x y) (+ x y))))
(my-op 10)
```
---
    11

### second clause matches when first fails

```scheme
(define-syntax my-op2
  (syntax-rules ()
    ((_ x) (+ x 1))
    ((_ x y) (+ x y))))
(my-op2 10 20)
```
---
    30

### pattern with nested structure

```scheme
(define-syntax swap-pair
  (syntax-rules ()
    ((_ (a b)) (list b a))))
(swap-pair (1 2))
```
---
    (2 1)

## define-syntax with define

### macro expanding to lambda

```scheme
(define-syntax make-adder
  (syntax-rules ()
    ((_ n) (lambda (x) (+ x n)))))
(define add5 (make-adder 5))
(add5 10)
```
---
    15

## hygiene with gensym

### introduced let binding does not capture

```scheme
(define x 10)
(define-syntax use-x
  (syntax-rules ()
    ((_ body) (let ((y 99)) body))))
(use-x x)
```
---
    10

### multiple macros do not interfere

```scheme
(define-syntax mac1
  (syntax-rules ()
    ((_ x) (+ x 1))))
(define-syntax mac2
  (syntax-rules ()
    ((_ x) (* x 2))))
(+ (mac1 5) (mac2 5))
```
---
    16

## pitfall-style edge cases

### lambda as identifier (pitfall 4.1)

```scheme
((lambda lambda lambda) (quote x))
```
---
    (x)

### let-syntax in define body (pitfall 8.3)

```scheme
(let ((x 1))
  (let-syntax ((foo (syntax-rules () ((_) 2))))
    (define x (foo))
    3)
  x)
```
---
    1

## ellipsis patterns

### ellipsis collects zero or more elements

```scheme
(define-syntax my-list
  (syntax-rules ()
    ((_ x ...) (list x ...))))
(my-list 1 2 3)
```
---
    (1 2 3)

### ellipsis with zero elements

```scheme
(define-syntax my-list
  (syntax-rules ()
    ((_ x ...) (list x ...))))
(null? (my-list))
```
---
    t

### ellipsis with single element

```scheme
(define-syntax my-list
  (syntax-rules ()
    ((_ x ...) (list x ...))))
(my-list 42)
```
---
    (42)

### ellipsis in recursive macro (my-and)

```scheme
(define-syntax my-and
  (syntax-rules ()
    ((_) #t)
    ((_ e) e)
    ((_ e1 e2 ...)
     (if e1 (my-and e2 ...) #f))))
(my-and 1 2 3)
```
---
    3

### ellipsis recursive macro short-circuit

```scheme
(define-syntax my-and
  (syntax-rules ()
    ((_) #t)
    ((_ e) e)
    ((_ e1 e2 ...)
     (if e1 (my-and e2 ...) #f))))
(null? (my-and #f 2 3))
```
---
    t

### multiple pvars in ellipsis (my-let)

```scheme
(define-syntax my-let
  (syntax-rules ()
    ((_ ((var val) ...) body)
     ((lambda (var ...) body) val ...))))
(my-let ((x 1) (y 2) (z 3)) (+ x y z))
```
---
    6

### empty ellipsis with multiple pvars

```scheme
(define-syntax my-let
  (syntax-rules ()
    ((_ ((var val) ...) body)
     ((lambda (var ...) body) val ...))))
(my-let () 42)
```
---
    42

### tail pattern after ellipsis

```scheme
(define-syntax last-arg
  (syntax-rules ()
    ((_ x ... last) last)))
(last-arg 1 2 3 4 5)
```
---
    5

### begin-like sequencing with ellipsis

```scheme
(define-syntax my-begin
  (syntax-rules ()
    ((_ e) e)
    ((_ e1 e2 ...) (let ((t e1)) (my-begin e2 ...)))))
(my-begin 1 2 3)
```
---
    3

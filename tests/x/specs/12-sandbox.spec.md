## make-base

### creates a base object

```scheme
(pair? (make-base))
```
---

### new base has arithmetic

```scheme
(do (def b (make-base)) (base-eval b (lit (+ 1 2))))
```
---
    3

### new base has def

```scheme
(do (def b (make-base)) (base-eval b (lit (def x 10))) (base-eval b (lit x)))
```
---
    10

## base isolation

### parent binding not visible in child

```scheme
(do (def x 10) (def b (make-base)) (guard (e (lit isolated)) (base-eval b (lit x))))
```
---
    isolated

### child binding not visible in parent

```scheme
(do (def b (make-base)) (base-eval b (lit (def x 42))) (guard (e (lit isolated)) x))
```
---
    isolated

### two bases are independent

```scheme
(do (def a (make-base)) (def b (make-base)) (base-eval a (lit (def x 1))) (base-eval b (lit (def x 2))) (+ (base-eval a (lit x)) (base-eval b (lit x))))
```
---
    3

## base-eval

### evaluates arithmetic

```scheme
(do (def b (make-base)) (base-eval b (lit (* 6 7))))
```
---
    42

### evaluates closures

```scheme
(do (def b (make-base)) (base-eval b (lit (do (def f (fn (x) (* x x))) (f 5)))))
```
---
    25

### propagates errors to parent guard

```scheme
(do (def b (make-base)) (guard (e (lit caught)) (base-eval b (lit (error "boom")))))
```
---
    caught

## base-bind

### binds a value in target base

```scheme
(do (def b (make-base)) (base-bind b (lit x) 42) (base-eval b (lit x)))
```
---
    42

### binds a list in target base

```scheme
(do (def b (make-base)) (base-bind b (lit xs) (list 1 2 3)) (base-eval b (lit (first xs))))
```
---
    1

### does not affect parent

```scheme
(do (def b (make-base)) (base-bind b (lit z) 99) (guard (e (lit ok)) z))
```
---
    ok


## token-accept

### is a function

```scheme
(procedure? token-accept)
```
---
    #t

## token-reject

### is a function

```scheme
(procedure? token-reject)
```
---
    #t

## make-digit-state

### returns a function

```scheme
(procedure? (make-digit-state token-accept))
```
---
    #t

## make-xdigit-state

### returns a function

```scheme
(procedure? (make-xdigit-state token-accept))
```
---
    #t

## make-char-state

### returns a function

```scheme
(procedure? (make-char-state 65 token-accept ()))
```
---
    #t

## make-pred-state

### returns a function

```scheme
(procedure? (make-pred-state (fn (_ c) (Char alphabetic? c)) token-accept))
```
---
    #t

## make-range-state

### returns a function

```scheme
(procedure? (make-range-state 48 57 token-accept))
```
---
    #t

## make-alt-state

### returns a function

```scheme
(procedure? (make-alt-state token-accept token-reject))
```
---
    #t

## make-str-state

### returns a function

```scheme
(procedure? (make-str-state "abc" token-accept ()))
```
---
    #t

## make-count-state

### returns a function for n=3

```scheme
(procedure? (make-count-state 3 (fn (_ c) (Char numeric? c)) token-accept))
```
---
    #t

### returns done directly for n=0

```scheme
(eq? (make-count-state 0 (fn (_ c) (Char numeric? c)) token-accept) token-accept)
```
---
    #t

## make-min-state

### returns a function

```scheme
(procedure? (make-min-state 1 (fn (_ c) (Char numeric? c)) token-accept))
```
---
    #t

## make-optional-char

### returns a function

```scheme
(procedure? (make-optional-char 43 token-accept))
```
---
    #t

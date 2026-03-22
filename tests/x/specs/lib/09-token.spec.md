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
(procedure? (make-pred-state char-alphabetic? token-accept))
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

## make-string-state

### returns a function

```scheme
(procedure? (make-string-state "abc" token-accept ()))
```
---
    #t

## make-count-state

### returns a function for n=3

```scheme
(procedure? (make-count-state 3 char-numeric? token-accept))
```
---
    #t

### returns done directly for n=0

```scheme
(eq? (make-count-state 0 char-numeric? token-accept) token-accept)
```
---
    #t

## make-min-state

### returns a function

```scheme
(procedure? (make-min-state 1 char-numeric? token-accept))
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

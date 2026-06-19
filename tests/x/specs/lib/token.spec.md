# @lib ../tests/x/lib/token.x

Token (`lib/x/sys/token.x`) is the tokenizer state-builder vocabulary. The
builders are `Token` methods (called at setup); the terminators (accept /
accept-inclusive / reject) are registered under catalog ns `token` for
reader-context callers to fetch. The harness caches `%acc` / `%rej`.

## Token accept

### the accept terminator is a function

```scheme
(procedure? %acc)
```
---
    #t

## Token reject

### the reject terminator is a function

```scheme
(procedure? %rej)
```
---
    #t

## make-digit-state

### returns a function

```scheme
(procedure? (Token make-digit-state %acc))
```
---
    #t

## make-xdigit-state

### returns a function

```scheme
(procedure? (Token make-xdigit-state %acc))
```
---
    #t

## make-char-state

### returns a function

```scheme
(procedure? (Token make-char-state 65 %acc ()))
```
---
    #t

## make-pred-state

### returns a function

```scheme
(procedure? (Token make-pred-state (fn (_ c) (Char alphabetic? c)) %acc))
```
---
    #t

## make-range-state

### returns a function

```scheme
(procedure? (Token make-range-state 48 57 %acc))
```
---
    #t

## make-alt-state

### returns a function

```scheme
(procedure? (Token make-alt-state %acc %rej))
```
---
    #t

## make-str-state

### returns a function

```scheme
(procedure? (Token make-str-state "abc" %acc ()))
```
---
    #t

## make-count-state

### returns a function for n=3

```scheme
(procedure? (Token make-count-state 3 (fn (_ c) (Char numeric? c)) %acc))
```
---
    #t

### returns done directly for n=0

```scheme
(eq? (Token make-count-state 0 (fn (_ c) (Char numeric? c)) %acc) %acc)
```
---
    #t

## make-min-state

### returns a function

```scheme
(procedure? (Token make-min-state 1 (fn (_ c) (Char numeric? c)) %acc))
```
---
    #t

## make-optional-char

### returns a function

```scheme
(procedure? (Token make-optional-char 43 %acc))
```
---
    #t

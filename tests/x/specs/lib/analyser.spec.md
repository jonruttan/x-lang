# @lib ../tests/x/lib/analyser.x
# @weight 1

Analyser (`lib/x/reader/analyser.x`) is the tokenizer state-builder vocabulary. The
builders are `Analyser` methods (called at setup); the terminators (accept /
accept-inclusive / reject) are registered under catalog ns `token` for
reader-context callers to fetch. The harness caches `%acc` / `%rej`.

## Analyser accept

### the accept terminator is a function

```scheme
(procedure? %acc)
```
---
    #t

## Analyser reject

### the reject terminator is a function

```scheme
(procedure? %rej)
```
---
    #t

## make-digit-state

### returns a function

```scheme
(procedure? (Analyser make-digit-state %acc))
```
---
    #t

## make-xdigit-state

### returns a function

```scheme
(procedure? (Analyser make-xdigit-state %acc))
```
---
    #t

## make-char-state

### returns a function

```scheme
(procedure? (Analyser make-char-state 65 %acc ()))
```
---
    #t

## make-pred-state

### returns a function

```scheme
(procedure? (Analyser make-pred-state (fn (_ c) (Char alphabetic? c)) %acc))
```
---
    #t

## make-range-state

### returns a function

```scheme
(procedure? (Analyser make-range-state 48 57 %acc))
```
---
    #t

## make-alt-state

### returns a function

```scheme
(procedure? (Analyser make-alt-state %acc %rej))
```
---
    #t

## make-str-state

### returns a function

```scheme
(procedure? (Analyser make-str-state "abc" %acc ()))
```
---
    #t

## make-count-state

### returns a function for n=3

```scheme
(procedure? (Analyser make-count-state 3 (fn (_ c) (Char numeric? c)) %acc))
```
---
    #t

### returns done directly for n=0

```scheme
(eq? (Analyser make-count-state 0 (fn (_ c) (Char numeric? c)) %acc) %acc)
```
---
    #t

## make-min-state

### returns a function

```scheme
(procedure? (Analyser make-min-state 1 (fn (_ c) (Char numeric? c)) %acc))
```
---
    #t

## make-optional-char

### returns a function

```scheme
(procedure? (Analyser make-optional-char 43 %acc))
```
---
    #t

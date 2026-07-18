# @lib ../tests/x/lib/assert.x

The `assert.x` test-support helpers (`throws?` / `raised`). These ARE the
suite's own error assertions, so they are meta-tested here for BOTH branches:
a helper that always returned the same value would be a silent no-op that could
never fail a real test.

## throws?

### returns #t when the thunk raises

```scheme
(throws? (fn (_) (error "boom")))
```
---
    #t

### returns #f when the thunk returns normally

```scheme
(throws? (fn (_) 42))
```
---
    #f

### returns #f for a thunk that returns nil (nil-return is NOT a raise)

```scheme
(throws? (fn (_) ()))
```
---
    #f

## raised

### returns the value handed to error

```scheme
(raised (fn (_) (error "boom")))
```
---
    "boom"

### returns a non-string raised value verbatim

```scheme
(raised (fn (_) (error 99)))
```
---
    99

### returns the %no-raise sentinel when nothing is raised

```scheme
(eq? (raised (fn (_) 42)) (lit %no-raise))
```
---
    #t

## shipped under lib (importable by user code)

### throws? via (import x/test/assert)

```scheme
(do (import x/test/assert) (throws? (fn (_) (error "boom"))))
```
---
    #t

### raised exposes the error value

```scheme
(do (import x/test/assert) (raised (fn (_) (error "boom"))))
```
---
    "boom"

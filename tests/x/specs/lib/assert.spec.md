# @lib ../tests/x/lib/assert.x
# @weight 1

The `assert.x` test-support helpers (`throws?` / `raised`). These ARE the
suite's own error assertions, so they are meta-tested here for BOTH branches:
a helper that always returned the same value would be a silent no-op that could
never fail a real test.

## throws?

### returns #t when the thunk raises

```x
(throws? (fn (_) (error "boom")))
```
---
    #t

### returns #f when the thunk returns normally

```x
(throws? (fn (_) 42))
```
---
    #f

### returns #f for a thunk that returns nil (nil-return is NOT a raise)

```x
(throws? (fn (_) ()))
```
---
    #f

## raised

### returns the value handed to error

```x
(raised (fn (_) (error "boom")))
```
---
    "boom"

### returns a non-string raised value verbatim

```x
(raised (fn (_) (error 99)))
```
---
    99

### returns the %no-raise sentinel when nothing is raised

```x
(eq? (raised (fn (_) 42)) '%no-raise)
```
---
    #t

## shipped under lib (importable by user code)

### throws? via (import x/test/assert)

```x
(do (import x/test/assert) (throws? (fn (_) (error "boom"))))
```
---
    #t

### raised exposes the error value

```x
(do (import x/test/assert) (raised (fn (_) (error "boom"))))
```
---
    "boom"

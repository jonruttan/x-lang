# @lib ../tests/x/lib/assert.x

# Convert: dispatch order + the no-match (silent-nil) policy

`(Convert to VAL TARGET . extra)` dispatches in order: identity (already the
target type) -> exact source in the target's from-alist -> the target's `#t`
wildcard -> target in the source's to-alist -> `(Convert missing)` (default
nil). The silent-nil default is the historical contract; these specs pin it AND
show how to make a miss loud -- the bug class where a missing table entry
returns `()` instead of converting (e.g. the getenv `STR <- ptr` gap).

These complement the char<->int / string<->symbol cases already in
`core/predicates.spec.md`, `core/reader.spec.md`, and `core/strings.spec.md`;
here the focus is the dispatch contract, the radix `extra` arg, and the policy.

## dispatch order

### identity: converting a value to its own type returns it unchanged

```scheme
(Convert to 42 %int)
```
---
    42

### a registered conversion runs (int -> decimal string)

```scheme
(Convert to 255 %string)
```
---
    "255"

### the radix extra arg is threaded through (int -> hex string)

```scheme
(Convert to 255 %string 16)
```
---
    "ff"

### and the inverse parses with the radix (hex string -> int)

```scheme
(Convert to "ff" %int 16)
```
---
    255

### a symbol/string roundtrip preserves the name

```scheme
(Convert to (Convert to 'hi %string) %symbol)
```
---
    'hi

### a nil value converts to nil (absence stays absence)

```scheme
(Convert to () %int)
```
---

## the no-match policy (the silent-nil class)

### an unregistered conversion returns nil by DEFAULT (silent)

```scheme
(null? (Convert to 42 %symbol))
```
---
    #t

### a custom (Convert missing) makes a miss loud -- and is restorable

```scheme
(do
  (def %orig (Convert missing))
  (Convert missing (fn (_ v t) (error "no conversion")))
  (def %caught (throws? (fn (_) (Convert to 42 %symbol))))
  (Convert missing %orig)
  %caught)
```
---
    #t

### the default policy is restored afterward (no leak to later tests)

```scheme
(null? (Convert to 42 %symbol))
```
---
    #t

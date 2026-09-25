# @lib ../tests/x/lib/assert.x
# @weight 1

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

```x
(Convert to 42 (Type named INTEGER))
```
---
    42

### a registered conversion runs (int -> decimal string)

```x
(Convert to 255 (Type named STRING))
```
---
    "255"

### the radix extra arg is threaded through (int -> hex string)

```x
(Convert to 255 (Type named STRING) 16)
```
---
    "ff"

### and the inverse parses with the radix (hex string -> int)

```x
(Convert to "ff" (Type named INTEGER) 16)
```
---
    255

### a symbol/string roundtrip preserves the name

```x
(Convert to (Convert to 'hi (Type named STRING)) (Type named SYMBOL))
```
---
    'hi

### a nil value converts to nil (absence stays absence)

```x
(Convert to () (Type named INTEGER))
```
---

## the no-match policy (the silent-nil class)

### an unregistered conversion returns nil by DEFAULT (silent)

```x
(null? (Convert to 42 (Type named SYMBOL)))
```
---
    #t

### a custom (Convert missing) makes a miss loud -- and is restorable

```x
(do
  (def %orig (Convert missing))
  (Convert missing (fn (_ v t) (error "no conversion")))
  (def %caught (throws? (fn (_) (Convert to 42 (Type named SYMBOL)))))
  (Convert missing %orig)
  %caught)
```
---
    #t

### the default policy is restored afterward (no leak to later tests)

```x
(null? (Convert to 42 (Type named SYMBOL)))
```
---
    #t

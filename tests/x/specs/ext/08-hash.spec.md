# @lib ../tests/x/lib/hash.x

## fnv-1a

### hashes empty string

```scheme
(not (null? (fnv-1a "")))
```
---
    #t

### hashes non-empty string

```scheme
(not (null? (fnv-1a "hello")))
```
---
    #t

### same input same hash

```scheme
(= (fnv-1a "test") (fnv-1a "test"))
```
---
    #t

### different input different hash

```scheme
(if (= (fnv-1a "a") (fnv-1a "b")) "same" "diff")
```
---
    "diff"

## hash->hex

### produces hex string

```scheme
(str-length (hash->hex (fnv-1a "hello")))
```
---
    16

### consistent output

```scheme
(str=? (hash->hex (fnv-1a "test")) (hash->hex (fnv-1a "test")))
```
---
    #t

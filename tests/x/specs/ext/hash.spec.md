# @lib ../tests/x/lib/hash.x

## fnv-1a

### hashes empty string

```scheme
(not (null? (Hash fnv-1a "")))
```
---
    #t

### hashes non-empty string

```scheme
(not (null? (Hash fnv-1a "hello")))
```
---
    #t

### same input same hash

```scheme
(= (Hash fnv-1a "test") (Hash fnv-1a "test"))
```
---
    #t

### different input different hash

```scheme
(if (= (Hash fnv-1a "a") (Hash fnv-1a "b")) "same" "diff")
```
---
    "diff"

## hash->hex

### produces hex string

```scheme
(str-length (Hash hash->hex (Hash fnv-1a "hello")))
```
---
    16

### consistent output

```scheme
(str=? (Hash hash->hex (Hash fnv-1a "test")) (Hash hash->hex (Hash fnv-1a "test")))
```
---
    #t

# @lib ../tests/x/lib/hash.x
# @weight 1

## fnv-1a

### hashes empty string

```x
(not (null? (Hash fnv-1a "")))
```
---
    #t

### hashes non-empty string

```x
(not (null? (Hash fnv-1a "hello")))
```
---
    #t

### same input same hash

```x
(= (Hash fnv-1a "test") (Hash fnv-1a "test"))
```
---
    #t

### different input different hash

```x
(if (= (Hash fnv-1a "a") (Hash fnv-1a "b")) "same" "diff")
```
---
    "diff"

## ->hex

### produces hex string

```x
(%str-length (Hash ->hex (Hash fnv-1a "hello")))
```
---
    16

### consistent output

```x
(str=? (Hash ->hex (Hash fnv-1a "test")) (Hash ->hex (Hash fnv-1a "test")))
```
---
    #t

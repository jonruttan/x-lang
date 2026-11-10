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

Two digits a byte of the word: 16 on an 8-byte word, 8 on a 4-byte one.

```x
(= (%str-length (Hash ->hex (Hash fnv-1a "hello")))
   (if (< %word-size 8) 8 16))
```
---
    #t

### consistent output

```x
(str=? (Hash ->hex (Hash fnv-1a "test")) (Hash ->hex (Hash fnv-1a "test")))
```
---
    #t

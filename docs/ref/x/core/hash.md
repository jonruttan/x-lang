[← Index](../../index.md)

# x/core/hash

FNV-1a hash function for strings.

## Hashing

### `fnv-1a`

Hash a string to a 64-bit integer using the FNV-1a algorithm.

**Parameters:**

- **s** : `STRING` — String to hash

**Returns:** `INTEGER` — 64-bit FNV-1a hash value

### `hash->hex`

Convert a 64-bit signed integer to a 16-character unsigned hex string.

**Parameters:**

- **n** : `INTEGER` — 64-bit signed hash value

**Returns:** `STRING` — 16-character hexadecimal string


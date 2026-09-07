# UTF-8 code-point layer (StrUtf8 ->list / list->str)
# @weight 1

`str->list` decodes a UTF-8 string into a list of code-point CHARACTERs and
`list->str` re-encodes it; they are exact inverses (`lib/x/type/str-utf8.x` over
the `x/codec/utf8` codec). These exercise the 1/2/3-byte sequence paths that are
fragile and previously had no dedicated round-trip coverage. The named byte API
(`str-length`) stays byte-level, which is what makes the byte-vs-code-point
distinction below assertable.

Sample chars: `$` = U+0024 (1 byte), `¢` = U+00A2 (2 bytes), `€` = U+20AC (3 bytes).

## str->list (decode)

### counts code points, not bytes

Value, not length: a count of 3 is true even if the bytes were regrouped
incorrectly.

```x
(StrUtf8 ->list "$¢€")
```
---
    (#\$ #\¢ #\€)

### byte length is larger than the code-point count

```x
(%str-length "$¢€")
```
---
    6

### a 2-byte code point inside ASCII counts once (café = 4 code points)

```x
(StrUtf8 ->list "café")
```
---
    (#\c #\a #\f #\é)

### empty string decodes to the empty list

```x
(StrUtf8 ->list "")
```
---

## list->str (encode) and round-trip

### the documented example builds a UTF-8 string

```x
(StrUtf8 ->str (list #\$ #\€))
```
---
    "$€"

### str->list then list->str round-trips the string

```x
(StrUtf8 ->str (StrUtf8 ->list "$¢€"))
```
---
    "$¢€"

### the round-trip preserves the exact byte length (no corruption)

```x
(%str-length (StrUtf8 ->str (StrUtf8 ->list "¢€")))
```
---
    5

## the value-call indexes; it does not answer a length

### a call with no index raises

A string's value-call is indexing, so a call naming no index is an index call
that named nothing -- the same answer `(v)` gives on a vector. It used to
answer the code-point length, which made `(x-version)` look like an accessor.

```x
(guard (e e) ("héllo"))
```
---
    "string: call with no index -- (Str length s) is the length"

### one index is still the code point there

```x
("héllo" 1)
```
---
    #\é

### two indices are still the substring

```x
("héllo" 1 3)
```
---
    "éll"

### the length doors say which unit they mean

```x
(list (Str length "héllo") (Str8 length "héllo"))
```
---
    (5 6)

### the code-point counter is published on the catalog for the boot printer

`write-fits?` decides every line break in the formatter and needs code points,
but the printer loads long before the UTF-8 layer, so it resolves the counter
through the catalog and falls back to bytes when it is absent.

```x
(list ((prim-ref 'str 'cp-len) "héllo")
      ((prim-ref 'io 'write-fits?) "héllo" 6)
      ((prim-ref 'io 'write-fits?) "héllo" 20))
```
---
    (5 #f #t)

# UTF-8 code-point layer (str->list / list->str)

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

```scheme
(str->list "$¢€")
```
---
    (#\$ #\¢ #\€)

### byte length is larger than the code-point count

```scheme
(%str-length "$¢€")
```
---
    6

### a 2-byte code point inside ASCII counts once (café = 4 code points)

```scheme
(str->list "café")
```
---
    (#\c #\a #\f #\é)

### empty string decodes to the empty list

```scheme
(str->list "")
```
---

## list->str (encode) and round-trip

### the documented example builds a UTF-8 string

```scheme
(list->str (list #\$ #\€))
```
---
    "$€"

### str->list then list->str round-trips the string

```scheme
(list->str (str->list "$¢€"))
```
---
    "$¢€"

### the round-trip preserves the exact byte length (no corruption)

```scheme
(%str-length (list->str (str->list "¢€")))
```
---
    5

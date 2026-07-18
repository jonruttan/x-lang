# Sequence Protocol

`Seq` is a base class whose derived operations (`count`, `->list`, `each`,
`fold`) are written once in terms of three cursor primitives (`start`, `done?`,
`step`). Subclasses supply only the primitives; the derived API is polymorphic
through static-method dispatch (`self` is the class). `Str8` is the byte view of
a string; `StrUTF8` overrides the primitives to walk code points.

## byte view (Str8)

### length counts bytes

```x
(do (import x/protocol/str/str8) (Str8 length "$¢€"))
```
---
    6

### ->list yields one character per byte

```x
(do (import x/protocol/str/str8) (length (Str8 ->list "$¢€")))
```
---
    6

### ref is O(1) indexed access

```x
(do (import x/protocol/str/str8) (Str8 ref 1 "ABC"))
```
---
    #\B

## code-point view (StrUTF8)

### length counts code points, not bytes

```x
(do (import x/protocol/str/utf8) (StrUTF8 length "$¢€"))
```
---
    3

### ->list decodes UTF-8 code points

```x
(do (import x/protocol/str/utf8) (StrUTF8 ->list "$¢€"))
```
---
    (#\$ #\¢ #\€)

### ASCII agrees with the byte view

```x
(do (import x/protocol/str/utf8) (StrUTF8 length "hello"))
```
---
    5

### ref returns the i-th code point (O(n) index)

```x
(do (import x/protocol/str/utf8) (StrUTF8 ref 1 "$¢£¥€¤"))
```
---
    #\¢

### ref reaches a later multi-byte code point

```x
(do (import x/protocol/str/utf8) (StrUTF8 ref 4 "$¢£¥€¤"))
```
---
    #\€

### code-point ref differs from the byte-level str-ref

```x
(do
  (import x/protocol/str/utf8)
  (list (StrUTF8 ref 0 "¢") (str-ref "¢" 0)))
```
---
    (#\¢ #\Â)

## polymorphism

### the same derived ->list walks bytes or code points by class

```x
(do
  (import x/protocol/str/utf8)
  (list (length (Str8 ->list "€")) (length (StrUTF8 ->list "€"))))
```
---
    (3 1)

### count is inherited from Seq and dispatches to the subclass step

```x
(do (import x/protocol/str/utf8) (StrUTF8 count "$¢€"))
```
---
    3

### fold is inherited and threads an accumulator

```x
(do
  (import x/protocol/str/utf8)
  (StrUTF8 fold (fn (_ a c) (+ a (Char ->int c))) 0 "AB"))
```
---
    131

## encode (->str, the inverse of ->list)

### ->str encodes code-point characters to a UTF-8 string

```x
(do (import x/protocol/str/utf8) (StrUTF8 ->str (list #\$ #\¢ #\€)))
```
---
    "$¢€"

### ->str round-trips ->list for any UTF-8 string

```x
(do
  (import x/protocol/str/utf8)
  (str=? (StrUTF8 ->str (StrUTF8 ->list "$¢£¥€¤")) "$¢£¥€¤"))
```
---
    #t

### the byte view round-trips too (identity on bytes)

```x
(do (import x/protocol/str/utf8) (Str ->str (Str ->list "abc")))
```
---
    "abc"

### char->bytes gives a code point's UTF-8 bytes

```x
(do (import x/protocol/str/utf8) (StrUTF8 char->bytes #\€))
```
---
    (226 130 172)

## value-call dispatch (subject-last through Seq)

### fold value-calls route the string as the subject

```x
(do (import x/protocol/str/utf8) ("abc" fold (fn (_ a c) (+ a 1)) 0))
```
---
    3

### for-each value-calls route too

```x
(do
  (import x/protocol/str/utf8)
  (def n 0)
  ("ab" for-each (fn (_ c) (set! n (+ n 1))))
  n)
```
---
    2

### count value-calls stay correct

```x
(do (import x/protocol/str/utf8) ("$¢€" count))
```
---
    3

# Sequence Protocol

`Seq` is a base class whose derived operations (`count`, `->list`, `each`,
`fold`) are written once in terms of three cursor primitives (`start`, `done?`,
`step`). Subclasses supply only the primitives; the derived API is polymorphic
through static-method dispatch (`self` is the class). `Str` is the byte view of
a string; `Utf8` overrides one primitive (`step`) to walk code points.

## byte view (Str)

### length counts bytes

```x
(do (import x/protocol/str/str) (Str length "$¢€"))
```
---
    6

### ->list yields one character per byte

```x
(do (import x/protocol/str/str) (length (Str ->list "$¢€")))
```
---
    6

### ref is O(1) indexed access

```x
(do (import x/protocol/str/str) (Str ref "ABC" 1))
```
---
    #\B

## code-point view (Utf8)

### length counts code points, not bytes

```x
(do (import x/protocol/str/utf8) (Utf8 length "$¢€"))
```
---
    3

### ->list decodes UTF-8 code points

```x
(do (import x/protocol/str/utf8) (Utf8 ->list "$¢€"))
```
---
    (#\$ #\¢ #\€)

### ASCII agrees with the byte view

```x
(do (import x/protocol/str/utf8) (Utf8 length "hello"))
```
---
    5

## polymorphism

### the same derived ->list walks bytes or code points by class

```x
(do
  (import x/protocol/str/utf8)
  (list (length (Str ->list "€")) (length (Utf8 ->list "€"))))
```
---
    (3 1)

### count is inherited from Seq and dispatches to the subclass step

```x
(do (import x/protocol/str/utf8) (Utf8 count "héllo"))
```
---
    5

### fold is inherited and threads an accumulator

```x
(do
  (import x/protocol/str/utf8)
  (Utf8 fold "AB" (fn (_ a c) (+ a (char->integer c))) 0))
```
---
    131

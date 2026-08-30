# Byte-level string primitives
# @weight 1

The `str` catalog: byte length, byte indexing, byte substrings and
string-to-symbol interning.  These are the layer the UTF-8 codec is built on,
so they are deliberately BYTE-oriented -- `str byte-len` counts bytes, not
code points, and that difference is the whole reason this layer exists.

The `str` namespace is de-registered, so these have no bare binding and are
reached through the catalog.

## str byte-len

### counts bytes in a string

```scheme
((prim-ref 'str 'byte-len) "hello")
```
---
    5

### an empty string is zero bytes

```scheme
((prim-ref 'str 'byte-len) "")
```
---
    0

### counts BYTES, not code points

A two-byte code point makes the byte length exceed the character length; this
is the property the UTF-8 layer above depends on.

```scheme
((prim-ref 'str 'byte-len) "héllo")
```
---
    6

## str byte-ref

### indexes a byte, zero-based

```scheme
((prim-ref 'str 'byte-ref) "hello" 0)
```
---
    #\h

### a negative index counts from the end

```scheme
((prim-ref 'str 'byte-ref) "hello" -1)
```
---
    #\o

### the result is a CHARACTER, not a one-byte string

```scheme
(char? ((prim-ref 'str 'byte-ref) "hello" 0))
```
---
    #t

## str byte-sub

### takes a LENGTH, not an end index

`(str byte-sub s 1 2)` is two bytes from offset one -- not bytes one through
two.  Reading the third argument as an end index is the reachable mistake here.

```scheme
((prim-ref 'str 'byte-sub) "hello" 1 2)
```
---
    "el"

### a zero length yields the empty string

```scheme
((prim-ref 'str 'byte-sub) "hello" 0 0)
```
---
    ""

### a run reaching the end of the string

```scheme
((prim-ref 'str 'byte-sub) "hello" 3 2)
```
---
    "lo"

## str ->sym

### converts a string to a symbol of the same name

```scheme
((prim-ref 'str '->sym) "hello")
```
---
    'hello

### the symbol is INTERNED: equal names are the same object

```scheme
(do
  (def %a ((prim-ref 'str '->sym) "hello"))
  (eq? %a ((prim-ref 'str '->sym) "hello")))
```
---
    #t

### round-trips through sym ->str

```scheme
((prim-ref 'sym '->str) ((prim-ref 'str '->sym) "round"))
```
---
    "round"

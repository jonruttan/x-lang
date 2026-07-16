# Buffer reading (Buf)

Buffer construction from x-lang is back: `(buf make s)` (catalog ns `buf` is
de-registered, so fetch via `prim-ref`) wraps a BUFFER around a string's
bytes -- non-owning, the wrap rule -- and `(str make n)` provides the
GC-owned backing region. Both cursors start at the base, so the working
pattern is append-then-read: `Buf append` advances the write cursor,
`Buf read` walks the read cursor behind it, and `Buf tok` returns the
consumed bytes.

A `(buf make)` view is NOT read-only: this is the tokenizer's type, and
`Buf read` on an exhausted non-RO buffer extends from stdin rather than
returning `()`. The spec harness feeds specs through stdin, so
end-of-input cases would block on (or eat) the harness input -- they stay
**pending** below. (A test with no `---` separator is counted *pending*,
not run -- see tests/spec-format.md.)

## Buf construction & reading

### construction yields a BUFFER

```scheme
(Type name ((prim-ref (lit buf) (lit make)) ((prim-ref (lit str) (lit make)) 8)))
```
---
    "BUFFER"

### append then read advances; tok returns the consumed bytes

```scheme
(do
  (def %b ((prim-ref (lit buf) (lit make)) ((prim-ref (lit str) (lit make)) 8)))
  (Buf append %b #\h) (Buf append %b #\i)
  (Buf read %b) (Buf read %b)
  (Buf tok %b))
```
---
    "hi"

### reads the whole appended input in order

```scheme
(do
  (def %b ((prim-ref (lit buf) (lit make)) ((prim-ref (lit str) (lit make)) 8)))
  (Buf append %b #\a) (Buf append %b #\b) (Buf append %b #\c)
  (Buf read %b) (Buf read %b) (Buf read %b)
  (Buf tok %b))
```
---
    "abc"

### tok covers only the consumed portion, not appended-but-unread bytes

```scheme
(do
  (def %b ((prim-ref (lit buf) (lit make)) ((prim-ref (lit str) (lit make)) 8)))
  (Buf append %b #\x) (Buf append %b #\y)
  (Buf read %b)
  (Buf tok %b))
```
---
    "x"

### last-char reports the last byte consumed, as its code

```scheme
(do
  (def %b ((prim-ref (lit buf) (lit make)) ((prim-ref (lit str) (lit make)) 8)))
  (Buf append %b #\h) (Buf append %b #\i)
  (Buf read %b) (Buf read %b)
  (Buf last-char %b))
```
---
    105

### reset empties the buffer (tok becomes zero-length)

```scheme
(do
  (def %b ((prim-ref (lit buf) (lit make)) ((prim-ref (lit str) (lit make)) 8)))
  (Buf append %b #\z) (Buf read %b)
  (Buf reset %b)
  (str-length (Buf tok %b)))
```
---
    0

### retain compacts unread bytes to the front of the backing string

```scheme
(do
  (def %s ((prim-ref (lit str) (lit make)) 8))
  (def %b ((prim-ref (lit buf) (lit make)) %s))
  (Buf append %b #\a) (Buf append %b #\b) (Buf append %b #\c)
  (Buf read %b)
  (Buf retain %b)
  (str-ref %s 0))
```
---
    #\b

### read-text treats a NUL byte as end-of-input

```scheme
(do
  (def %b ((prim-ref (lit buf) (lit make)) ((prim-ref (lit str) (lit make)) 8)))
  (Buf append %b #\x)
  (Buf append %b ((prim-ref (lit int) (lit ->char)) 0))
  (list (null? (Buf read-text %b)) (null? (Buf read-text %b))))
```
---
    (#f #t)

## End-of-input -- PENDING

These stay pending: a `(buf make)` view is non-read-only, so an exhausted
`Buf read` extends from stdin (blocking on, or consuming, the harness's
own spec input) instead of returning `()`. The read-only flag
(`X_OBJ_FLAG_RO`) is only set by the C tokenizer's own buffers
(token-read-string) and is not reachable from x-lang construction. When an
RO construction door exists, re-point these at it and add the `---` +
expected block back.

### a read-only view returns () at end of input

```scheme
(null? (do (def %b (Buf make-ro "x")) (Buf read %b) (Buf read %b)))
```

### empty input is an immediately-exhausted buffer

```scheme
(null? (do (def %b (Buf make-ro "")) (Buf read %b)))
```

## Buf type identity

The old `Buf buffer?` predicate is gone (no such method on the class);
type discrimination goes through `(Type name)` instead -- construction
case above pins the "BUFFER" name.

### a buffer's type differs from its backing string's type

```scheme
(str=? (Type name ((prim-ref (lit buf) (lit make)) ((prim-ref (lit str) (lit make)) 4)))
       (Type name "plain string"))
```
---
    #f

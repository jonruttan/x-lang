# Buffer reading (Buf)
# @weight 1

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

```x
(Type name ((prim-ref 'buf 'make) ((prim-ref 'str 'make) 8)))
```
---
    "BUFFER"

### append then read advances; tok returns the consumed bytes

```x
(do
  (def %b ((prim-ref 'buf 'make) ((prim-ref 'str 'make) 8)))
  (Buf append %b #\h) (Buf append %b #\i)
  (Buf read %b) (Buf read %b)
  (Buf tok %b))
```
---
    "hi"

### reads the whole appended input in order

```x
(do
  (def %b ((prim-ref 'buf 'make) ((prim-ref 'str 'make) 8)))
  (Buf append %b #\a) (Buf append %b #\b) (Buf append %b #\c)
  (Buf read %b) (Buf read %b) (Buf read %b)
  (Buf tok %b))
```
---
    "abc"

### tok covers only the consumed portion, not appended-but-unread bytes

```x
(do
  (def %b ((prim-ref 'buf 'make) ((prim-ref 'str 'make) 8)))
  (Buf append %b #\x) (Buf append %b #\y)
  (Buf read %b)
  (Buf tok %b))
```
---
    "x"

### last-char reports the last byte consumed, as its code

```x
(do
  (def %b ((prim-ref 'buf 'make) ((prim-ref 'str 'make) 8)))
  (Buf append %b #\h) (Buf append %b #\i)
  (Buf read %b) (Buf read %b)
  (Buf last-char %b))
```
---
    105

### reset empties the buffer (tok becomes zero-length)

```x
(do
  (def %b ((prim-ref 'buf 'make) ((prim-ref 'str 'make) 8)))
  (Buf append %b #\z) (Buf read %b)
  (Buf reset %b)
  (%str-length (Buf tok %b)))
```
---
    0

### retain compacts unread bytes to the front of the backing string

```x
(do
  (def %s ((prim-ref 'str 'make) 8))
  (def %b ((prim-ref 'buf 'make) %s))
  (Buf append %b #\a) (Buf append %b #\b) (Buf append %b #\c)
  (Buf read %b)
  (Buf retain %b)
  (%str-ref %s 0))
```
---
    #\b

### read-text treats a NUL byte as end-of-input

```x
(do
  (def %b ((prim-ref 'buf 'make) ((prim-ref 'str 'make) 8)))
  (Buf append %b #\x)
  (Buf append %b ((prim-ref 'int '->char) 0))
  (list (null? (Buf read-text %b)) (null? (Buf read-text %b))))
```
---
    (#f #t)

## End-of-input (read-only views)

`(buf make s %obj-flag-ro)` constructs a READ-ONLY view: an exhausted
read returns `()` instead of extending from stdin (which would block on,
or consume, the harness's own spec input).  The flag value comes from the
committed obj-layout descriptor, not a magic number.  Note the write
cursor of a view starts at the BASE: an RO view of "x" must first walk
its write cursor past the content via `Buf append`-free means -- the C
tokenizer does this internally -- so these specs use `Buf tok` semantics:
a fresh RO view has read == write == base, i.e. it is ALREADY exhausted.

### a read-only view returns () at end of input

```x
(null? (do (def %b ((prim-ref 'buf 'make) "x" %obj-flag-ro))
           ((prim-ref 'buf 'read) %b)))
```
---
    #t

### empty input is an immediately-exhausted read-only buffer

```x
(null? (do (def %b ((prim-ref 'buf 'make) "" %obj-flag-ro))
           ((prim-ref 'buf 'read) %b)))
```
---
    #t

## Buf type identity

The old `Buf buffer?` predicate is gone (no such method on the class);
type discrimination goes through `(Type name)` instead -- construction
case above pins the "BUFFER" name.

### a buffer's type differs from its backing string's type

```x
(str=? (Type name ((prim-ref 'buf 'make) ((prim-ref 'str 'make) 4)))
       (Type name "plain string"))
```
---
    #f

## tok read -- deliberately not specced here

`token-read` exposes the tokenizer so a reader hook can pull sub-expressions
mid-parse.  Called from a spec it does not read the buffer it is handed --
it reads the AMBIENT input port, which under this harness is the spec file
being fed to the interpreter.  Handed a buffer over `"(+ 1 2)"` it returned
`('display "<<SEP>>\n")` -- the runner's own separator form, consumed out
from under it -- and the next case died mid-batch.

This is the reader re-entrancy hazard that also keeps `Tok read-str` off
arbitrary source.  Its real call site is inside a reader hook during
`x_token_read`, where the port is the one being parsed; the reader specs cover
that path. Note the C suite tests `token-read-string`, which is a different
primitive -- `x_prim_token_read` itself has no direct test on either side.

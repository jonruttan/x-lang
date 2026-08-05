# @lib ../tests/x/lib/compile.x

The JIT's scratch-memory forms. Arch-tagged: the assembler backend is
ARM64 (x86_64 parity is in progress), so the runner skips this file on
other hosts.

The compiler keeps every value in `x0` as a raw integer, so a compiled
expression cannot hold state across steps — which is what a generated
loop body needs. These forms supply state **without a register
allocator**: the caller passes a raw address (x-lang-side, a string
buffer's data pointer as an integer) and slots are addressed by word
index, so each access is a single scaled-offset `ldr`/`str`.

    (%mem-ref     ADDR INDEX)        word at ADDR[INDEX], INDEX literal
    (%mem-set!    ADDR INDEX VALUE)  store, yields VALUE
    (%mem-ref-at  ADDR IDX-EXPR)     same, index computed at run time
    (%mem-set-at! ADDR IDX-EXPR VAL)

Unchecked by design — this is the raw-pointer tier, the same trust model
as `(obj ref)`: the caller owns the buffer and its bounds.

## constant-index access

### a value round-trips through native code

```scheme
(do
  (def %make-str (prim-ref (lit str) (lit make)))
  (def %str->ptr (prim-ref (lit str) (lit ->ptr)))
  (def %ptr->int (prim-ref (lit ptr) (lit ->int)))
  (def %buf (%make-str 512))
  (def %addr (%ptr->int (%str->ptr %buf)))
  ((compile-asm '(fn (_ a v) (%mem-set! a 3 v))) %addr 123456789)
  (display ((compile-asm '(fn (_ a) (%mem-ref a 3))) %addr)))
```
---
    123456789

### a full 32-bit value survives (the slot is a machine word)

```scheme
(do
  (def %make-str (prim-ref (lit str) (lit make)))
  (def %str->ptr (prim-ref (lit str) (lit ->ptr)))
  (def %ptr->int (prim-ref (lit ptr) (lit ->int)))
  (def %buf (%make-str 512))
  (def %addr (%ptr->int (%str->ptr %buf)))
  ((compile-asm '(fn (_ a v) (%mem-set! a 7 v))) %addr 4294967295)
  (display ((compile-asm '(fn (_ a) (%mem-ref a 7))) %addr)))
```
---
    4294967295

### distinct slots do not interfere

```scheme
(do
  (def %make-str (prim-ref (lit str) (lit make)))
  (def %str->ptr (prim-ref (lit str) (lit ->ptr)))
  (def %ptr->int (prim-ref (lit ptr) (lit ->int)))
  (def %buf (%make-str 512))
  (def %addr (%ptr->int (%str->ptr %buf)))
  ((compile-asm '(fn (_ a) (do (%mem-set! a 1 111) (%mem-set! a 2 222)))) %addr)
  (display ((compile-asm '(fn (_ a) (+ (%mem-ref a 1) (%mem-ref a 2)))) %addr)))
```
---
    333

### a non-literal constant index is refused

```scheme
(display (guard (_ 'raised) (do (compile-asm '(fn (_ a i) (%mem-ref a i))) 'no-raise)))
```
---
    raised

### an out-of-range constant index is refused

The scaled offset is a 12-bit field: 0..4095 words.

```scheme
(display (guard (_ 'raised) (do (compile-asm '(fn (_ a) (%mem-ref a 9000))) 'no-raise)))
```
---
    raised

## runtime-index access

### a computed index reads the slot a constant index wrote

`(& i 15)` is the shape a round loop uses for a 16-word window.

```scheme
(do
  (def %make-str (prim-ref (lit str) (lit make)))
  (def %str->ptr (prim-ref (lit str) (lit ->ptr)))
  (def %ptr->int (prim-ref (lit ptr) (lit ->int)))
  (def %buf (%make-str 512))
  (def %addr (%ptr->int (%str->ptr %buf)))
  ((compile-asm '(fn (_ a v) (%mem-set! a 5 v))) %addr 999)
  (display ((compile-asm '(fn (_ a i) (%mem-ref-at a (& i 15)))) %addr 21)))
```
---
    999

### runtime store and load agree across several slots

```scheme
(do
  (def %make-str (prim-ref (lit str) (lit make)))
  (def %str->ptr (prim-ref (lit str) (lit ->ptr)))
  (def %ptr->int (prim-ref (lit ptr) (lit ->int)))
  (def %buf (%make-str 512))
  (def %addr (%ptr->int (%str->ptr %buf)))
  (def %st (compile-asm '(fn (_ a i v) (%mem-set-at! a i v))))
  (def %ld (compile-asm '(fn (_ a i) (%mem-ref-at a i))))
  (%st %addr 10 4242)
  (%st %addr 11 88)
  (display (+ (%ld %addr 10) (%ld %addr 11))))
```
---
    4330

### a runtime store yields the value it stored

```scheme
(do
  (def %make-str (prim-ref (lit str) (lit make)))
  (def %str->ptr (prim-ref (lit str) (lit ->ptr)))
  (def %ptr->int (prim-ref (lit ptr) (lit ->int)))
  (def %buf (%make-str 512))
  (def %addr (%ptr->int (%str->ptr %buf)))
  (display ((compile-asm '(fn (_ a i v) (%mem-set-at! a i v))) %addr 4 77)))
```
---
    77

## byte-width access

The word family above is the JIT's own scratch state; the byte family is
how a compiled function consumes INPUT -- a message, a codec buffer --
arriving as a string's data pointer. Indices count bytes (no *8), LDRB
zero-extends, STRB stores the low byte.

    (%mem-byte-ref     ADDR INDEX)        (%mem-byte-ref-at  ADDR IDX-EXPR)
    (%mem-byte-set!    ADDR INDEX VALUE)  (%mem-byte-set-at! ADDR IDX-EXPR VALUE)

### a byte written by x-lang is read by the JIT, and vice versa

The two directions go through different code paths (the interpreter's
ptr prims vs the compiled LDRB/STRB), so agreement is evidence neither
is self-consistently wrong.

```scheme
(do
  (def %make-str (prim-ref (lit str) (lit make)))
  (def %str->ptr (prim-ref (lit str) (lit ->ptr)))
  (def %ptr->int (prim-ref (lit ptr) (lit ->int)))
  (def %pset (prim-ref (lit ptr) (lit set!)))
  (def %pref (prim-ref (lit ptr) (lit ref)))
  (def %buf (%make-str 256))
  (def %p (%str->ptr %buf))
  (def %a (%ptr->int %p))
  (%pset %p 11 66 1)
  ((compile-asm '(fn (_ a v) (%mem-byte-set! a 20 v))) %a 200)
  (display (list ((compile-asm '(fn (_ a) (%mem-byte-ref a 11))) %a)
                 (%pref %p 20 1))))
```
---
    (66 200)

### a byte reads zero-extended, never sign-extended

0xFF is 255. A sign-extending load (LDRSB) would answer -1, and every
byte above 0x7F in a digest's message would corrupt the word built from
it.

```scheme
(do
  (def %make-str (prim-ref (lit str) (lit make)))
  (def %str->ptr (prim-ref (lit str) (lit ->ptr)))
  (def %ptr->int (prim-ref (lit ptr) (lit ->int)))
  (def %pset (prim-ref (lit ptr) (lit set!)))
  (def %buf (%make-str 256))
  (def %p (%str->ptr %buf))
  (def %a (%ptr->int %p))
  (%pset %p 30 255 1)
  (display ((compile-asm '(fn (_ a) (%mem-byte-ref a 30))) %a)))
```
---
    255

### a store yields the FULL value while memory takes the low byte

The form's value is the expression's value, same as the word family; the
truncation happens in memory, where STRB ignores everything above bit 7.

```scheme
(do
  (def %make-str (prim-ref (lit str) (lit make)))
  (def %str->ptr (prim-ref (lit str) (lit ->ptr)))
  (def %ptr->int (prim-ref (lit ptr) (lit ->int)))
  (def %pref (prim-ref (lit ptr) (lit ref)))
  (def %buf (%make-str 256))
  (def %p (%str->ptr %buf))
  (def %a (%ptr->int %p))
  (def %yield ((compile-asm '(fn (_ a v) (%mem-byte-set-at! a 21 v))) %a 511))
  (display (list %yield (%pref %p 21 1))))
```
---
    (511 255)

### byte indices address the bytes INSIDE a word slot

Word slot 6 is bytes 48..55, little-endian: the word 258 (0x102) reads
back as byte 2 at 48 and byte 1 at 49. This is the layout contract that
lets one buffer serve both families at once.

```scheme
(do
  (def %make-str (prim-ref (lit str) (lit make)))
  (def %str->ptr (prim-ref (lit str) (lit ->ptr)))
  (def %ptr->int (prim-ref (lit ptr) (lit ->int)))
  (def %buf (%make-str 256))
  (def %a (%ptr->int (%str->ptr %buf)))
  ((compile-asm '(fn (_ a) (%mem-set! a 6 258))) %a)
  (display (list ((compile-asm '(fn (_ a) (%mem-byte-ref a 48))) %a)
                 ((compile-asm '(fn (_ a) (%mem-byte-ref a 49))) %a))))
```
---
    (2 1)

### a computed index walks bytes, not words

```scheme
(do
  (def %make-str (prim-ref (lit str) (lit make)))
  (def %str->ptr (prim-ref (lit str) (lit ->ptr)))
  (def %ptr->int (prim-ref (lit ptr) (lit ->int)))
  (def %pset (prim-ref (lit ptr) (lit set!)))
  (def %buf (%make-str 256))
  (def %p (%str->ptr %buf))
  (def %a (%ptr->int %p))
  (%pset %p 100 7 1)
  (%pset %p 101 9 1)
  (def %ld (compile-asm '(fn (_ a i) (%mem-byte-ref-at a i))))
  (display (+ (%ld %a 100) (%ld %a 101))))
```
---
    16

### a non-literal constant index is refused

```scheme
(display (guard (_ 'raised) (do (compile-asm '(fn (_ a i) (%mem-byte-ref a i))) 'no-raise)))
```
---
    raised

### an out-of-range constant index is refused

imm12 is unscaled here: 0..4095 BYTES, not words.

```scheme
(display (guard (_ 'raised) (do (compile-asm '(fn (_ a) (%mem-byte-ref a 4096))) 'no-raise)))
```
---
    raised

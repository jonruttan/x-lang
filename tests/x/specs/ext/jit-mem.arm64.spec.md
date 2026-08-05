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

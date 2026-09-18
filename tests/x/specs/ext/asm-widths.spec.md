# @lib ../tests/x/lib/asm.x
# @requires native/jit
# @weight 1

Loads and stores at every width.  Untagged on purpose: both backends
(ARM64 and x86-64) take the same mnemonics, so this file runs on every
host and IS the parity contract.

    ldrb  ldrsb   one byte, zero- or sign-extended      strb
    ldrh  ldrsh   two bytes                             strh
    ldrw  ldrsw   four bytes                            strw
    ldr           eight bytes                           str

The operand is `(mem BASE BYTE-OFFSET)` at every width; ARM64 scales the
offset by the width, so it must be a multiple of it.  A load fills all 64
bits of its register, and a store writes its width and nothing past it.

Each case below builds its function over a string buffer's bytes: `x0`
is the buffer's address and `x1` the value a store writes.

## loads

### a byte: zero-extended, then sign-extended either way

```x
(do
  (def %make-str (prim-ref 'str 'make))
  (def %str->ptr (prim-ref 'str '->ptr))
  (def %ptr->int (prim-ref 'ptr '->int))
  (def %ptr-set! (prim-ref 'ptr 'set!))
  (def %p (%str->ptr (%make-str 64)))
  (%ptr-set! %p 0 255 1)
  (%ptr-set! %p 1 127 1)
  (def load
    (fn (_ op off)
      (do (def a (asm-new))
          (asm-emit! a op x0 (mem x0 off))
          (asm-emit! a 'ret)
          (def r (Ptr call (asm-finalize! a) (%ptr->int %p) 0))
          (asm-free! a)
          r)))
  (display (list (load 'ldrb 0) (load 'ldrsb 0) (load 'ldrsb 1))))
```
---
    (255 -1 127)

### a halfword, and one at an offset past the first

```x
(do
  (def %make-str (prim-ref 'str 'make))
  (def %str->ptr (prim-ref 'str '->ptr))
  (def %ptr->int (prim-ref 'ptr '->int))
  (def %ptr-set! (prim-ref 'ptr 'set!))
  (def %p (%str->ptr (%make-str 64)))
  (%ptr-set! %p 0 65535 2)
  (%ptr-set! %p 2 4660 2)
  (def load
    (fn (_ op off)
      (do (def a (asm-new))
          (asm-emit! a op x0 (mem x0 off))
          (asm-emit! a 'ret)
          (def r (Ptr call (asm-finalize! a) (%ptr->int %p) 0))
          (asm-free! a)
          r)))
  (display (list (load 'ldrh 0) (load 'ldrsh 0) (load 'ldrh 2) (load 'ldrsh 2))))
```
---
    (65535 -1 4660 4660)

### a word clears the upper half the address was in

```x
(do
  (def %make-str (prim-ref 'str 'make))
  (def %str->ptr (prim-ref 'str '->ptr))
  (def %ptr->int (prim-ref 'ptr '->int))
  (def %ptr-set! (prim-ref 'ptr 'set!))
  (def %p (%str->ptr (%make-str 64)))
  (%ptr-set! %p 0 4294967295 4)
  (%ptr-set! %p 4 305419896 4)
  (def load
    (fn (_ op off)
      (do (def a (asm-new))
          (asm-emit! a op x0 (mem x0 off))
          (asm-emit! a 'ret)
          (def r (Ptr call (asm-finalize! a) (%ptr->int %p) 0))
          (asm-free! a)
          r)))
  (display (list (load 'ldrw 0) (load 'ldrsw 0) (load 'ldrw 4) (load 'ldrsw 4))))
```
---
    (4294967295 -1 305419896 305419896)

## stores

### each writes its width and leaves the next byte alone

```x
(do
  (def %make-str (prim-ref 'str 'make))
  (def %str->ptr (prim-ref 'str '->ptr))
  (def %ptr->int (prim-ref 'ptr '->int))
  (def %ptr-set! (prim-ref 'ptr 'set!))
  (def %ptr-ref (prim-ref 'ptr 'ref))
  (def %p (%str->ptr (%make-str 64)))
  (def fill (fn (self i) (if (< i 16) (do (%ptr-set! %p i 170 1) (self (+ i 1))) ())))
  (fill 0)
  (def store
    (fn (_ op off)
      (do (def a (asm-new))
          (asm-emit! a op x1 (mem x0 off))
          (asm-emit! a 'ret)
          (Ptr call (asm-finalize! a) (%ptr->int %p) 1234605616436508552)
          (asm-free! a))))
  (store 'strb 0)
  (store 'strh 2)
  (store 'strw 8)
  (display (list (%ptr-ref %p 0 1) (%ptr-ref %p 1 1)
                 (%ptr-ref %p 2 2) (%ptr-ref %p 4 1)
                 (%ptr-ref %p 8 4) (%ptr-ref %p 12 1))))
```
---
    (136 170 30600 170 1432778632 170)

### a negative round-trips through each width

```x
(do
  (def %make-str (prim-ref 'str 'make))
  (def %str->ptr (prim-ref 'str '->ptr))
  (def %ptr->int (prim-ref 'ptr '->int))
  (def %p (%str->ptr (%make-str 64)))
  (def trip
    (fn (_ st ld)
      (do (def a (asm-new))
          (asm-emit! a st x1 (mem x0 16))
          (asm-emit! a ld x0 (mem x0 16))
          (asm-emit! a 'ret)
          (def r (Ptr call (asm-finalize! a) (%ptr->int %p) -2))
          (asm-free! a)
          r)))
  (display (list (trip 'strb 'ldrsb) (trip 'strh 'ldrsh) (trip 'strw 'ldrsw)
                 (trip 'strb 'ldrb) (trip 'strh 'ldrh) (trip 'strw 'ldrw))))
```
---
    (-2 -2 -2 254 65534 4294967294)

# @lib ../tests/x/lib/asm.x
# @requires native/jit
# @weight 1

The portable model's `x23` and `x24` are callee-saved on every target:
ARM64's own x23 and x24, x86-64's r15 and rbp, and A32's r8 and r10.
`asm-prologue!` keeps x19-x22 and not these two, so a function that uses
them saves and restores them itself.  Unlabelled on purpose: both
backends take the same mnemonics, so this file runs on every host.

Each function opens with `asm-prologue!`, which puts the first argument in
`x0` on x86-64, and closes with `asm-epilogue!`.

## values

### moved, added, and moved back

```x
(do
  (def a (asm-new))
  (asm-prologue! a)
  (asm-push! a x23)
  (asm-push! a x24)
  (asm-emit! a 'mov x23 x0)
  (asm-emit! a 'mov x24 (imm 2))
  (asm-emit! a 'add x23 x23 x24)
  (asm-emit! a 'mov x0 x23)
  (asm-pop! a x24)
  (asm-pop! a x23)
  (asm-epilogue! a)
  (def f (asm-finalize! a))
  (display (Ptr call f 40 0))
  (asm-free! a))
```
---
    42

### kept across a call that saves and uses them

```x
(do
  (def a (asm-new))
  (asm-prologue! a)
  (asm-push! a x23)
  (asm-push! a x24)
  (asm-emit! a 'mov x23 (imm 40))
  (asm-emit! a 'mov x24 (imm 2))
  (asm-emit! a 'adr x8 (label 'clobber))
  (asm-emit! a 'blr x8)
  (asm-emit! a 'add x0 x23 x24)
  (asm-pop! a x24)
  (asm-pop! a x23)
  (asm-epilogue! a)
  (asm-label! a 'clobber)
  (asm-prologue! a)
  (asm-push! a x23)
  (asm-push! a x24)
  (asm-emit! a 'mov x23 (imm 7))
  (asm-emit! a 'mov x24 (imm 9))
  (asm-pop! a x24)
  (asm-pop! a x23)
  (asm-epilogue! a)
  (def f (asm-finalize! a))
  (display (Ptr call f 0 0))
  (asm-free! a))
```
---
    42

## a memory base

### a store and a load through each

On x86-64 x24 is rbp, whose base has no form without a displacement.

```x
(do
  (def %make-str (prim-ref 'str 'make))
  (def %asm-callee-str->ptr (prim-ref 'str '->ptr))
  (def %asm-callee-ptr->int (prim-ref 'ptr '->int))
  (def %p (%asm-callee-str->ptr (%make-str 64)))
  (def a (asm-new))
  (asm-prologue! a)
  (asm-push! a x23)
  (asm-push! a x24)
  (asm-emit! a 'mov x23 x0)
  (asm-emit! a 'mov x24 x0)
  (asm-emit! a 'str x1 (mem x24 0))
  (asm-emit! a 'ldr x2 (mem x23 0))
  (asm-emit! a 'str x2 (mem x23 8))
  (asm-emit! a 'ldr x0 (mem x24 8))
  (asm-emit! a 'add x0 x0 x2)
  (asm-pop! a x24)
  (asm-pop! a x23)
  (asm-epilogue! a)
  (def f (asm-finalize! a))
  (display (Ptr call f (%asm-callee-ptr->int %p) 21))
  (asm-free! a))
```
---
    42

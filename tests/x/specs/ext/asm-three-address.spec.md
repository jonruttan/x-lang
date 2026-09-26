# @lib ../tests/x/lib/asm.x
# @requires native/jit
# @weight 1

The three-address arithmetic forms: `(add Xd Xn OPERAND)` sets Xd to Xn plus
the operand, a register or an immediate, and `sub` to Xn minus it; Xn keeps
its value.  ARM64 encodes these directly.  x86-64 has only the two-address
form, so its backend moves Xn into Xd first when they differ.  Untagged on
purpose: both backends take the same mnemonics, so this file runs on every
host.

Each function opens with `asm-prologue!`, which puts the first argument in
`x0` on x86-64 (SysV passes it in rdi, and x1 is rsi, the second argument,
already), and closes with `asm-epilogue!`.

## add

### an immediate, into another register

```x
(do
  (def a (asm-new))
  (asm-prologue! a)
  (asm-emit! a 'add x0 x1 (imm 10))
  (asm-epilogue! a)
  (def f (asm-finalize! a))
  (display (Ptr call f 0 32))
  (asm-free! a))
```
---
    42

### an immediate, in place

```x
(do
  (def a (asm-new))
  (asm-prologue! a)
  (asm-emit! a 'add x0 x0 (imm 10))
  (asm-epilogue! a)
  (def f (asm-finalize! a))
  (display (Ptr call f 32 0))
  (asm-free! a))
```
---
    42

### a register, into a third register

```x
(do
  (def a (asm-new))
  (asm-prologue! a)
  (asm-emit! a 'mov x21 x0)
  (asm-emit! a 'add x0 x1 x21)
  (asm-epilogue! a)
  (def f (asm-finalize! a))
  (display (Ptr call f 20 22))
  (asm-free! a))
```
---
    42

## sub

### an immediate, into another register

```x
(do
  (def a (asm-new))
  (asm-prologue! a)
  (asm-emit! a 'sub x0 x1 (imm 8))
  (asm-epilogue! a)
  (def f (asm-finalize! a))
  (display (Ptr call f 0 50))
  (asm-free! a))
```
---
    42

### an immediate, in place

```x
(do
  (def a (asm-new))
  (asm-prologue! a)
  (asm-emit! a 'sub x0 x0 (imm 8))
  (asm-epilogue! a)
  (def f (asm-finalize! a))
  (display (Ptr call f 50 0))
  (asm-free! a))
```
---
    42

### the source register keeps its value

```x
(do
  (def a (asm-new))
  (asm-prologue! a)
  (asm-emit! a 'mov x21 x0)
  (asm-emit! a 'sub x1 x21 (imm 10))
  (asm-emit! a 'add x0 x21 x1)
  (asm-epilogue! a)
  (def f (asm-finalize! a))
  (display (Ptr call f 26 0))
  (asm-free! a))
```
---
    42

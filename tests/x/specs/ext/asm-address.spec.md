# @lib ../tests/x/lib/asm.x
# @requires native/jit
# @weight 1

`(adr Xd (label L))` sets Xd to the address of the label L, worked out from
where the instruction is: ARM64 encodes it as ADR, which reaches a label
within a megabyte either way, and x86-64 as LEA from RIP.  Untagged on
purpose: both backends take the same mnemonic, so this file runs on every
host.

Each function opens with `asm-prologue!`, which puts the first argument in
`x0` on x86-64, and closes with `asm-epilogue!`.

## adr

### a label after it, called through blr

```x
(do
  (def a (asm-new))
  (asm-prologue! a)
  (asm-emit! a 'adr x8 (label 'fn40))
  (asm-emit! a 'blr x8)
  (asm-emit! a 'add x0 x0 (imm 2))
  (asm-epilogue! a)
  (asm-label! a 'fn40)
  (asm-emit! a 'mov x0 (imm 40))
  (asm-emit! a 'ret)
  (def f (asm-finalize! a))
  (display (Ptr call f 0 0))
  (asm-free! a))
```
---
    42

### a label before it, called through blr

```x
(do
  (def a (asm-new))
  (asm-emit! a 'b (label 'main))
  (asm-label! a 'fn7)
  (asm-emit! a 'mov x0 (imm 7))
  (asm-emit! a 'ret)
  (asm-label! a 'main)
  (asm-prologue! a)
  (asm-emit! a 'adr x8 (label 'fn7))
  (asm-emit! a 'blr x8)
  (asm-emit! a 'add x0 x0 (imm 35))
  (asm-epilogue! a)
  (def f (asm-finalize! a))
  (display (Ptr call f 0 0))
  (asm-free! a))
```
---
    42

### two labels' addresses differ by the bytes between them

```x
(do
  (def a (asm-new))
  (asm-prologue! a)
  (asm-emit! a 'adr x0 (label 'p))
  (asm-emit! a 'adr x1 (label 'q))
  (asm-emit! a 'sub x1 x1 x0)
  (asm-emit! a 'mov x0 x1)
  (asm-epilogue! a)
  (def at-p (asm-pos a))
  (asm-label! a 'p)
  (asm-emit! a 'nop)
  (asm-emit! a 'nop)
  (asm-emit! a 'nop)
  (def at-q (asm-pos a))
  (asm-label! a 'q)
  (def f (asm-finalize! a))
  (display (= (Ptr call f 0 0) (- at-q at-p)))
  (asm-free! a))
```
---
    #t

# @lib ../tests/x/lib/asm.x
# @requires native/jit
# @weight 1

SysV AMD64 mirror of asm.arm64.spec.md: arguments arrive in rdi/rsi and the
return value leaves in rax, so scenarios that ride A64's x0 arg-and-return
duality need an explicit `mov rax, rdi` here.

## asm-new

### creates assembler instance

```x
(do (def a (asm-new)) (display (asm-pos a)))
```
---
    0

## ret

### returns first argument

```x
(do (def a (asm-new)) (asm-emit! a 'mov rax rdi) (asm-emit! a 'ret) (def f (asm-finalize! a)) (display (Ptr call f 42 0)) (asm-free! a))
```
---
    42

### returns zero for zero

```x
(do (def a (asm-new)) (asm-emit! a 'mov rax rdi) (asm-emit! a 'ret) (def f (asm-finalize! a)) (display (Ptr call f 0 0)) (asm-free! a))
```
---
    0

## mov immediate

### loads constant into return register

```x
(do (def a (asm-new)) (asm-emit! a 'mov rax (imm 99)) (asm-emit! a 'ret) (def f (asm-finalize! a)) (display (Ptr call f 0 0)) (asm-free! a))
```
---
    99

### loads zero

```x
(do (def a (asm-new)) (asm-emit! a 'mov rax (imm 0)) (asm-emit! a 'ret) (def f (asm-finalize! a)) (display (Ptr call f 999 0)) (asm-free! a))
```
---
    0

## add

### adds two registers

```x
(do (def a (asm-new)) (asm-emit! a 'mov rax rdi) (asm-emit! a 'add rax rsi) (asm-emit! a 'ret) (def f (asm-finalize! a)) (display (Ptr call f 20 22)) (asm-free! a))
```
---
    42

### add immediate

```x
(do (def a (asm-new)) (asm-emit! a 'mov rax rdi) (asm-emit! a 'add rax (imm 10)) (asm-emit! a 'ret) (def f (asm-finalize! a)) (display (Ptr call f 32 0)) (asm-free! a))
```
---
    42

## sub

### subtracts two registers

```x
(do (def a (asm-new)) (asm-emit! a 'mov rax rdi) (asm-emit! a 'sub rax rsi) (asm-emit! a 'ret) (def f (asm-finalize! a)) (display (Ptr call f 100 58)) (asm-free! a))
```
---
    42

### sub immediate

```x
(do (def a (asm-new)) (asm-emit! a 'mov rax rdi) (asm-emit! a 'sub rax (imm 8)) (asm-emit! a 'ret) (def f (asm-finalize! a)) (display (Ptr call f 50 0)) (asm-free! a))
```
---
    42

## nop

### nop does not change registers

```x
(do (def a (asm-new)) (asm-emit! a 'mov rax rdi) (asm-emit! a 'nop) (asm-emit! a 'ret) (def f (asm-finalize! a)) (display (Ptr call f 42 0)) (asm-free! a))
```
---
    42

## branch

### forward branch skips instruction

```x
(do (def a (asm-new)) (asm-emit! a 'mov rax (imm 1)) (asm-emit! a 'b (label 'skip)) (asm-emit! a 'mov rax (imm 99)) (asm-label! a 'skip) (asm-emit! a 'ret) (def f (asm-finalize! a)) (display (Ptr call f 0 0)) (asm-free! a))
```
---
    1

## multi-instruction

### sequence of operations

```x
(do (def a (asm-new)) (asm-emit! a 'mov rax (imm 0)) (asm-emit! a 'add rax rsi) (asm-emit! a 'add rax rsi) (asm-emit! a 'ret) (def f (asm-finalize! a)) (display (Ptr call f 0 21)) (asm-free! a))
```
---
    42

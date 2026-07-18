# @lib ../tests/x/lib/asm.x

## asm-new

### creates assembler instance

```scheme
(do (def a (asm-new)) (display (asm-pos a)))
```
---
    0

## ret

### returns first argument

```scheme
(do (def a (asm-new)) (asm-emit! a 'ret) (def f (asm-finalize! a)) (display (Ptr call f 42 0)) (asm-free! a))
```
---
    42

### returns zero for zero

```scheme
(do (def a (asm-new)) (asm-emit! a 'ret) (def f (asm-finalize! a)) (display (Ptr call f 0 0)) (asm-free! a))
```
---
    0

## mov immediate

### loads constant into return register

```scheme
(do (def a (asm-new)) (asm-emit! a 'mov x0 (imm 99)) (asm-emit! a 'ret) (def f (asm-finalize! a)) (display (Ptr call f 0 0)) (asm-free! a))
```
---
    99

### loads zero

```scheme
(do (def a (asm-new)) (asm-emit! a 'mov x0 (imm 0)) (asm-emit! a 'ret) (def f (asm-finalize! a)) (display (Ptr call f 999 0)) (asm-free! a))
```
---
    0

## add

### adds two registers

```scheme
(do (def a (asm-new)) (asm-emit! a 'add x0 x0 x1) (asm-emit! a 'ret) (def f (asm-finalize! a)) (display (Ptr call f 20 22)) (asm-free! a))
```
---
    42

### add immediate

```scheme
(do (def a (asm-new)) (asm-emit! a 'add x0 x0 (imm 10)) (asm-emit! a 'ret) (def f (asm-finalize! a)) (display (Ptr call f 32 0)) (asm-free! a))
```
---
    42

## sub

### subtracts two registers

```scheme
(do (def a (asm-new)) (asm-emit! a 'sub x0 x0 x1) (asm-emit! a 'ret) (def f (asm-finalize! a)) (display (Ptr call f 100 58)) (asm-free! a))
```
---
    42

### sub immediate

```scheme
(do (def a (asm-new)) (asm-emit! a 'sub x0 x0 (imm 8)) (asm-emit! a 'ret) (def f (asm-finalize! a)) (display (Ptr call f 50 0)) (asm-free! a))
```
---
    42

## nop

### nop does not change registers

```scheme
(do (def a (asm-new)) (asm-emit! a 'nop) (asm-emit! a 'ret) (def f (asm-finalize! a)) (display (Ptr call f 42 0)) (asm-free! a))
```
---
    42

## branch

### forward branch skips instruction

```scheme
(do (def a (asm-new)) (asm-emit! a 'mov x0 (imm 1)) (asm-emit! a 'b (label 'skip)) (asm-emit! a 'mov x0 (imm 99)) (asm-label! a 'skip) (asm-emit! a 'ret) (def f (asm-finalize! a)) (display (Ptr call f 0 0)) (asm-free! a))
```
---
    1

## multi-instruction

### sequence of operations

```scheme
(do (def a (asm-new)) (asm-emit! a 'mov x0 (imm 0)) (asm-emit! a 'add x0 x0 x1) (asm-emit! a 'add x0 x0 x1) (asm-emit! a 'ret) (def f (asm-finalize! a)) (display (Ptr call f 0 21)) (asm-free! a))
```
---
    42

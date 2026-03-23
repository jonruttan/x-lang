# @lib x-base.x

## asm-new

### creates assembler instance

```scheme
(do (include "lib/x/tool/asm.x") (def a (asm-new)) (display (asm-pos a)))
```
---
    0

## ret

### returns first argument

```scheme
(do (include "lib/x/tool/asm.x") (def a (asm-new)) (asm-emit! a (lit ret)) (def f (asm-finalize! a)) (display (ptr-call f 42 0)) (asm-free! a))
```
---
    42

### returns zero for zero

```scheme
(do (include "lib/x/tool/asm.x") (def a (asm-new)) (asm-emit! a (lit ret)) (def f (asm-finalize! a)) (def r (ptr-call f 0 0)) (display (if (null? r) 0 r)) (asm-free! a))
```
---
    0

## mov immediate

### loads constant into return register

```scheme
(do (include "lib/x/tool/asm.x") (def a (asm-new)) (asm-emit! a (lit mov) x0 (imm 99)) (asm-emit! a (lit ret)) (def f (asm-finalize! a)) (display (ptr-call f 0 0)) (asm-free! a))
```
---
    99

### loads zero

```scheme
(do (include "lib/x/tool/asm.x") (def a (asm-new)) (asm-emit! a (lit mov) x0 (imm 0)) (asm-emit! a (lit ret)) (def f (asm-finalize! a)) (display (ptr-call f 999 0)) (asm-free! a))
```
---
    0

## add

### adds two registers

```scheme
(do (include "lib/x/tool/asm.x") (def a (asm-new)) (asm-emit! a (lit add) x0 x0 x1) (asm-emit! a (lit ret)) (def f (asm-finalize! a)) (display (ptr-call f 20 22)) (asm-free! a))
```
---
    42

### add immediate

```scheme
(do (include "lib/x/tool/asm.x") (def a (asm-new)) (asm-emit! a (lit add) x0 x0 (imm 10)) (asm-emit! a (lit ret)) (def f (asm-finalize! a)) (display (ptr-call f 32 0)) (asm-free! a))
```
---
    42

## sub

### subtracts two registers

```scheme
(do (include "lib/x/tool/asm.x") (def a (asm-new)) (asm-emit! a (lit sub) x0 x0 x1) (asm-emit! a (lit ret)) (def f (asm-finalize! a)) (display (ptr-call f 100 58)) (asm-free! a))
```
---
    42

### sub immediate

```scheme
(do (include "lib/x/tool/asm.x") (def a (asm-new)) (asm-emit! a (lit sub) x0 x0 (imm 8)) (asm-emit! a (lit ret)) (def f (asm-finalize! a)) (display (ptr-call f 50 0)) (asm-free! a))
```
---
    42

## nop

### nop does not change registers

```scheme
(do (include "lib/x/tool/asm.x") (def a (asm-new)) (asm-emit! a (lit nop)) (asm-emit! a (lit ret)) (def f (asm-finalize! a)) (display (ptr-call f 42 0)) (asm-free! a))
```
---
    42

## branch

### forward branch skips instruction

```scheme
(do (include "lib/x/tool/asm.x") (def a (asm-new)) (asm-emit! a (lit mov) x0 (imm 1)) (asm-emit! a (lit b) (label (lit skip))) (asm-emit! a (lit mov) x0 (imm 99)) (asm-label! a (lit skip)) (asm-emit! a (lit ret)) (def f (asm-finalize! a)) (display (ptr-call f 0 0)) (asm-free! a))
```
---
    1

## multi-instruction

### sequence of operations

```scheme
(do (include "lib/x/tool/asm.x") (def a (asm-new)) (asm-emit! a (lit mov) x0 (imm 0)) (asm-emit! a (lit add) x0 x0 x1) (asm-emit! a (lit add) x0 x0 x1) (asm-emit! a (lit ret)) (def f (asm-finalize! a)) (display (ptr-call f 0 21)) (asm-free! a))
```
---
    42

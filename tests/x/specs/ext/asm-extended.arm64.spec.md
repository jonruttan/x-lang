# @lib ../tests/x/lib/asm.x

## cmp and conditional branch

### cmp register equal takes b/eq

```scheme
(do (def a (asm-new)) (asm-emit! a 'cmp x0 x1) (asm-emit! a 'b/ne (label 'neq)) (asm-emit! a 'mov x0 (imm 1)) (asm-emit! a 'ret) (asm-label! a 'neq) (asm-emit! a 'mov x0 (imm 0)) (asm-emit! a 'ret) (def f (asm-finalize! a)) (display (Ptr call f 42 42)) (asm-free! a))
```
---
    1

### cmp register unequal takes b/ne

```scheme
(do (def a (asm-new)) (asm-emit! a 'cmp x0 x1) (asm-emit! a 'b/ne (label 'neq)) (asm-emit! a 'mov x0 (imm 1)) (asm-emit! a 'ret) (asm-label! a 'neq) (asm-emit! a 'mov x0 (imm 0)) (asm-emit! a 'ret) (def f (asm-finalize! a)) (display (Ptr call f 10 20)) (asm-free! a))
```
---
    0

### cmp immediate with b/eq

```scheme
(do (def a (asm-new)) (asm-emit! a 'cmp x0 (imm 42)) (asm-emit! a 'b/eq (label 'yes)) (asm-emit! a 'mov x0 (imm 0)) (asm-emit! a 'ret) (asm-label! a 'yes) (asm-emit! a 'mov x0 (imm 1)) (asm-emit! a 'ret) (def f (asm-finalize! a)) (display (Ptr call f 42 0)) (asm-free! a))
```
---
    1

### cmp less-than with b/lt

```scheme
(do (def a (asm-new)) (asm-emit! a 'cmp x0 x1) (asm-emit! a 'b/lt (label 'less)) (asm-emit! a 'mov x0 (imm 0)) (asm-emit! a 'ret) (asm-label! a 'less) (asm-emit! a 'mov x0 (imm 1)) (asm-emit! a 'ret) (def f (asm-finalize! a)) (display (Ptr call f 5 10)) (asm-free! a))
```
---
    1

### cmp greater-than with b/gt

```scheme
(do (def a (asm-new)) (asm-emit! a 'cmp x0 x1) (asm-emit! a 'b/gt (label 'greater)) (asm-emit! a 'mov x0 (imm 0)) (asm-emit! a 'ret) (asm-label! a 'greater) (asm-emit! a 'mov x0 (imm 1)) (asm-emit! a 'ret) (def f (asm-finalize! a)) (display (Ptr call f 20 10)) (asm-free! a))
```
---
    1

## prologue and epilogue

### function with prologue/epilogue preserves frame

```scheme
(do (def a (asm-new)) (asm-prologue! a) (asm-emit! a 'mov x0 (imm 77)) (asm-epilogue! a) (def f (asm-finalize! a)) (display (Ptr call f 0 0)) (asm-free! a))
```
---
    77

## combined operations

### max function via cmp and conditional branch

```scheme
(do (def a (asm-new)) (asm-emit! a 'cmp x0 x1) (asm-emit! a 'b/ge (label 'done)) (asm-emit! a 'mov x0 x1) (asm-label! a 'done) (asm-emit! a 'ret) (def f (asm-finalize! a)) (display (Ptr call f 30 50)) (display " ") (display (Ptr call f 50 30)) (asm-free! a))
```
---
    50 50

### absolute difference

```scheme
(do (def a (asm-new)) (asm-emit! a 'cmp x0 x1) (asm-emit! a 'b/ge (label 'noswap)) (asm-emit! a 'sub x0 x1 x0) (asm-emit! a 'ret) (asm-label! a 'noswap) (asm-emit! a 'sub x0 x0 x1) (asm-emit! a 'ret) (def f (asm-finalize! a)) (display (Ptr call f 10 50)) (display " ") (display (Ptr call f 50 10)) (asm-free! a))
```
---
    40 40

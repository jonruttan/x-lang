# @lib ../tests/x/lib/asm.x

## cmp and conditional branch

### cmp register equal takes b/eq

```scheme
(do (def a (asm-new)) (asm-emit! a (lit cmp) x0 x1) (asm-emit! a (lit b/ne) (label (lit neq))) (asm-emit! a (lit mov) x0 (imm 1)) (asm-emit! a (lit ret)) (asm-label! a (lit neq)) (asm-emit! a (lit mov) x0 (imm 0)) (asm-emit! a (lit ret)) (def f (asm-finalize! a)) (display (Ptr call f 42 42)) (asm-free! a))
```
---
    1

### cmp register unequal takes b/ne

```scheme
(do (def a (asm-new)) (asm-emit! a (lit cmp) x0 x1) (asm-emit! a (lit b/ne) (label (lit neq))) (asm-emit! a (lit mov) x0 (imm 1)) (asm-emit! a (lit ret)) (asm-label! a (lit neq)) (asm-emit! a (lit mov) x0 (imm 0)) (asm-emit! a (lit ret)) (def f (asm-finalize! a)) (display (Ptr call f 10 20)) (asm-free! a))
```
---
    0

### cmp immediate with b/eq

```scheme
(do (def a (asm-new)) (asm-emit! a (lit cmp) x0 (imm 42)) (asm-emit! a (lit b/eq) (label (lit yes))) (asm-emit! a (lit mov) x0 (imm 0)) (asm-emit! a (lit ret)) (asm-label! a (lit yes)) (asm-emit! a (lit mov) x0 (imm 1)) (asm-emit! a (lit ret)) (def f (asm-finalize! a)) (display (Ptr call f 42 0)) (asm-free! a))
```
---
    1

### cmp less-than with b/lt

```scheme
(do (def a (asm-new)) (asm-emit! a (lit cmp) x0 x1) (asm-emit! a (lit b/lt) (label (lit less))) (asm-emit! a (lit mov) x0 (imm 0)) (asm-emit! a (lit ret)) (asm-label! a (lit less)) (asm-emit! a (lit mov) x0 (imm 1)) (asm-emit! a (lit ret)) (def f (asm-finalize! a)) (display (Ptr call f 5 10)) (asm-free! a))
```
---
    1

### cmp greater-than with b/gt

```scheme
(do (def a (asm-new)) (asm-emit! a (lit cmp) x0 x1) (asm-emit! a (lit b/gt) (label (lit greater))) (asm-emit! a (lit mov) x0 (imm 0)) (asm-emit! a (lit ret)) (asm-label! a (lit greater)) (asm-emit! a (lit mov) x0 (imm 1)) (asm-emit! a (lit ret)) (def f (asm-finalize! a)) (display (Ptr call f 20 10)) (asm-free! a))
```
---
    1

## prologue and epilogue

### function with prologue/epilogue preserves frame

```scheme
(do (def a (asm-new)) (asm-prologue! a) (asm-emit! a (lit mov) x0 (imm 77)) (asm-epilogue! a) (def f (asm-finalize! a)) (display (Ptr call f 0 0)) (asm-free! a))
```
---
    77

## combined operations

### max function via cmp and conditional branch

```scheme
(do (def a (asm-new)) (asm-emit! a (lit cmp) x0 x1) (asm-emit! a (lit b/ge) (label (lit done))) (asm-emit! a (lit mov) x0 x1) (asm-label! a (lit done)) (asm-emit! a (lit ret)) (def f (asm-finalize! a)) (display (Ptr call f 30 50)) (display " ") (display (Ptr call f 50 30)) (asm-free! a))
```
---
    50 50

### absolute difference

```scheme
(do (def a (asm-new)) (asm-emit! a (lit cmp) x0 x1) (asm-emit! a (lit b/ge) (label (lit noswap))) (asm-emit! a (lit sub) x0 x1 x0) (asm-emit! a (lit ret)) (asm-label! a (lit noswap)) (asm-emit! a (lit sub) x0 x0 x1) (asm-emit! a (lit ret)) (def f (asm-finalize! a)) (display (Ptr call f 10 50)) (display " ") (display (Ptr call f 50 10)) (asm-free! a))
```
---
    40 40

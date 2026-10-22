# @lib ../tests/x/lib/asm.x
# @requires native/jit
# @weight 1

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
(do (def a (asm-new)) (asm-emit! a 'ret) (def f (asm-finalize! a)) (display (Ptr call f 42 0)) (asm-free! a))
```
---
    42

### returns zero for zero

```x
(do (def a (asm-new)) (asm-emit! a 'ret) (def f (asm-finalize! a)) (display (Ptr call f 0 0)) (asm-free! a))
```
---
    0

## mov immediate

### loads constant into return register

```x
(do (def a (asm-new)) (asm-emit! a 'mov x0 (imm 99)) (asm-emit! a 'ret) (def f (asm-finalize! a)) (display (Ptr call f 0 0)) (asm-free! a))
```
---
    99

### loads zero

```x
(do (def a (asm-new)) (asm-emit! a 'mov x0 (imm 0)) (asm-emit! a 'ret) (def f (asm-finalize! a)) (display (Ptr call f 999 0)) (asm-free! a))
```
---
    0

## add

### adds two registers

```x
(do (def a (asm-new)) (asm-emit! a 'add x0 x0 x1) (asm-emit! a 'ret) (def f (asm-finalize! a)) (display (Ptr call f 20 22)) (asm-free! a))
```
---
    42

### add immediate

```x
(do (def a (asm-new)) (asm-emit! a 'add x0 x0 (imm 10)) (asm-emit! a 'ret) (def f (asm-finalize! a)) (display (Ptr call f 32 0)) (asm-free! a))
```
---
    42

## sub

### subtracts two registers

```x
(do (def a (asm-new)) (asm-emit! a 'sub x0 x0 x1) (asm-emit! a 'ret) (def f (asm-finalize! a)) (display (Ptr call f 100 58)) (asm-free! a))
```
---
    42

### sub immediate

```x
(do (def a (asm-new)) (asm-emit! a 'sub x0 x0 (imm 8)) (asm-emit! a 'ret) (def f (asm-finalize! a)) (display (Ptr call f 50 0)) (asm-free! a))
```
---
    42

## nop

### nop does not change registers

```x
(do (def a (asm-new)) (asm-emit! a 'nop) (asm-emit! a 'ret) (def f (asm-finalize! a)) (display (Ptr call f 42 0)) (asm-free! a))
```
---
    42

## branch

### forward branch skips instruction

```x
(do (def a (asm-new)) (asm-emit! a 'mov x0 (imm 1)) (asm-emit! a 'b (label 'skip)) (asm-emit! a 'mov x0 (imm 99)) (asm-label! a 'skip) (asm-emit! a 'ret) (def f (asm-finalize! a)) (display (Ptr call f 0 0)) (asm-free! a))
```
---
    1

### a program of more labels than a list walk finds each

Forty labels, each branched to, are more than finalize walks as a list, so
it indexes them; a name placed twice resolves to its last place, as the
list walk found it.

```x
(do
  (def a (asm-new))
  (def lab (fn (_ i) (Str8 ->sym (Str8 repeat (+ i 1) "l"))))
  (asm-emit! a 'mov x0 (imm 0))
  (def hop (fn (self i) (if (= i 40) () (do (asm-emit! a 'b (label (lab i))) (asm-emit! a 'add x0 x0 (imm 100)) (asm-label! a (lab i)) (asm-emit! a 'add x0 x0 (imm 1)) (self (+ i 1))))))
  (hop 0)
  (asm-emit! a 'b (label 'twice))
  (asm-label! a 'twice)
  (asm-emit! a 'add x0 x0 (imm 1000))
  (asm-label! a 'twice)
  (asm-emit! a 'ret)
  (def f (asm-finalize! a))
  (display (Ptr call f 0 0))
  (asm-free! a))
```
---
    40

## multi-instruction

### sequence of operations

```x
(do (def a (asm-new)) (asm-emit! a 'mov x0 (imm 0)) (asm-emit! a 'add x0 x0 x1) (asm-emit! a 'add x0 x0 x1) (asm-emit! a 'ret) (def f (asm-finalize! a)) (display (Ptr call f 0 21)) (asm-free! a))
```
---
    42

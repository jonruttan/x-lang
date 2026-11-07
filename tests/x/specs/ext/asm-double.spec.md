# @lib ../tests/x/lib/asm-double.x
# @requires native/jit
# @weight 1

The scalar double instructions, which lib/x/num/float.x's stubs are made
of, and the conversions to and from a single (a C float).
Unlabelled: every backend lowers the same forms, d0-d7 being the d
registers on ARM and x86-64's xmm registers.  A double travels as its IEEE
754 bit pattern through (Ptr call): in one general register on an 8-byte
word, where the harness moves it with fmov/d and fmov/x, and as two words
on a 4-byte one, where it moves with fmov/d2 and an answer goes out
through a pointer (tests/x/lib/asm-double.x).  Each case reads the same
patterns on either word.  The assembler's prologue is what puts the first
argument in x0.  Bit patterns used: 1.0 4607182418800017408, 2.0
4611686018427387904, 3.0 4613937818241073152, 1.5 4609434218613702656,
0.5 4602678819172646912, -2.5 -4610560118520545280, NaN
9221120237041090560.

## arithmetic

### fadd: 1.0 + 2.0 is 3.0

```x
(do (def a (asm-new)) (asm-prologue! a) (asm-double-in! a d0 0) (asm-double-in! a d1 1) (asm-emit! a 'fadd d0 d0 d1) (asm-double-out! a d0) (asm-epilogue! a) (def f (asm-finalize! a)) (display (asm-double-call/d f 4607182418800017408 4611686018427387904)) (asm-free! a))
```
---
    4613937818241073152

### fsub: 3.0 - 1.0 is 2.0

```x
(do (def a (asm-new)) (asm-prologue! a) (asm-double-in! a d0 0) (asm-double-in! a d1 1) (asm-emit! a 'fsub d0 d0 d1) (asm-double-out! a d0) (asm-epilogue! a) (def f (asm-finalize! a)) (display (asm-double-call/d f 4613937818241073152 4607182418800017408)) (asm-free! a))
```
---
    4611686018427387904

### fmul: 2.0 * 1.5 is 3.0

```x
(do (def a (asm-new)) (asm-prologue! a) (asm-double-in! a d0 0) (asm-double-in! a d1 1) (asm-emit! a 'fmul d0 d0 d1) (asm-double-out! a d0) (asm-epilogue! a) (def f (asm-finalize! a)) (display (asm-double-call/d f 4611686018427387904 4609434218613702656)) (asm-free! a))
```
---
    4613937818241073152

### fdiv: 1.0 / 2.0 is 0.5

```x
(do (def a (asm-new)) (asm-prologue! a) (asm-double-in! a d0 0) (asm-double-in! a d1 1) (asm-emit! a 'fdiv d0 d0 d1) (asm-double-out! a d0) (asm-epilogue! a) (def f (asm-finalize! a)) (display (asm-double-call/d f 4607182418800017408 4611686018427387904)) (asm-free! a))
```
---
    4602678819172646912

### three-address: d2 = (3.0 - 1.0) + 3.0 keeps d0 intact

```x
(do (def a (asm-new)) (asm-prologue! a) (asm-double-in! a d0 0) (asm-double-in! a d1 1) (asm-emit! a 'fsub d2 d0 d1) (asm-emit! a 'fadd d2 d2 d0) (asm-double-out! a d2) (asm-epilogue! a) (def f (asm-finalize! a)) (display (asm-double-call/d f 4613937818241073152 4607182418800017408)) (asm-free! a))
```
---
    4617315517961601024

## conversions

### scvtf: 3 is 3.0

```x
(do (def a (asm-new)) (asm-prologue! a) (asm-emit! a 'scvtf d0 (asm-arg 0)) (asm-double-out! a d0) (asm-epilogue! a) (def f (asm-finalize! a)) (display (asm-double-call/d f 3 0)) (asm-free! a))
```
---
    4613937818241073152

### fcvtzs: -2.5 truncates to -2

```x
(do (def a (asm-new)) (asm-prologue! a) (asm-double-in! a d0 0) (asm-emit! a 'fcvtzs x0 d0) (asm-epilogue! a) (def f (asm-finalize! a)) (display (asm-double-call f -4610560118520545280 0)) (asm-free! a))
```
---
    -2

### fcvt/s: 1.5 as a single is 1.5f, the bits above it zero

On an 8-byte word the single is the low half of d1, which held all ones.

```x
(do (def a (asm-new)) (asm-prologue! a) (asm-double-in! a d0 0) (asm-double-in! a d1 1) (asm-single-out! a d1 d0) (asm-epilogue! a) (def f (asm-finalize! a)) (display (asm-double-call/s f 4609434218613702656 -1)) (asm-free! a))
```
---
    1069547520

### fcvt/s rounds to nearest: 0.1 is 0x3DCCCCCD, 1 + 3/2^25 rounds up

```x
(do (def a (asm-new)) (asm-prologue! a) (asm-double-in! a d0 0) (asm-single-out! a d0 d0) (asm-epilogue! a) (def f (asm-finalize! a)) (display (list (asm-double-call/s f 4591870180066957722 0) (asm-double-call/s f 4607182419202670592 0))) (asm-free! a))
```
---
    (1036831949 1065353217)

### fcvt/s past the single range is infinity

```x
(do (def a (asm-new)) (asm-prologue! a) (asm-double-in! a d0 0) (asm-single-out! a d0 d0) (asm-epilogue! a) (def f (asm-finalize! a)) (display (asm-double-call/s f 5205425776111082661 0)) (asm-free! a))
```
---
    2139095040

### fcvt/d: -2.5f and 0.1f as doubles

```x
(do (def a (asm-new)) (asm-prologue! a) (asm-single-in! a d0 d1 0) (asm-double-out! a d0) (asm-epilogue! a) (def f (asm-finalize! a)) (display (list (asm-double-call/d f 3223322624 0) (asm-double-call/d f 1036831949 0))) (asm-free! a))
```
---
    (-4610560118520545280 4591870180174331904)

### scvtf/s: 3, 16777217 and -5 as singles, the bits above them zero

```x
(do (def a (asm-new)) (asm-prologue! a) (asm-double-in! a d1 1) (asm-int-single-out! a d1 0) (asm-epilogue! a) (def f (asm-finalize! a)) (display (list (asm-double-call/s f 3 -1) (asm-double-call/s f 16777217 -1) (asm-double-call/s f -5 -1))) (asm-free! a))
```
---
    (1077936128 1266679808 3231711232)

### scvtf/s rounds once: an integer just past halfway between singles rounds up

On an 8-byte word, 2^60 + 2^36 + 1, which a trip through a double would
round to the halfway point and then to even, down; on a 4-byte word the
widest an integer gets, 2^30 + 2^6 + 1.

```x
(do (def a (asm-new)) (asm-prologue! a) (asm-int-single-out! a d0 0) (asm-epilogue! a) (def f (asm-finalize! a)) (def wide (int= %word-size 8)) (display (int= (asm-double-call/s f (if wide 1152921573326323713 1073741889) 0) (if wide 1568669697 1317011457))) (asm-free! a))
```
---
    #t

## compare

### flt: 1.0 < 2.0

```x
(do (def a (asm-new)) (asm-prologue! a) (asm-double-in! a d0 0) (asm-double-in! a d1 1) (asm-emit! a 'flt x0 d0 d1) (asm-epilogue! a) (def f (asm-finalize! a)) (display (asm-double-call f 4607182418800017408 4611686018427387904)) (asm-free! a))
```
---
    1

### flt: 2.0 < 1.0 is 0

```x
(do (def a (asm-new)) (asm-prologue! a) (asm-double-in! a d0 0) (asm-double-in! a d1 1) (asm-emit! a 'flt x0 d0 d1) (asm-epilogue! a) (def f (asm-finalize! a)) (display (asm-double-call f 4611686018427387904 4607182418800017408)) (asm-free! a))
```
---
    0

### flt: a NaN operand is 0

```x
(do (def a (asm-new)) (asm-prologue! a) (asm-double-in! a d0 0) (asm-double-in! a d1 1) (asm-emit! a 'flt x0 d0 d1) (asm-epilogue! a) (def f (asm-finalize! a)) (display (asm-double-call f 9221120237041090560 4607182418800017408)) (asm-free! a))
```
---
    0

### feq: 2.0 = 2.0

```x
(do (def a (asm-new)) (asm-prologue! a) (asm-double-in! a d0 0) (asm-double-in! a d1 1) (asm-emit! a 'feq x0 d0 d1) (asm-epilogue! a) (def f (asm-finalize! a)) (display (asm-double-call f 4611686018427387904 4611686018427387904)) (asm-free! a))
```
---
    1

### feq: NaN is not equal to itself

```x
(do (def a (asm-new)) (asm-prologue! a) (asm-double-in! a d0 0) (asm-double-in! a d1 1) (asm-emit! a 'feq x0 d0 d1) (asm-epilogue! a) (def f (asm-finalize! a)) (display (asm-double-call f 9221120237041090560 9221120237041090560)) (asm-free! a))
```
---
    0

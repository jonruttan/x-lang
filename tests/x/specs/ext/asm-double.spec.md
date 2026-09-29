# @lib ../tests/x/lib/asm.x
# @requires native/jit
# @weight 1

The scalar double family, which lib/x/num/float.x's stubs are made of,
and the two conversions to and from a single (a C float), which is the
low 32 bits of a d register with the bits above it zero.
Untagged: both backends lower the same forms, d0-d7 being arm64's d
registers and x86-64's xmm registers.  A double travels as its IEEE 754
bit pattern in a general register, so each case moves the bits in with
fmov/d and the answer out with fmov/x.  The assembler's prologue is what
puts the first argument in x0 on both backends.  Bit patterns used:
1.0 4607182418800017408, 2.0 4611686018427387904, 3.0
4613937818241073152, 1.5 4609434218613702656, 0.5 4602678819172646912,
-2.5 -4610560118520545280, NaN 9221120237041090560.

## arithmetic

### fadd: 1.0 + 2.0 is 3.0

```x
(do (def a (asm-new)) (asm-prologue! a) (asm-emit! a 'fmov/d d0 x0) (asm-emit! a 'fmov/d d1 x1) (asm-emit! a 'fadd d0 d0 d1) (asm-emit! a 'fmov/x x0 d0) (asm-epilogue! a) (def f (asm-finalize! a)) (display (Ptr call f 4607182418800017408 4611686018427387904)) (asm-free! a))
```
---
    4613937818241073152

### fsub: 3.0 - 1.0 is 2.0

```x
(do (def a (asm-new)) (asm-prologue! a) (asm-emit! a 'fmov/d d0 x0) (asm-emit! a 'fmov/d d1 x1) (asm-emit! a 'fsub d0 d0 d1) (asm-emit! a 'fmov/x x0 d0) (asm-epilogue! a) (def f (asm-finalize! a)) (display (Ptr call f 4613937818241073152 4607182418800017408)) (asm-free! a))
```
---
    4611686018427387904

### fmul: 2.0 * 1.5 is 3.0

```x
(do (def a (asm-new)) (asm-prologue! a) (asm-emit! a 'fmov/d d0 x0) (asm-emit! a 'fmov/d d1 x1) (asm-emit! a 'fmul d0 d0 d1) (asm-emit! a 'fmov/x x0 d0) (asm-epilogue! a) (def f (asm-finalize! a)) (display (Ptr call f 4611686018427387904 4609434218613702656)) (asm-free! a))
```
---
    4613937818241073152

### fdiv: 1.0 / 2.0 is 0.5

```x
(do (def a (asm-new)) (asm-prologue! a) (asm-emit! a 'fmov/d d0 x0) (asm-emit! a 'fmov/d d1 x1) (asm-emit! a 'fdiv d0 d0 d1) (asm-emit! a 'fmov/x x0 d0) (asm-epilogue! a) (def f (asm-finalize! a)) (display (Ptr call f 4607182418800017408 4611686018427387904)) (asm-free! a))
```
---
    4602678819172646912

### three-address: d2 = (3.0 - 1.0) + 3.0 keeps d0 intact

```x
(do (def a (asm-new)) (asm-prologue! a) (asm-emit! a 'fmov/d d0 x0) (asm-emit! a 'fmov/d d1 x1) (asm-emit! a 'fsub d2 d0 d1) (asm-emit! a 'fadd d2 d2 d0) (asm-emit! a 'fmov/x x0 d2) (asm-epilogue! a) (def f (asm-finalize! a)) (display (Ptr call f 4613937818241073152 4607182418800017408)) (asm-free! a))
```
---
    4617315517961601024

## conversions

### scvtf: 3 is 3.0

```x
(do (def a (asm-new)) (asm-prologue! a) (asm-emit! a 'scvtf d0 x0) (asm-emit! a 'fmov/x x0 d0) (asm-epilogue! a) (def f (asm-finalize! a)) (display (Ptr call f 3 0)) (asm-free! a))
```
---
    4613937818241073152

### fcvtzs: -2.5 truncates to -2

```x
(do (def a (asm-new)) (asm-prologue! a) (asm-emit! a 'fmov/d d0 x0) (asm-emit! a 'fcvtzs x0 d0) (asm-epilogue! a) (def f (asm-finalize! a)) (display (Ptr call f -4610560118520545280 0)) (asm-free! a))
```
---
    -2

### fcvt/s: 1.5 as a single is 1.5f, the bits above it zero

```x
(do (def a (asm-new)) (asm-prologue! a) (asm-emit! a 'fmov/d d0 x0) (asm-emit! a 'fmov/d d1 x1) (asm-emit! a 'fcvt/s d1 d0) (asm-emit! a 'fmov/x x0 d1) (asm-epilogue! a) (def f (asm-finalize! a)) (display (Ptr call f 4609434218613702656 -1)) (asm-free! a))
```
---
    1069547520

### fcvt/s rounds to nearest: 0.1 is 0x3DCCCCCD, 1 + 3/2^25 rounds up

```x
(do (def a (asm-new)) (asm-prologue! a) (asm-emit! a 'fmov/d d0 x0) (asm-emit! a 'fcvt/s d0 d0) (asm-emit! a 'fmov/x x0 d0) (asm-epilogue! a) (def f (asm-finalize! a)) (display (list (Ptr call f 4591870180066957722 0) (Ptr call f 4607182419202670592 0))) (asm-free! a))
```
---
    (1036831949 1065353217)

### fcvt/s past the single range is infinity

```x
(do (def a (asm-new)) (asm-prologue! a) (asm-emit! a 'fmov/d d0 x0) (asm-emit! a 'fcvt/s d0 d0) (asm-emit! a 'fmov/x x0 d0) (asm-epilogue! a) (def f (asm-finalize! a)) (display (Ptr call f 5205425776111082661 0)) (asm-free! a))
```
---
    2139095040

### fcvt/d: -2.5f and 0.1f as doubles

```x
(do (def a (asm-new)) (asm-prologue! a) (asm-emit! a 'fmov/d d1 x0) (asm-emit! a 'fcvt/d d0 d1) (asm-emit! a 'fmov/x x0 d0) (asm-epilogue! a) (def f (asm-finalize! a)) (display (list (Ptr call f 3223322624 0) (Ptr call f 1036831949 0))) (asm-free! a))
```
---
    (-4610560118520545280 4591870180174331904)


## compare

### flt: 1.0 < 2.0

```x
(do (def a (asm-new)) (asm-prologue! a) (asm-emit! a 'fmov/d d0 x0) (asm-emit! a 'fmov/d d1 x1) (asm-emit! a 'flt x0 d0 d1) (asm-epilogue! a) (def f (asm-finalize! a)) (display (Ptr call f 4607182418800017408 4611686018427387904)) (asm-free! a))
```
---
    1

### flt: 2.0 < 1.0 is 0

```x
(do (def a (asm-new)) (asm-prologue! a) (asm-emit! a 'fmov/d d0 x0) (asm-emit! a 'fmov/d d1 x1) (asm-emit! a 'flt x0 d0 d1) (asm-epilogue! a) (def f (asm-finalize! a)) (display (Ptr call f 4611686018427387904 4607182418800017408)) (asm-free! a))
```
---
    0

### flt: a NaN operand is 0

```x
(do (def a (asm-new)) (asm-prologue! a) (asm-emit! a 'fmov/d d0 x0) (asm-emit! a 'fmov/d d1 x1) (asm-emit! a 'flt x0 d0 d1) (asm-epilogue! a) (def f (asm-finalize! a)) (display (Ptr call f 9221120237041090560 4607182418800017408)) (asm-free! a))
```
---
    0

### feq: 2.0 = 2.0

```x
(do (def a (asm-new)) (asm-prologue! a) (asm-emit! a 'fmov/d d0 x0) (asm-emit! a 'fmov/d d1 x1) (asm-emit! a 'feq x0 d0 d1) (asm-epilogue! a) (def f (asm-finalize! a)) (display (Ptr call f 4611686018427387904 4611686018427387904)) (asm-free! a))
```
---
    1

### feq: NaN is not equal to itself

```x
(do (def a (asm-new)) (asm-prologue! a) (asm-emit! a 'fmov/d d0 x0) (asm-emit! a 'fmov/d d1 x1) (asm-emit! a 'feq x0 d0 d1) (asm-epilogue! a) (def f (asm-finalize! a)) (display (Ptr call f 9221120237041090560 9221120237041090560)) (asm-free! a))
```
---
    0


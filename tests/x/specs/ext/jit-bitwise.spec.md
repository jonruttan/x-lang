# @lib ../tests/x/lib/compile.x

The JIT's bitwise and shift family. Untagged on purpose: both backends (ARM64 and x86-64) compile the
same vocabulary, so this file runs on every host and IS the parity
contract.

## bitwise and shift operators

### bitwise and

```scheme
(display ((compile-asm '(fn (_ a b) (& a b))) 12 5))
```
---
    4

### bitwise or

```scheme
(display ((compile-asm '(fn (_ a b) (| a b))) 12 5))
```
---
    13

### bitwise xor

```scheme
(display ((compile-asm '(fn (_ a b) (^ a b))) 12 5))
```
---
    9

### bitwise not

```scheme
(display ((compile-asm '(fn (_ a) (~ a))) 12))
```
---
    -13

### shift left

```scheme
(display ((compile-asm '(fn (_ a b) (<< a b))) 12 3))
```
---
    96

### shift right

```scheme
(display ((compile-asm '(fn (_ a b) (>> a b))) 12 3))
```
---
    1

### shift right on a negative value sign-extends, as the interpreter does

The interpreter's `>>` is C's on a signed word, so it propagates the
sign bit. The JIT first emitted LSRV and answered
`4611686018427387900` here — a compiled function disagreeing with the
identical interpreted one, which is the only contract the JIT has. It
emits ASRV now. (On the masked non-negative values a digest shifts,
the two instructions agree, so nothing above would have caught this.)

```scheme
(display ((compile-asm '(fn (_ a b) (>> a b))) -16 2))
```
---
    -4

### a shift amount may itself be an expression

```scheme
(display ((compile-asm '(fn (_ a b) (<< a (- b 1)))) 1 5))
```
---
    16

### compiled agrees with interpreted on a mixed expression

```scheme
(do
  (def %f (fn (_ a b) (& (^ (| a b) (<< a 2)) 255)))
  (def %c (compile-asm '(fn (_ a b) (& (^ (| a b) (<< a 2)) 255))))
  (display (= (%f 200 44) (%c 200 44))))
```
---
    #t

## the SHA-256 primitive

### a full 32-bit rotate compiles and runs natively

rotr32(x, n) = ((x >> n) | (x << (32 - n))) & 0xFFFFFFFF — the operation
the digest's four sigma functions are built from.

```scheme
(display ((compile-asm '(fn (_ x n) (& (| (>> x n) (<< x (- 32 n))) 4294967295))) 1 1))
```
---
    2147483648

### the rotate agrees with the interpreted definition across cases

```scheme
(do
  (def %rotr (fn (_ x n) (& (| (>> x n) (<< x (- 32 n))) 4294967295)))
  (def %crotr (compile-asm '(fn (_ x n) (& (| (>> x n) (<< x (- 32 n))) 4294967295))))
  (display (and (= (%rotr 2 1) (%crotr 2 1))
                (and (= (%rotr 4294967295 7) (%crotr 4294967295 7))
                     (= (%rotr 305419896 13) (%crotr 305419896 13))))))
```
---
    #t

# @lib ../tests/x/lib/compile.x
# @requires native/jit
# @weight 1

Wide integer literals in JIT-compiled code. Untagged on purpose: both backends (ARM64 and x86-64) compile the
same vocabulary, so this file runs on every host and IS the parity
contract.

`mov Xd, #imm` maps to MOVZ — 16 bits, and the encoder masks the rest
away — so before this fix any literal above 65535 compiled to a
silently wrong constant and the function answered without complaint.
Literals that do not fit now take the MOVZ+MOVK sequence
(`asm-load-imm64!`) instead.

## wide literals

### a literal above 65535 survives compilation

Before the fix this answered 34506 — that is `(100000 & 65535) + 42`.

```scheme
(display ((compile-asm '(fn (_ x) (+ x 100000))) 42))
```
---
    100042

### the 32-bit mask survives compilation

Before the fix this answered 65577 — the mask had collapsed to 65535.

```scheme
(display ((compile-asm '(fn (_ x) (+ x 4294967295))) 42))
```
---
    4294967337

### a literal at the MOVZ boundary still works

```scheme
(display ((compile-asm '(fn (_ x) (+ x 65535))) 1))
```
---
    65536

### a literal just past the boundary is exact

```scheme
(display ((compile-asm '(fn (_ x) (+ x 65536))) 0))
```
---
    65536

### small literals are unaffected

```scheme
(display ((compile-asm '(fn (_ x) (+ x 1000))) 42))
```
---
    1042

### a negative literal round-trips

```scheme
(display ((compile-asm '(fn (_ x) (+ x -100000))) 0))
```
---
    -100000

### compiled agrees with interpreted on a wide-constant expression

```scheme
(do
  (def %f (fn (_ x) (- (* x 1000000) 999999)))
  (def %c (compile-asm '(fn (_ x) (- (* x 1000000) 999999))))
  (display (= (%f 7) (%c 7))))
```
---
    #t

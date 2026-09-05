# @lib ../tests/x/lib/compile.x
# @requires native/jit
# @weight 1

The JIT's `do` form and its code-buffer bounds. Untagged on purpose: both backends (ARM64 and x86-64) compile the
same vocabulary, so this file runs on every host and IS the parity
contract.

## the `do` form

`%seq` is the tokenizer's internal two-argument sequencing form; `do` is
the language's own, and the JIT had no emitter for it at all — a
compiled `(do ...)` body fell through to the function-call path and
failed obscurely.

### a two-form do yields its last value

```x
(display ((compile-asm '(fn (_ a b) (do a b))) 1 2))
```
---
    2

### a many-form do yields its last value

```x
(display ((compile-asm '(fn (_ a b) (do a b a b (+ a b)))) 20 22))
```
---
    42

### an empty do yields zero

The JIT's nil is a raw 0 in x0, and the boxing at return makes that the
integer 0 rather than `()` — the same boundary every other JIT form
sits on, pinned here so it is a decision and not a surprise.

```x
(display ((compile-asm '(fn (_ a) (do))) 1))
```
---
    0

### a do nests inside other forms

```x
(display ((compile-asm '(fn (_ a b) (+ (do a b) (do b a)))) 10 32))
```
---
    42

### earlier forms in a do really are evaluated

The middle form is a division that would trap on a zero divisor, so a
`do` that skipped it would answer instead of dying.

```x
(display ((compile-asm '(fn (_ a b) (do (/ a b) (+ a b)))) 40 2))
```
---
    42

## code-buffer bounds

`asm-new`'s default buffer is 4096 bytes — 1024 instructions — and
nothing checked the position, so emitting past it wrote beyond the
mmap'd region and segfaulted somewhere unrelated. It raises now, and
`compile-asm` sizes the buffer from the expression.

### emitting past the capacity raises instead of corrupting memory

Nine nops into an eight-byte buffer: a nop is one byte on x86-64 and
four on ARM64, so nine overruns eight bytes on ANY backend.

```x
(do
  (def %a (asm-new 8))
  (def %fill (fn (self n) (match ((= n 0) ()) (#t (do (asm-emit! %a 'nop) (self (- n 1)))))))
  (display (guard (_ 'raised) (do (%fill 9) 'no-raise))))
```
---
    raised

### a small function still compiles and runs

```x
(display ((compile-asm '(fn (_ a) (+ a 1))) 41))
```
---
    42

### a large generated body compiles and runs

Well past the old 1024-instruction default: 400 nested additions, which
before the sizing fix wrote off the end of the buffer.

```x
(do
  (def %big
    ((fn (self i acc) (match ((= i 0) acc) (#t (self (- i 1) (list '+ acc 1)))))
     400 'a))
  (display ((compile-asm (list 'fn '(_ a) %big)) 2)))
```
---
    402

### an instruction that would straddle the end raises before writing any of it

The capacity check used to sit in the byte emitter and fire per byte, so
an instruction landing across the end wrote its leading bytes and only
then raised — a torn instruction in the buffer behind a raised error.
The batched emitters check the LAST byte up front, so the position does
not move and nothing is written.

Arch-neutral by measurement: one `mov x0 x0` is emitted into a probe
buffer to learn the instruction size (four bytes on ARM64, three on
x86-64), and the real buffer is sized to hold exactly four of them plus
ONE SPARE BYTE — so the fifth mov begins in bounds and ends past the
end, the exact tear shape. The case then pins that the failing emit
moved the position by NOTHING: a torn instruction would leave it past
`4*size`.

```x
(do
  (def %probe (asm-new 64))
  (asm-emit! %probe 'mov x0 x0)
  (def %size (asm-pos %probe))
  (def %a (asm-new (+ (* 4 %size) (- %size 1))))
  (def %fill (fn (self n) (match ((= n 0) ()) (#t (do (asm-emit! %a 'mov x0 x0) (self (- n 1)))))))
  (%fill 4)
  (def %before (asm-pos %a))
  (def %verdict (guard (_ 'raised) (do (asm-emit! %a 'mov x0 x0) 'no-raise)))
  (display (list %verdict (= %before (* 4 %size)) (= (asm-pos %a) %before))))
```
---
    (raised #t #t)

## runtime availability

The compiler reaches its runtime helpers (`jit_mkint`, `jit_atomint`,
…) by `dlsym` on the engine itself, and those symbols live in
`exports.sym`. An engine built without them — a bare `strip` drops the
exported symbol table that `strip -x` keeps, which is what `make
install` did — resolves every helper to nil, and nil becomes address 0.
Compiled code then *called address 0*: a SIGSEGV inside `jit_atomint`,
arbitrarily far from the cause, on every installed engine while the
repo build was clean (x-lang#201).

So the entry point refuses first. It refuses at the CALL, not at module
load: raising out of a nested `import` leaves the loader mid-file, which
showed up as correct answers followed by a stray error and exit 1.

### an unreachable JIT runtime refuses instead of emitting a call to zero

`%jit-missing` is what resolution records; forcing it here simulates the
stripped engine without needing one, and the case restores it so the
rest of the batch still compiles.

```x
(do
  (def %saved %jit-missing)
  (set! %jit-missing (list "jit_mkint"))
  (def %verdict (guard (_ 'raised) (do (compile-asm '(fn (_ a) (+ a 1))) 'no-raise)))
  (set! %jit-missing %saved)
  (display (list %verdict ((compile-asm '(fn (_ a) (+ a 1))) 41))))
```
---
    (raised 42)

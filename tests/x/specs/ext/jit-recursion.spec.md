# @lib ../tests/x/lib/compile.x
# @requires native/jit

JIT self-recursion. Untagged on purpose: both backends (ARM64 and x86-64) compile the
same vocabulary, so this file runs on every host and IS the parity
contract.

The trampoline machinery for recursive calls was present but had never
run — two bugs, one at generation and one at runtime:

- the trampoline load emitted `(mem x8 0)`, but a `mem` operand's base
  is a raw register **number**, not a `(reg n)` operand, so the encoder
  tried to shift a list and every recursive call failed to compile;
- the argument-list builder stashed its accumulator in `x3` across a
  `jit_mkint` call. `x3` is caller-saved (AAPCS64), so the C function
  was free to clobber it — the pair got built on garbage and the call
  segfaulted. It lives in `x21` now: callee-saved, and the compiler's
  prologue already spills it.

## recursion

### a recursive function terminates and returns

```scheme
(display ((compile-asm '(fn (self a t) (if (= t 3) a (self a (+ t 1))))) 7 0))
```
---
    7

### the recursion actually iterates (accumulates per level)

```scheme
(display ((compile-asm '(fn (self n acc) (if (= n 0) acc (self (- n 1) (+ acc n))))) 10 0))
```
---
    55

### one argument

```scheme
(display ((compile-asm '(fn (self n) (if (= n 0) 100 (self (- n 1))))) 5))
```
---
    100

### three arguments survive the call

Each argument is boxed and threaded through a fresh pair list per call,
which is where the clobbered accumulator corrupted things.

```scheme
(display ((compile-asm '(fn (self a b c) (if (= c 0) (+ a b) (self (+ a 1) (+ b 10) (- c 1))))) 1 2 3))
```
---
    36

### deep recursion (64 levels, the SHA-256 round count)

```scheme
(display ((compile-asm '(fn (self n acc) (if (= n 0) acc (self (- n 1) (+ acc 1))))) 64 0))
```
---
    64

### recursion composes with do and arithmetic

```scheme
(display ((compile-asm '(fn (self n acc) (if (= n 0) acc (do acc (self (- n 1) (% (+ acc 7) 255)))))) 4 0))
```
---
    28

### an unsupported operator raises instead of compiling to a self-call

Anything the JIT does not implement used to reach the self-recursion
path and compile AS a recursive call: the code ran, recursed forever,
and segfaulted far from the cause. `abs` stands in for any unimplemented
form — it reads as an operator and has no emitter.

(This case originally used `&`, which the bitwise family later
implemented; the suite caught the stale premise. Any stand-in here is
only valid while it stays unimplemented — if `abs` ever lands, pick
another rather than deleting the case.)

```scheme
(display (guard (_ 'raised) (do (compile-asm '(fn (_ a b) (abs a b))) 'no-raise)))
```
---
    raised

### a call to a name that is not the function's own also raises

```scheme
(display (guard (_ 'raised) (do (compile-asm '(fn (self a) (helper a))) 'no-raise)))
```
---
    raised

### compiled recursion agrees with the interpreted definition

```scheme
(do
  (def %i (fn (self n acc) (if (= n 0) acc (self (- n 1) (+ acc (* n n))))))
  (def %c (compile-asm '(fn (self n acc) (if (= n 0) acc (self (- n 1) (+ acc (* n n)))))))
  (display (= (%i 12 0) (%c 12 0))))
```
---
    #t

# @lib ../tests/x/lib/compile.x
# @requires native/jit
# @weight 2

JIT parameter slots and the tail self-call.  An integer function reads
each parameter once, on entry, into a stack slot; a self-call in tail
position stores its arguments over the slots and jumps back to the top
of the body.  A compiled loop runs in constant stack and allocates
nothing per turn.  Unlabelled on purpose: both backends run it.

## loops

### a million turns: past any C stack a call per turn would need

```x
(display ((compile-asm '(fn (self n acc) (if (= n 0) acc (self (- n 1) (+ acc n))))) 1000000 0))
```
---
    500000500000

### a turn allocates nothing

The call itself allocates what any call from x does; ten turns or a
hundred thousand, the same, give or take the bookkeeping: an object a turn
would show as a hundred thousand.

```x
(do (def %jt-loop (compile-asm '(fn (self n) (if (= n 0) 0 (self (- n 1))))))
    (%jt-loop 10)
    (def %jt-c0 (Heap count))
    (%jt-loop 10)
    (def %jt-c1 (Heap count))
    (%jt-loop 100000)
    (display (< (- (- (Heap count) %jt-c1) (- %jt-c1 %jt-c0)) 100)))
```
---
    #t

### the new arguments are all computed before any is stored

Each argument reads the parameters it replaces: a swap.

```x
(display ((compile-asm '(fn (self a b n) (if (= n 0) (- (* a 10) b) (self b a (- n 1))))) 1 2 3))
```
---
    19

### tail position through do, if and match arms

```x
(display (list
  ((compile-asm '(fn (self n acc) (do (+ n 1) (if (= n 0) acc (self (- n 1) (+ acc 2)))))) 300000 0)
  ((compile-asm '(fn (self n acc) (match ((= n 0) acc) ((< n 5) (self (- n 1) (+ acc 100))) (#t (self (- n 1) (+ acc 1)))))) 100000 0)))
```
---
    (600000 100396)

## calls that are not in tail position

### a call whose value is used is still a call, with slots of its own

```x
(display ((compile-asm '(fn (self n) (if (< n 2) n (+ (self (- n 1)) (self (- n 2)))))) 20))
```
---
    6765

### an argument is evaluated once, on entry

A parameter read three times reads the one value.

```x
(do (def %jt-count 0)
    (def %jt-f (compile-asm '(fn (self x) (+ x (+ x x)))))
    (display (%jt-f (do (set! %jt-count (+ %jt-count 1)) 5)))
    (display %jt-count))
```
---
    151

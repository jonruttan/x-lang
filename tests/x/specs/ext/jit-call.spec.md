# @lib ../tests/x/lib/compile.x
# @requires native/jit
# @weight 2

Calling something other than the function being compiled. Untagged on purpose:
both backends (ARM64 and x86-64) compile the same vocabulary, so this file runs
on every host and IS the parity contract.

The lane had exactly one call shape -- the self-call -- so a compiled function
could recurse and nothing else. Two shapes join it here, and they differ only in
when the callee's address is known:

    (CALLEE arg ...)      CALLEE is a name bound to an fvar holding a prim,
                          so its address is baked at generation (#603)
    (%call HEAD arg ...)  HEAD is an OPERAND, so which prim it is is not
                          known until the call runs (#604)

Both build the argument list the self-call already built and hand
`(callee arg0 arg1 ...)` -- the prim ABI shape, callee in the self slot -- to
`jit_call_value`, which checks the head really is a callable prim before it
branches. That check is the whole reason the branch is safe: on anything that
is not a PRIMITIVE, the word `jit_call_value` would jump through is a length or
a character, and the crash would have no relation to the call site.

## calling a prim named at compile time

### a compiled function calls another compiled function

The callee is handed in as an fvar. `#f` is the third argument: it declares
this an ordinary integer function rather than an analyse callback, which is
what the presence of fvars used to be read as.

```x
(do
  (def %sq (compile-asm '(fn (_ n) (* n n))))
  (def %f (compile-asm '(fn (self n) (+ (helper n) 1)) (list (pair 'helper %sq)) #f))
  (display (%f 5)))
```
---
    26

### the answer matches the same two functions interpreted

```x
(do
  (def %sq (compile-asm '(fn (_ n) (* n n))))
  (def %f (compile-asm '(fn (self n) (+ (helper n) 1)) (list (pair 'helper %sq)) #f))
  (def %i-sq (fn (_ n) (* n n)))
  (def %i-f (fn (self n) (+ (%i-sq n) 1)))
  (display (= (%f 12) (%i-f 12))))
```
---
    #t

### the callee may contain a loop the caller could not inline

Inlining was the lane's only cross-call, and it cannot reach a callee that
loops: a body inlined into an expression has to BE one expression, and an
expression cannot iterate. This is the case that forced the ask.

```x
(do
  (def %sum (compile-asm '(fn (self n acc) (if (= n 0) acc (self (- n 1) (+ acc n))))))
  (def %f (compile-asm '(fn (self n) (* 2 (sumto n 0))) (list (pair 'sumto %sum)) #f))
  (display (%f 10)))
```
---
    110

### two compiled functions call each other

Neither is the other's self-call, and `%c-even` reaches `%c-odd` by name.

```x
(do
  (def %c-odd (compile-asm '(fn (self n) (if (= n 0) 0 (if (= n 1) 1 (self (- n 2)))))))
  (def %c-even (compile-asm '(fn (self n) (- 1 (isodd n))) (list (pair 'isodd %c-odd)) #f))
  (write (list (%c-even 10) (%c-even 7)))
  (newline))
```
---
    (1 0)

## calling a prim computed at run time

### a callback reaches native code through a parameter

`f` is an ordinary parameter. What it holds is not known until the call runs,
which is the whole difference from the section above.

```x
(do
  (def %sq (compile-asm '(fn (_ n) (* n n))))
  (def %apply1 (compile-asm '(fn (self f x) (%call f x))))
  (display (%apply1 %sq 9)))
```
---
    81

### the callback shape that motivated this: f(f(x))

`int twice(int (*f)(int), int x) { return f(f(x)); }` -- a C function pointer,
and the shape that kept every compiled caller of a callback interpreted.

```x
(do
  (def %inc (compile-asm '(fn (_ n) (+ n 1))))
  (def %twice (compile-asm '(fn (self f x) (%call f (%call f x)))))
  (display (%twice %inc 40)))
```
---
    42

### a dispatch table indexed at run time

`ops[i](x)`: the table holds prim ADDRESSES in scratch memory and the index is
computed, so the head is an expression, not a name. A compiled opcode switch is
this shape, and so is a sort with a comparator.

```x
(do
  (def %make-str (prim-ref (lit str) (lit make)))
  (def %str->ptr (prim-ref (lit str) (lit ->ptr)))
  (def %ptr->int (prim-ref (lit ptr) (lit ->int)))
  (def %obj->ptr (prim-ref (lit obj) (lit ->ptr)))
  (def %store (compile-asm '(fn (_ a i v) (%mem-set-at! a i v))))
  (def %tbl (%make-str 512))
  (def %addr (%ptr->int (%str->ptr %tbl)))
  (%store %addr 0 (%ptr->int (%obj->ptr (compile-asm '(fn (_ n) (+ n 1))))))
  (%store %addr 1 (%ptr->int (%obj->ptr (compile-asm '(fn (_ n) (* n 2))))))
  (%store %addr 2 (%ptr->int (%obj->ptr (compile-asm '(fn (_ n) (- 0 n))))))
  (def %dispatch (compile-asm '(fn (self a i x) (%call (%mem-ref-at a i) x))))
  (write (list (%dispatch %addr 0 10) (%dispatch %addr 1 10) (%dispatch %addr 2 10)))
  (newline))
```
---
    (11 20 -10)

### a computed call agrees with the interpreted definition

```x
(do
  (def %sq (compile-asm '(fn (_ n) (* n n))))
  (def %c (compile-asm '(fn (self f x) (+ (%call f (+ x 1)) (%call f x)))))
  (def %i (fn (self f x) (+ (f (+ x 1)) (f x))))
  (display (= (%c %sq 6) (%i %sq 6))))
```
---
    #t

### no arguments, and the four the marshalling allows

```x
(do
  (def %a0 (compile-asm '(fn (_) 99)))
  (def %a4 (compile-asm '(fn (_ a b c d) (+ (+ a b) (+ c d)))))
  (write (list ((compile-asm '(fn (self f) (%call f))) %a0)
               ((compile-asm '(fn (self f) (%call f 1 2 3 4))) %a4)))
  (newline))
```
---
    (99 10)

## refusing a head that cannot be called

### a value that is not a callable prim raises instead of branching

Every one of these has a first word, and branching to it is a segfault with no
relation to the call site. The check is at run time because the head is.

```x
(do
  (def %apply1 (compile-asm '(fn (self f x) (%call f x))))
  (def %try (fn (_ v) (guard (_ 'raised) (%apply1 v 5))))
  (write (list (%try 42) (%try (list 1 2)) (%try ()) (%try "hi") (%try (fn (_ n) n))))
  (newline))
```
---
    ('raised 'raised 'raised 'raised 'raised)

### a refused call leaves the compiled function usable

The raise unwinds; it does not corrupt the caller.

```x
(do
  (def %sq (compile-asm '(fn (_ n) (* n n))))
  (def %apply1 (compile-asm '(fn (self f x) (%call f x))))
  (guard (_ ()) (%apply1 42 5))
  (display (%apply1 %sq 6)))
```
---
    36

### a name bound to an fvar that is not a prim refuses at GENERATION

Known at generation, so caught at generation -- the same rule the unsupported
form check follows.

```x
(display (guard (_ 'raised)
  (do (compile-asm '(fn (self n) (helper n)) (list (pair 'helper 7)) #f) 'no-raise)))
```
---
    raised

### an unbound name still refuses at generation

The regression this file must not cause. Compiling an unrecognised head as a
self-call once made the code recurse on itself forever and die far from the
cause; a name that resolves to nothing is still not a call.

```x
(display (guard (_ 'raised) (do (compile-asm '(fn (self a) (helper a))) 'no-raise)))
```
---
    raised

### an unimplemented operator still refuses at generation

`abs` stands in for any form the JIT has no emitter for. It is not an fvar
here, so it is not a call either.

```x
(display (guard (_ 'raised) (do (compile-asm '(fn (_ a b) (abs a b))) 'no-raise)))
```
---
    raised

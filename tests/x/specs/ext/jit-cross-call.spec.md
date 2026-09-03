# @lib ../tests/x/lib/compile.x
# @requires native/jit
# @weight 1

One compiled function calling another. Untagged on purpose: both backends
(ARM64 and x86-64) compile the same vocabulary, so this file runs on every
host and IS the parity contract.

`compile-asm` used to refuse every call whose head was not the function's
own name, so a compiled function could recurse but two compiled functions
could not call each other. Everything a lane function needed from another
function had to be INLINED into it — which cannot work when the callee has
a loop or its own recursion, because inlining makes the callee's body one
expression and an expression cannot loop.

The machinery was already present in the self-call: it builds a real
x-lang argument list, branches to an address, and unboxes the result. It
loaded that address from a malloc'd cell only because its own prim does
not exist yet while its body is being compiled. A callee compiled EARLIER
does exist, and its `x_fn_t` is data unit 0 of the prim object — the same
union slot `jit_firstobj` already reads, so the cross-call needs no new
engine symbol.

Callees are compile-asm's THIRD argument, an alist `((name . prim) ...)`,
and deliberately not the fvar argument: a non-empty fvar list is what puts
the compile in analyser mode, and an integer function compiled that way
bus errors when x calls it.

## cross-calls

### a compiled function calls another compiled function

```scheme
(do
  (def %sq (compile-asm '(fn (self n) (* n n))))
  (def %cube (compile-asm '(fn (self n) (* n (sq n))) () (list (pair 'sq %sq))))
  (display (%cube 5)))
```
---
    125

### the compiled pair answers exactly what the interpreted pair answers

```scheme
(do
  (def %isq (fn (self n) (* n n)))
  (def %icube (fn (self n) (* n (%isq n))))
  (def %sq (compile-asm '(fn (self n) (* n n))))
  (def %ccube (compile-asm '(fn (self n) (* n (sq n))) () (list (pair 'sq %sq))))
  (display (= (%icube 9) (%ccube 9))))
```
---
    #t

### the callee may have its own loop

This is the case inlining can never reach: the callee's body is a
recursion, so it has no single-expression form to inline. Called, it runs
native at both ends.

```scheme
(do
  (def %sumto (compile-asm '(fn (self n acc) (if (= n 0) acc (self (- n 1) (+ acc n))))))
  (def %twice (compile-asm '(fn (self n) (+ (sumto n 0) (sumto n 0)))
                () (list (pair 'sumto %sumto))))
  (display (%twice 10)))
```
---
    110

### a caller may recurse and cross-call in the same body

```scheme
(do
  (def %sq (compile-asm '(fn (self n) (* n n))))
  (def %sumsq (compile-asm '(fn (self n acc) (if (= n 0) acc (self (- n 1) (+ acc (sq n)))))
                () (list (pair 'sq %sq))))
  (display (%sumsq 5 0)))
```
---
    55

### cross-calls nest as arguments to each other

The argument marshalling pushes each evaluated argument before it builds
the list, so a call inside an argument is just another expression.

```scheme
(do
  (def %sq (compile-asm '(fn (self n) (* n n))))
  (def %quad (compile-asm '(fn (self n) (sq (sq n))) () (list (pair 'sq %sq))))
  (display (%quad 3)))
```
---
    81

### cross-calls chain three deep

Each link is compiled with the previous one in its callee list, so `top`
reaches `inc` through `dbl` without either caller knowing more than its
immediate callee.

```scheme
(do
  (def %inc (compile-asm '(fn (self n) (+ n 1))))
  (def %dbl (compile-asm '(fn (self n) (* (inc n) 2)) () (list (pair 'inc %inc))))
  (def %top (compile-asm '(fn (self n) (+ (dbl n) (dbl (+ n 1)))) () (list (pair 'dbl %dbl))))
  (display (%top 3)))
```
---
    18

### four arguments survive the call

Four is the ceiling, the same one self-calls have.

```scheme
(do
  (def %four (compile-asm '(fn (self a b c d) (+ (+ a b) (+ c d)))))
  (def %c4 (compile-asm '(fn (self x) (four x (* x 2) (* x 3) (* x 4)))
             () (list (pair 'four %four))))
  (display (%c4 1)))
```
---
    10

### more than four arguments refuses at generation

```scheme
(do
  (def %five (compile-asm '(fn (self a b c d e) (+ a b))))
  (display (guard (_ 'raised)
    (do (compile-asm '(fn (self x) (five x x x x x)) () (list (pair 'five %five)))
        'no-raise))))
```
---
    raised

### a callee list does not put the caller in analyser mode

The fvar argument does, and that is why callees have their own. An
integer function must keep eval'ing its arguments and boxing its result:
here the argument is an EXPRESSION, not a literal, which an
analyser-mode compile would read as an unevaluated pair.

```scheme
(do
  (def %sq (compile-asm '(fn (self n) (* n n))))
  (def %cube (compile-asm '(fn (self n) (* n (sq n))) () (list (pair 'sq %sq))))
  (display (%cube (+ 2 3))))
```
---
    125

### the call sites are recorded as relocations under the callee's name

A baked object pointer is per-process, so each cross-call site is a
relocation -- kind `callee`, not `fvar`: what a loader has to find again
is a prim, and resolving one of these to any other value produces code
that branches into it. Two sites per call: the self slot of the argument
list, and the fetch of the callee's function pointer.

```scheme
(do
  (def %sq (compile-asm '(fn (self n) (* n n))))
  (def %cube (compile-asm '(fn (self n) (* n (sq n))) () (list (pair 'sq %sq))))
  (def %count
    (fn (self k xs)
      (if (null? xs) 0
        (+ (if (eq? (first (rest (first xs))) k) 1 0) (self k (rest xs))))))
  (def %named
    (fn (self xs)
      (if (null? xs) #t
        (if (eq? (first (rest (first xs))) 'callee)
          (if (eq? (first (rest (rest (first xs)))) 'sq) (self (rest xs)) #f)
          (self (rest xs))))))
  (write (list (%count 'callee %asm-last-relocs) (%named %asm-last-relocs)))
  (newline))
```
---
    (2 #t)

## the refusals

Refusing at generation is the whole reason this lane is trustworthy.
Compiling an unrecognised head AS a self-call once made the code recurse
on itself and die arbitrarily far from the cause; every case below used
to be that bug, and each must stay loud.

### an unbound name still refuses

```scheme
(display (guard (_ 'raised) (do (compile-asm '(fn (self a) (helper a))) 'no-raise)))
```
---
    raised

### a name absent from a NON-EMPTY callee list still refuses

```scheme
(do
  (def %sq (compile-asm '(fn (self n) (* n n))))
  (display (guard (_ 'raised)
    (do (compile-asm '(fn (self a) (helper a)) () (list (pair 'sq %sq))) 'no-raise))))
```
---
    raised

### a declared callee that is an integer refuses

A bound name is not enough: branching to a value that is not a native
function executes whatever those bytes are.

```scheme
(display (guard (_ 'raised)
  (do (compile-asm '(fn (self a) (k a)) () (list (pair 'k 5))) 'no-raise)))
```
---
    raised

### a declared callee that is a CLOSURE refuses

The dangerous one: an x-lang closure is callable, so it reads as a
function everywhere except here — it has no machine code to branch to.

```scheme
(display (guard (_ 'raised)
  (do (compile-asm '(fn (self a) (k a)) () (list (pair 'k (fn (_ x) x)))) 'no-raise)))
```
---
    raised

### a callee named outside head position refuses

Callees resolve in head position only. A prim's OBJECT is not a value
this compiler can produce in an integer expression, so naming one as an
operand is unbound — which is the honest answer, not a silent zero.

```scheme
(do
  (def %sq (compile-asm '(fn (self n) (* n n))))
  (display (guard (_ 'raised)
    (do (compile-asm '(fn (self n) (+ n sq)) () (list (pair 'sq %sq))) 'no-raise))))
```
---
    raised

## analyser mode

### a compiled analyser calls another compiled analyser through an fvar

An analyser's fvars already carry compiled prims — the tokenizer's
replace-state protocol hands handlers around — so a call to one is a
cross-call too, and needs no second list. Here the name state's accept
path is a separate compiled function; the whole token loop still runs
without re-entering the interpreter.

```scheme
(do
  (def %b (Base make-tok))
  (def %read-str (prim-ref 'tok 'read-str))
  (def %buf-tok (prim-ref 'buf 'tok))
  (def %accept
    (compile-asm
      '(fn (_ buffer score chr)
        (%seq (%buffer-unread buffer) (%score-set score 1 buffer)))
      (list (pair 'u 1))))
  (def %name-body
    (compile-asm
      '(fn (me buffer score chr)
        (if (and (>= chr 97) (<= chr 122)) me (accept buffer score chr)))
      (list (pair 'accept %accept))))
  (def %name-start
    (compile-asm
      '(fn (_ buffer score chr)
        (if (and (>= chr 97) (<= chr 122)) body ()))
      (list (pair 'body %name-body))))
  (Base make-type %b "S-NAME"
    (list (pair 'analyse %name-start)
      (pair 'read (fn (_ . args) (%buf-tok (first args))))))
  (Base make-type %b "S-WS"
    (list (pair 'analyse
      (fn (_ buffer score chr)
        (if (= chr 32) (%score-set score -1 buffer) ())))))
  (write (%read-str (Base raw-of %b) "hello world xy z "))
  (newline))
```
---
    ("hello" "world" "xy" "z")

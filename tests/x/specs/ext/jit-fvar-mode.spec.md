# @lib ../tests/x/lib/compile.x
# @requires native/jit
# @weight 2

The two calling worlds, and what happens to a body compiled for the wrong one.
Untagged on purpose: both backends compile the same vocabulary, so this file
runs on every host.

`compile-asm` emits for two worlds. An **integer function** is called from x
through the prim ABI: its arguments arrive as unevaluated expressions, so each
param evaluates and unboxes, and the result is boxed on the way out. An
**analyse callback** is invoked from C's scoring loop with live values built on
the C stack: nothing evaluates, the leading one or two params stay the
`x_obj_t*` they arrived as, and the result is returned unboxed.

The third argument declares which. With no third argument the door reads the
fvar table — present means analyser — and that reading cannot be made exact,
because an fvar also names a callee the body calls (#603). Both worlds are
`(fn (self a b c) ...)` over the same vocabulary, and nothing in the expression
or the table separates them.

So the misuse is what refuses. An object param handed to arithmetic, to a shift
or to an ordered comparison is not something an analyser means — every state in
the tower and in the lang bundles uses its object params as trampoline arguments
and nothing else — and it is what an integer function read as an analyser does
on its first line.

## an object param is not a number

### arithmetic on one refuses, and names the declaration that fixes it

A scanner for the first byte at or below 32. `bref` and `cint` are fvars
because that is how a compiled body calls a prim (#603), so with no third
argument the compile is an analyser: `i` is a pointer, and ordering it against
`n` is the refusal. Without the refusal the comparison reads a pointer as a
number, the branch is taken on that, and the unboxed result is argument 2.

```x
(do
  (def %bref (prim-ref 'str 'byte-ref))
  (def %cint (prim-ref 'char '->int))
  (write (guard (e (list (Err tag e) (e msg)))
    (do
      (compile-asm '(fn (self s i n)
                      (if (>= i n) i
                        (if (<= (cint (bref s i)) 32) i
                          (self s (+ i 1) n))))
                   (list (pair 'bref %bref) (pair 'cint %cint)))
      'compiled))))
```
---
```output
('value "asm-compile: >= cannot take the object parameter i as an operand: this compile is in analyser mode, where that parameter arrives as an x_obj_t* and not as a number.  Pass #f as compile-asm's third argument for an ordinary integer function.")
```

### a comparison folded into an if test refuses too

`if` folds a comparison in its test into the branch, so that operand does not
reach the call emitter and the check runs there as well. A body whose only
arithmetic is its loop guard is an ordinary shape, so this is the common case
rather than a corner.

```x
(do
  (def %bref (prim-ref 'str 'byte-ref))
  (write (guard (e (Err tag e))
    (do (compile-asm '(fn (self s i n) (if (>= i n) 1 0))
                     (list (pair 'bref %bref)))
        'compiled))))
```
---
    'value

## declared, it compiles and agrees with the interpreter

### the compiled scanner answers what the interpreted one answers

Same body, same fvars, `#f` for the mode. The arguments evaluate, the result is
boxed, and the space at index 3 is what both answer.

```x
(do
  (def %bref (prim-ref 'str 'byte-ref))
  (def %cint (prim-ref 'char '->int))
  (def %jit (compile-asm '(fn (self s i n)
                            (if (>= i n) i
                              (if (<= (cint (bref s i)) 32) i
                                (self s (+ i 1) n))))
                         (list (pair 'bref %bref) (pair 'cint %cint)) #f))
  (def %interp (fn (self s i n)
                 (if (>= i n) i
                   (if (<= (%cint (%bref s i)) 32) i
                     (self s (+ i 1) n)))))
  (write (list (%jit "abc de" 0 6) (%interp "abc de" 0 6))))
```
---
    (3 3)

### and on every input, with the arguments passed as expressions

`" x"` answers 0 because index 0 is the space. Agreement is asserted per input
rather than against one expected number, so a compile that answers a constant
fails here whatever that constant is. The last case passes its arguments as
expressions rather than literals, which is what an integer function's params
evaluate; an analyser's do not, and dereferencing an argument expression as an
integer is a SIGSEGV.

```x
(do
  (def %bref (prim-ref 'str 'byte-ref))
  (def %cint (prim-ref 'char '->int))
  (def %jit (compile-asm '(fn (self s i n)
                            (if (>= i n) i
                              (if (<= (cint (bref s i)) 32) i
                                (self s (+ i 1) n))))
                         (list (pair 'bref %bref) (pair 'cint %cint)) #f))
  (def %interp (fn (self s i n)
                 (if (>= i n) i
                   (if (<= (%cint (%bref s i)) 32) i
                     (self s (+ i 1) n)))))
  (def %agree
    (fn (self cases)
      (if (null? cases) #t
        (do
          (def %c (first cases))
          (if (= (%jit (first %c) 0 (first (rest %c)))
                 (%interp (first %c) 0 (first (rest %c))))
            (self (rest cases))
            (first %c))))))
  (write (list (%agree (list (list "abc de" 6) (list "ab" 2) (list " x" 2)
                             (list "xyz" 3) (list "" 0) (list "  " 2)))
               (%jit "abc de" (+ 0 0) (- 7 1)))))
```
---
    (#t 3)

## what the declaration does not change

### a real analyser still compiles with the mode inferred

The bundles compile their tokenizer states as `(compile-asm form fvars)` and
adopt them under a guard, so a refusal there would not raise: it would pin the
interpreted states and keep them, with nothing reporting it. An analyser's
object params reach only trampolines, so the check does not touch one.

```x
(do
  (def %st '(fn (me buffer score chr)
              (if (and (>= chr 97) (<= chr 122)) me
                (%score-set score 1 buffer))))
  (write (list (if (null? (compile-asm %st (list (pair 'u 1)))) 'nothing 'compiled)
               (if (null? (compile-asm %st () #t)) 'nothing 'compiled))))
```
---
    ('compiled 'compiled)

### an empty fvar table is not ambiguous

Nothing for either world to bind, so both spellings mean an integer function.

```x
(write (list (if (null? (compile-asm '(fn (_ n) (+ n 1)))) 'nothing 'compiled)
             (if (null? (compile-asm '(fn (_ n) (+ n 2)) ())) 'nothing 'compiled)))
```
---
    ('compiled 'compiled)

## the subset boundary, which refuses and always did

### a form the lane does not implement is named, not guessed at

`let` and `#t` bound the compilable subset. Both refuse at generation, which is
the contract: what compiles agrees with the interpreter, and what would not is
named to the caller.

```x
(do
  (def %why (fn (_ e) (e msg)))
  (write (list (guard (e (%why e)) (do (compile-asm '(fn (_ n) (let ((a 1)) (+ n a)))) 'compiled))
               (guard (e (%why e)) (do (compile-asm '(fn (_ n) (if (>= n 0) #t #f))) 'compiled)))))
```
---
```output
("asm-compile: unsupported form: let" "asm-compile: unbound: #t")
```

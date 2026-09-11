# @lib ../tests/x/lib/compile.x
# @requires native/jit
# @weight 1

An OPTIONAL JIT symbol -- one an older engine may lack, so the lane binds it
as address 0 rather than refusing every compile -- must make the one form
that needs it REFUSE at compile time, never emit a call to 0. x-python's
compiled number states declared their variant through `jit_score_variant` on
an engine that had no such symbol, and the first number token after the swap
died with a SIGSEGV nowhere near the cause. The compile now raises a `'state`
Err, and the caller's guard falls back to the interpreted twin.

The engine decides which outcome is right, so each case asks the running
process itself -- `dlsym`, the way the lane resolves its trampolines -- and
pins compiled-where-exported, refused-where-absent, and nothing else.

## a state that declares a variant

### compiled where the engine exports jit_score_variant, refused by name where it does not

```x
(let ((present (not (null? ((prim-ref 'ffi 'dlsym) ((prim-ref 'ffi 'dlopen) () 1) "jit_score_variant"))))
      (r (guard (e (list (Err tag e) (e msg)))
           (%seq (compile-asm (lit (fn (_ buffer score chr) (%score-variant! score 7)))
                              (list (pair (lit u) 1)))
                 'compiled))))
  (if present
    (eq? r 'compiled)
    (equal? r (list 'state "asm-compile: this engine has no jit_score_variant, so a state that declares a variant cannot be compiled"))))
```
---
```output
#t
```

## any other unresolved trampoline

### %buffer-last-char: compiled where jit_buffer_last_char is exported, refused by the emitter where it is not

The emitter's own refusal, which no caller can reach around.

```x
(let ((present (not (null? ((prim-ref 'ffi 'dlsym) ((prim-ref 'ffi 'dlopen) () 1) "jit_buffer_last_char"))))
      (r (guard (e (Err tag e))
           (%seq (compile-asm (lit (fn (_ buffer score chr) (%buffer-last-char buffer)))
                              (list (pair (lit u) 1)))
                 'compiled))))
  (if present (eq? r 'compiled) (eq? r 'state)))
```
---
```output
#t
```

### the lane still compiles every form that needs no optional symbol

```x
(let ((r (compile-asm (lit (fn (_ x) (+ x k))) (list (pair (lit k) 41)))))
  (if (null? r) 'nothing 'compiled))
```
---
```output
'compiled
```

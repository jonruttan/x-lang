# @lib ../tests/x/lib/compile.x
# @requires native/jit
# @weight 1

compile-asm's operative world, declared with the symbol `operative`: the
function's one parameter is its argument list as the call wrote it, and
`(%eval x)` evaluates one of those expressions in the caller's environment.
Unlabelled, so both backends run it.  The object worlds also test a value for
truth as x does: false is nil or `#f`.

## truth in the object worlds

### #f is false in a test, as nil is

```x
(def %truth (compile-asm (lit (fn (_ x) (if x t f))) (list (pair (lit t) #t) (pair (lit f) #f)) (lit object)))
(write (list (%truth #f) (%truth ()) (%truth 0) (%truth "") (%truth #t) (%truth (list 1))))
```
---
    (#f #f #t #t #t #t)

### and and or inside a compiled body answer by the same truth

```x
(def %both (compile-asm (lit (fn (_ a b) (and a b))) () (lit object)))
(def %either (compile-asm (lit (fn (_ a b) (or a b))) () (lit object)))
(write (list (%both 1 2) (%both #f 2) (%both () 2) (%either #f 2) (%either () #f) (%either 1 2)))
```
---
    (2 #f () 2 #f 1)

## the operative world

### the parameter is the argument list, unevaluated

```x
(def %quoted (compile-asm (lit (fn (_ l) l)) () (lit operative)))
(write (%quoted (+ 1 2) undefined-name))
```
---
    (('+ 1 2) 'undefined-name)

### %eval evaluates an argument where the body reaches it, in the caller's environment

```x
(def %second (compile-asm (lit (fn (_ l) (%eval (first (rest l))))) () (lit operative)))
(def %n 0)
(def %bump (fn (_ v) (set! %n (+ %n 1)) v))
(def %local (fn (_ a b) (%second (%bump a) (+ b 1))))
(write (list (%local 1 41) %n))
```
---
    (42 0)

### a tail self-call walks the argument list

```x
(def %op-last (compile-asm
  (lit (fn (self l) (if (= (rest l) ()) (%eval (first l)) (self (rest l)))))
  () (lit operative)))
(write (%op-last (Err raise (lit x) "not reached" ()) 2 (+ 1 2)))
```
---
    3

### a raise inside an evaluated argument reaches the caller's guard

```x
(def %first-of (compile-asm (lit (fn (_ l) (%eval (first l)))) () (lit operative)))
(write (guard (e (lit caught)) (%first-of (Err raise (lit x) "inside" ()))))
```
---
    'caught

## refusals

### an operative takes one parameter

```x
(write (guard (e (lit refused)) (compile-asm (lit (fn (_ a b) a)) () (lit operative))))
```
---
    'refused

### %eval belongs to the operative world

```x
(write (guard (e (lit refused)) (compile-asm (lit (fn (_ a) (%eval a))) () (lit object))))
```
---
    'refused

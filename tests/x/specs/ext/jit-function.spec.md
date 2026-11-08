# @lib ../tests/x/lib/compile.x
# @requires native/jit
# @weight 2

compile-asm's function world, declared with the symbol `function`: the body
a program's closure becomes once x/tool/fn-compile has rewritten it.  Every
value is an object; `%unbox` and `%box` cross to and from the raw words
arithmetic takes; `(def NAME EXPR)` binds a local; and
`(%call-q T F A ...)` applies F to values through the template T, a list
`((lit ()) ...)` with one `(lit x)` for F and one for each A.  The
parameters and the locals live in cells on the base's root chain, so a
collect run by a callee keeps what the frame holds.  Unlabelled, so both
backends run it.

## values and locals

### integers cross to raw words and back

```x
(def %fw-add (compile-asm (lit (fn (_ a b) (%box (+ (%unbox a) (%unbox b))))) () (lit function)))
(write (list (%fw-add 2 3) (%fw-add -7 100000)))
```
---
    (5 99993)

### a local is a cell

```x
(def %fw-t (fn (_ n) ((fn (self k acc) (if (= k 0) acc (self (- k 1) (pair (list (lit lit) ()) acc)))) n ())))
(def %fw-loc-fv (list (pair (lit t) (%fw-t 3)) (pair (lit p) pair)))
(def %fw-loc (compile-asm
  (lit (fn (_ a b) (do (def s (%box (+ (%unbox a) (%unbox b)))) (%call-q t p s a))))
  %fw-loc-fv (lit function)))
(write (%fw-loc 4 5))
```
---
    (9 . 4)

### truth is nil or #f, as in the other object worlds

```x
(def %fw-truth (compile-asm (lit (fn (_ x) (if x t f)))
  (list (pair (lit t) (lit yes)) (pair (lit f) (lit no))) (lit function)))
(write (list (%fw-truth #f) (%fw-truth ()) (%fw-truth 0) (%fw-truth (list 1))))
```
---
    ('no 'no 'yes 'yes)

### a parameter the call does not pass is nil

```x
(def %fw-second (compile-asm (lit (fn (_ a b) b)) () (lit function)))
(write (list (%fw-second 1 2) (%fw-second 1)))
```
---
    (2 ())

## calls

### a call passes values: a symbol and a list arrive as themselves

```x
(def %fw-id (fn (_ x) x))
(def %fw-pass-fv (list (pair (lit t) (%fw-t 2)) (pair (lit g) %fw-id)))
(def %fw-pass (compile-asm (lit (fn (_ a) (%call-q t g a))) %fw-pass-fv (lit function)))
(write (list (%fw-pass (lit pid)) (%fw-pass (list (lit use) 1))))
```
---
    ('pid ('use 1))

### a collect inside a callee keeps every object the frame holds

```x
(def %fw-churn (fn (_ x) (Heap collect) (List range 0 200) x))
(def %fw-keep-fv
  (list (pair (lit t1) (%fw-t 3)) (pair (lit t2) (%fw-t 2)) (pair (lit t3) (%fw-t 3))
        (pair (lit t4) (%fw-t 2)) (pair (lit t5) (%fw-t 3))
        (pair (lit cons) pair) (pair (lit g) %fw-churn)))
(def %fw-keep (compile-asm
  (lit (fn (_ a)
    (do (def p (%call-q t1 cons a a))
        (def r (%call-q t2 g p))
        (def q (%call-q t3 cons r p))
        (def r2 (%call-q t4 g q))
        (%call-q t5 cons r2 p))))
  %fw-keep-fv
  (lit function)))
(write (%fw-keep (list 1 2)))
```
---
    ((((1 2) 1 2) (1 2) 1 2) (1 2) 1 2)

### a call by name refuses: the function world calls through a template

```x
(write (guard (_ (lit refused))
  (compile-asm (lit (fn (_ a) (g a))) (list (pair (lit g) %fw-id)) (lit function))))
```
---
    'refused

### an operand that makes a call refuses at generation

```x
(write (guard (_ (lit refused))
  (compile-asm (lit (fn (_ a) (%call-q t g (%call-q t g a))))
    (list (pair (lit t) (%fw-t 2)) (pair (lit g) %fw-id)) (lit function))))
```
---
    'refused

## self-calls

### a self-call in tail position loops

Its first operand is the call's template, which a jump does not use.

```x
(def %fw-sum-fv (list (pair (lit t) (%fw-t 3))))
(def %fw-sum (compile-asm
  (lit (fn (self n acc)
    (if (= (%unbox n) 0) acc
      (self t (%box (- (%unbox n) 1)) (%box (+ (%unbox acc) (%unbox n)))))))
  %fw-sum-fv (lit function)))
(write (%fw-sum 100000 0))
```
---
    5000050000

## nil where a read expects a value

### first and rest of nil answer what the interpreter answers

```x
(def %fw-first (compile-asm (lit (fn (_ x) (first x))) () (lit function)))
(write (list (%fw-first (list 7 8))
             (guard (_ (lit raised)) (%fw-first ()))
             (guard (_ (lit raised)) (first ()))))
```
---
    (7 'raised 'raised)

### an integer operation on nil raises

```x
(write (guard (_ (lit raised)) (%fw-add () 1)))
```
---
    'raised

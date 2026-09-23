# @lib ../tests/x/lib/compile.x
# @requires native/jit
# @weight 1

`match` in JIT-compiled code. The arms are tried in order and the first
whose test is truthy supplies the value; with no arm taken the value is
nil. A comparison test folds into `cmp` and one conditional branch, as an
`if` test does; any other test is evaluated and tested with `cbz`. A
literal `#t` test takes its arm unconditionally, which is what the
`(#t expr)` default arm means. `if` compiles as a match of one or two
arms, the way `lib/x/core/control.x` derives it, so both forms share one
lowering.

## arms

### the first truthy arm supplies the value

```x
(display ((compile-asm '(fn (_ x) (match ((< x 10) 1) ((< x 100) 2) (#t 3)))) 5))
```
---
    1

### a later arm

```x
(display ((compile-asm '(fn (_ x) (match ((< x 10) 1) ((< x 100) 2) (#t 3)))) 50))
```
---
    2

### the default arm

```x
(display ((compile-asm '(fn (_ x) (match ((< x 10) 1) ((< x 100) 2) (#t 3)))) 500))
```
---
    3

### no arm taken is nil

An integer function boxes its result, so the nil comes back as 0.

```x
(display ((compile-asm '(fn (_ x) (match ((< x 10) 1) ((< x 100) 2)))) 500))
```
---
    0

### a test that is not a comparison is evaluated and tested

```x
(display ((compile-asm '(fn (_ x) (match ((and (> x 0) (< x 10)) 1) (#t 2)))) 7))
```
---
    1

### an equality test

```x
(display ((compile-asm '(fn (_ x) (match ((= x 3) 30) ((= x 4) 40) (#t 0)))) 4))
```
---
    40

### a match is an operand like any other

```x
(display ((compile-asm '(fn (_ x) (+ 100 (match ((= x 1) 1) (#t 2))))) 1))
```
---
    101

### an arm's expression may itself be a match

```x
(display ((compile-asm '(fn (_ x) (match ((< x 10) (match ((< x 5) 1) (#t 2))) (#t 3)))) 7))
```
---
    2

## if is a match

### a two-armed if still takes both branches

```x
(display (list ((compile-asm '(fn (_ x) (if (< x 10) 1 2))) 5)
               ((compile-asm '(fn (_ x) (if (< x 10) 1 2))) 50)))
```
---
    (1 2)

### an if without an else answers nil on the false path

```x
(display ((compile-asm '(fn (_ x) (if (< x 10) 1))) 50))
```
---
    0

## analyser mode

### a state written with match loops itself and scores

The name-token machine from jit-analyser-self, with each state's `if`
written as a `match`.

```x
(do
  (def %b (Base make-tok))
  (def %read-str (prim-ref 'tok 'read-str))
  (def %buf-tok (prim-ref 'buf 'tok))
  (def %name-body
    (compile-asm
      '(fn (me buffer score chr)
        (match
          ((and (>= chr 97) (<= chr 122)) me)
          (#t (%seq (%buffer-unread buffer) (%score-set score 1 buffer)))))
      () #t))
  (def %name-start
    (compile-asm
      '(fn (_ buffer score chr)
        (match ((and (>= chr 97) (<= chr 122)) body)))
      (list (pair 'body %name-body)) #t))
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

### arms that hand back different states

The shape of `dec-int` in lib/x/num/decimal.x: a digit stays in the
state, `d` scores the token, `.` moves to the fraction state, and
anything else declines.

```x
(do
  (def %b (Base make-tok))
  (def %read-str (prim-ref 'tok 'read-str))
  (def %buf-tok (prim-ref 'buf 'tok))
  (def %dec-frac-state
    (compile-asm
      '(fn (me buffer score chr)
        (match
          ((and (>= chr 48) (<= chr 57)) me)
          ((= chr 100) (%score-set score 1 buffer))))
      () #t))
  (def %dec-int-state
    (compile-asm
      '(fn (me buffer score chr)
        (match
          ((and (>= chr 48) (<= chr 57)) me)
          ((= chr 100) (%score-set score 1 buffer))
          ((= chr 46) frac)))
      (list (pair 'frac %dec-frac-state)) #t))
  (def %dec-start
    (compile-asm
      '(fn (_ buffer score chr)
        (match ((and (>= chr 48) (<= chr 57)) int)))
      (list (pair 'int %dec-int-state)) #t))
  (Base make-type %b "S-DEC"
    (list (pair 'analyse %dec-start)
      (pair 'read (fn (_ . args) (%buf-tok (first args))))))
  (Base make-type %b "S-WS"
    (list (pair 'analyse
      (fn (_ buffer score chr)
        (if (= chr 32) (%score-set score -1 buffer) ())))))
  (write (%read-str (Base raw-of %b) "12d 3.5d 40d "))
  (newline))
```
---
    ("12d" "3.5d" "40d")

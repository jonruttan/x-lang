# @lib ../tests/x/lib/compile.x
# @requires native/jit
# @weight 1

An fvar is baked as its object's address, so a compiled state is given the
states it hands to when it is made, and two states that hand to each other
cannot both be. `(first CELL)` and `(rest CELL)` read a pair when the code
runs: CELL is an fvar holding the pair, and what the pair holds is set once
every state exists. The cell is an object of the heap, so the collector
reaches the state it holds through it.

## a state reached through a cell

### two compiled states hand to each other

A run of `a` is read by one state and a run of `b` by the other; each hands
to the other at the other's letter, so a token of both letters goes back and
forth. The first is compiled before the second exists, and reaches it
through the cell's first.

```x
(do
  (def %b (Base make-tok))
  (def %read-str (prim-ref 'tok 'read-str))
  (def %buf-tok (prim-ref 'buf 'tok))
  (def %cell (pair () ()))
  (def %a-run
    (compile-asm
      '(fn (me buffer score chr)
        (match
          ((= chr 97) me)
          ((= chr 98) (first to-b))
          (#t (%seq (%buffer-unread buffer) (%score-set score 1 buffer)))))
      (list (pair 'to-b %cell)) #t))
  (def %b-run
    (compile-asm
      '(fn (me buffer score chr)
        (match
          ((= chr 98) me)
          ((= chr 97) to-a)
          (#t (%seq (%buffer-unread buffer) (%score-set score 1 buffer)))))
      (list (pair 'to-a %a-run)) #t))
  (%set-first! %cell %b-run)
  (Base make-type %b "S-AB"
    (list
      (pair 'analyse
        (compile-asm
          '(fn (_ buffer score chr)
            (match
              ((= chr 97) a)
              ((= chr 98) b)
              (#t ())))
          (list (pair 'a %a-run) (pair 'b %b-run)) #t))
      (pair 'read (fn (_ . args) (%buf-tok (first args))))))
  (Base make-type %b "S-WS"
    (list (pair 'analyse
      (fn (_ buffer score chr)
        (if (= chr 32) (%score-set score -1 buffer) ())))))
  (write (%read-str (Base raw-of %b) "aabbaab ab bbba a abababab "))
  (newline))
```
---
    ("aabbaab" "ab" "bbba" "a" "abababab")

### rest reads the cell's other half, and a first of a rest the next cell

```x
(do
  (def %b (Base make-tok))
  (def %read-str (prim-ref 'tok 'read-str))
  (def %buf-tok (prim-ref 'buf 'tok))
  (def %end
    (compile-asm
      '(fn (_ buffer score chr)
        (%seq (%buffer-unread buffer) (%score-set score 1 buffer)))
      () #t))
  ; (x-state . (y-state))
  (def %cells (pair () (pair () ())))
  (Base make-type %b "S-XY"
    (list
      (pair 'analyse
        (compile-asm
          '(fn (_ buffer score chr)
            (match
              ((= chr 120) (first cells))
              ((= chr 121) (first (rest cells)))
              (#t ())))
          (list (pair 'cells %cells)) #t))
      (pair 'read (fn (_ . args) (%buf-tok (first args))))))
  (%set-first! %cells %end)
  (%set-first! (rest %cells) %end)
  (write (%read-str (Base raw-of %b) "xyx "))
  (newline))
```
---
    ("x" "y" "x")

### a cell that holds nil hands to nothing, and the state declines

```x
(do
  (def %b (Base make-tok))
  (def %read-str (prim-ref 'tok 'read-str))
  (def %buf-tok (prim-ref 'buf 'tok))
  (def %cell (pair () ()))
  (Base make-type %b "S-Q"
    (list
      (pair 'analyse
        (compile-asm
          '(fn (_ buffer score chr)
            (if (= chr 113) (%seq (%score-set score 1 buffer) (first to)) ()))
          (list (pair 'to %cell)) #t))
      (pair 'read (fn (_ . args) (%buf-tok (first args))))))
  (write (%read-str (Base raw-of %b) "qq"))
  (newline))
```
---
    ()

### the collector reaches a state its cell holds

The second state is held by the cell and by nothing else once its name is
rebound, and a collect leaves it where the first state finds it.

```x
(do
  (def %b (Base make-tok))
  (def %read-str (prim-ref 'tok 'read-str))
  (def %buf-tok (prim-ref 'buf 'tok))
  (def %cell (pair () ()))
  (def %a-run
    (compile-asm
      '(fn (me buffer score chr)
        (match
          ((= chr 97) me)
          ((= chr 98) (first to-b))
          (#t (%seq (%buffer-unread buffer) (%score-set score 1 buffer)))))
      (list (pair 'to-b %cell)) #t))
  (def %b-run
    (compile-asm
      '(fn (me buffer score chr)
        (if (= chr 98)
          me
          (%seq (%buffer-unread buffer) (%score-set score 1 buffer))))
      () #t))
  (%set-first! %cell %b-run)
  (set! %b-run ())
  (Base make-type %b "S-AB"
    (list
      (pair 'analyse
        (compile-asm
          '(fn (_ buffer score chr) (if (= chr 97) a ()))
          (list (pair 'a %a-run)) #t))
      (pair 'read (fn (_ . args) (%buf-tok (first args))))))
  (Heap collect)
  ; allocate over whatever the collect freed
  (def %fill (fn (self n acc) (if (= n 0) acc (self (- n 1) (pair n acc)))))
  (%fill 2000 ())
  (write (%read-str (Base raw-of %b) "aabbb "))
  (newline))
```
---
    ("aabbb")

## what first and rest refuse

### an integer function

```x
(guard (e (display (e msg)))
  (compile-asm '(fn (_ x) (first c)) (list (pair 'c (pair 1 2))) #f))
```
---
    asm-compile: first reads an object, and this compile is an integer function, whose result is a number.  Pass #t as compile-asm's third argument for an analyser.

### an operand that is a number

```x
(guard (e (display (e msg)))
  (compile-asm '(fn (_ buffer score chr) (rest chr)) (list (pair 'u 1)) #t))
```
---
    asm-compile: rest cannot take chr as its operand: it reads an object, which is an fvar, an object parameter, or another first or rest.

### an fvar that holds nil

```x
(guard (e (display (e msg)))
  (compile-asm '(fn (_ buffer score chr) (first c)) (list (pair 'c ())) #t))
```
---
    asm-compile: first cannot take the fvar c, which holds nil: bind it to the pair the code is to read.

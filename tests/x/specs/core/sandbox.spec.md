## Base make

### creates a base object

```scheme
(pair? (Base make))
```
---
    #f

### a base survives being displayed (the REPL echo path)

```scheme
(do (def %pb (Base make)) (display %pb) (display "\n") (Base eval %pb (lit (+ 1 2))))
```
---
    3

## Base instances

(Base make) answers a Base INSTANCE wrapping the raw C base (the `raw`
member): methods make the base interactive, every static unwraps either
form, and the tokenizer seams (Tok read-str, Xon's walks) unwrap the
same way -- raw bases from the catalog prims stay plumbing.

### the instance evaluates directly

```scheme
(do (def %ib (Base make)) (%ib eval (lit (* 6 7))))
```
---
    42

### the instance binds directly

```scheme
(do (def %ib2 (Base make)) (%ib2 bind (lit x) 5) (%ib2 eval (lit x)))
```
---
    5

### base? discriminates; raw bases are not instances

```scheme
(list (Base base? (Base make)) (Base base? ((prim-ref 'base 'make))) (Base base? 5))
```
---
    (#t #f #f)

### statics accept the raw form too

```scheme
(do (def %rb2 ((prim-ref 'base 'make))) (Base eval %rb2 (lit (+ 40 2))))
```
---
    42

### raw-of unwraps an instance and passes a raw base through

```scheme
(do (def %ib3 (Base make))
    (list (null? (Base raw-of %ib3))
          (Base base? (Base raw-of %ib3))
          (same? (Base raw-of (%ib3 raw)) (%ib3 raw))))
```
---
    (#f #f #t)

### an instance renders by its live allocation count

```scheme
(do (def %ib4 (Base make))
    (def %r ((prim-ref 'io 'display-to-str) %ib4))
    (Str8 includes? "#<base:objs " %r))
```
---
    #t

## base field reflection

Field access walks the layout contract (ext/x-eval-c/tools/contract/base-paths.x):
(b cell 'name) resolves the base-rooted row for name and steps from the
base; (Base fields) lists the names.  A non-base-rooted name is REFUSED
-- a type-rooted path stepped from a base addresses arbitrary spine
words, and mutating "its cell" would overwrite interpreter state.

### a fresh base's line counter reads 1 through the contract

```scheme
(do (def %fb (Base make)) (%cell-int (first (%fb cell (lit line)))))
```
---
    1

### the field list carries the contract's base-rooted names

```scheme
(do (def %names ((Base make) fields))
    (list (not (null? (List filter (fn (_ n) (eq? n (lit env-alist))) %names)))
          (not (null? (List filter (fn (_ n) (eq? n (lit type-alist))) %names)))
          (null? (List filter (fn (_ n) (eq? n (lit type-write))) %names))))
```
---
    (#t #t #t)

### a non-base-rooted name is refused

```scheme
(do (def %gb (Base make)) (guard (e (lit refused)) (%gb cell (lit type-write))))
```
---
    'refused

### a bound value is visible through the env-alist cell

```scheme
(do (def %eb (Base make))
    (%eb bind (lit marker) 77)
    (def %alist (first (%eb cell (lit env-alist))))
    (rest (first %alist)))
```
---
    77

### new base has arithmetic

```scheme
(do (def b (Base make)) (Base eval b (lit (+ 1 2))))
```
---
    3

### new base has def

```scheme
(do (def b (Base make)) (Base eval b (lit (def x 10))) (Base eval b 'x))
```
---
    10

## base isolation

### parent binding not visible in child

```scheme
(do (def x 10) (def b (Base make)) (guard (e 'isolated) (Base eval b 'x)))
```
---
    'isolated

### child binding not visible in parent

```scheme
(do (def b (Base make)) (Base eval b (lit (def cx 42))) (guard (e 'isolated) cx))
```
---
    'isolated

### two bases are independent

```scheme
(do (def a (Base make)) (def b (Base make)) (Base eval a (lit (def x 1))) (Base eval b (lit (def x 2))) (+ (Base eval a 'x) (Base eval b 'x)))
```
---
    3

## Base eval

### evaluates arithmetic

```scheme
(do (def b (Base make)) (Base eval b (lit (* 6 7))))
```
---
    42

### evaluates closures

```scheme
(do (def b (Base make)) (Base eval b (lit (%seq (def f (fn (_ x) (* x x))) (f 5)))))
```
---
    25

### propagates errors to parent guard

```scheme
(do (def b (Base make)) (guard (e 'caught) (Base eval b (lit (error "boom")))))
```
---
    'caught

## Base bind

### binds a value in target base

```scheme
(do (def b (Base make)) (Base bind b 'x 42) (Base eval b 'x))
```
---
    42

### binds a list in target base

```scheme
(do (def b (Base make)) (Base bind b 'xs (list 1 2 3)) (Base eval b (lit (first xs))))
```
---
    1

### does not affect parent

```scheme
(do (def b (Base make)) (Base bind b 'z 99) (guard (e 'ok) z))
```
---
    'ok

## make-token-base

### creates a base object

```scheme
(not (null? (Base make-tok)))
```
---
    #t

### bare base produces no tokens

```scheme
(null? (Tok read-str (Base make-tok) "hello"))
```
---
    #t

## base-make-type

### single custom type tokenizes

```scheme
(do (def %tb1 (Base make-tok))
    (def %buf-tok (prim-ref 'buf 'tok))
    (def %tb1-r (fn (_ . args) (list 'word (%buf-tok (first args)))))
    (def %tb1-a ()) (set! %tb1-a (fn (_ buffer score chr)
      (if (or (= chr 32) (= chr 10)) (do (%buffer-unread buffer) (%score-set score -1 buffer))
        %tb1-a)))
    (Base make-type %tb1 "WORD" (list (pair 'analyse (fn (_ buffer score chr)
      (if (and (>= chr 33) (<= chr 126)) (do (%score-set score -1 buffer) %tb1-a) ())))
      (pair 'read %tb1-r)))
    (first (first (Tok read-str %tb1 "hello"))))
```
---
    'word

### multiple types with discard

```scheme
(do (def %tb2 (Base make-tok))
    (def %buf-tok (prim-ref 'buf 'tok))
    (def %tb2-r (fn (_ . args) (list 'word (%buf-tok (first args)))))
    (def %tb2-a ()) (set! %tb2-a (fn (_ buffer score chr)
      (if (or (= chr 32) (= chr 10)) (do (%buffer-unread buffer) (%score-set score -1 buffer))
        %tb2-a)))
    (Base make-type %tb2 "WORD" (list (pair 'analyse (fn (_ buffer score chr)
      (if (and (>= chr 33) (<= chr 126)) (do (%score-set score -1 buffer) %tb2-a) ())))
      (pair 'read %tb2-r)))
    (Base make-type %tb2 "WS" (list (pair 'analyse (fn (_ buffer score chr)
      (if (= chr 32) (%score-set score -1 buffer) ())))))
    (List length (Tok read-str %tb2 "hello world")))
```
---
    2

### reader extracts buffer-token

```scheme
(do (def %tb3 (Base make-tok))
    (def %buf-tok (prim-ref 'buf 'tok))
    (def %tb3-r (fn (_ . args) (%buf-tok (first args))))
    (def %tb3-body ()) (set! %tb3-body (fn (_ buffer score chr)
      (if (or (= chr 32) (= chr 10)) (do (%buffer-unread buffer) (%score-set score -1 buffer))
        %tb3-body)))
    (Base make-type %tb3 "ALL" (list (pair 'analyse (fn (_ buffer score chr)
      (if (and (>= chr 33) (<= chr 126)) (do (%score-set score -1 buffer) %tb3-body) ())))
      (pair 'read %tb3-r)))
    (%str-length (first (Tok read-str %tb3 "hello"))))
```
---
    5

### deterministic positive scoring

```scheme
(do (def %tb4 (Base make-tok))
    (def %buf-tok (prim-ref 'buf 'tok))
    (def %tb4-r (fn (_ . args) (%buf-tok (first args))))
    (def %tb4-body ()) (set! %tb4-body (fn (_ buffer score chr)
      (if (= chr 10)
        (do (%buffer-unread buffer) (%score-set score 1 buffer))
        %tb4-body)))
    (Base make-type %tb4 "LINE" (list (pair 'analyse (fn (_ buffer score chr)
      (if (and (>= chr 32) (<= chr 126)) (do (%score-set score 1 buffer) %tb4-body) ())))
      (pair 'read %tb4-r)))
    (%str-length (first (Tok read-str %tb4 "hello\n"))))
```
---
    5

### greedy negative scoring

```scheme
(do (def %tb5 (Base make-tok))
    (def %buf-tok (prim-ref 'buf 'tok))
    (def %tb5-r (fn (_ . args) (list 'tok (%buf-tok (first args)))))
    (def %tb5-body ()) (set! %tb5-body (fn (_ buffer score chr)
      (if (= chr 32) (do (%buffer-unread buffer) (%score-set score -1 buffer))
        %tb5-body)))
    (Base make-type %tb5 "WORD" (list (pair 'analyse (fn (_ buffer score chr)
      (if (and (>= chr 97) (<= chr 122)) (do (%score-set score -1 buffer) %tb5-body) ())))
      (pair 'read %tb5-r)))
    (Base make-type %tb5 "WS" (list (pair 'analyse (fn (_ buffer score chr)
      (if (= chr 32) (%score-set score -1 buffer) ())))))
    (first (first (Tok read-str %tb5 "abc def"))))
```
---
    'tok

### custom type coexists with built-in types

```scheme
(do (def %tb6 ((Base make) raw))
    (def %tb6-r (fn (_ . args) (list '%comment (%buf-tok (first args)))))
    (def %tb6-body ()) (set! %tb6-body (fn (_ buffer score chr)
      (if (= chr 10) (%score-set score 1 buffer) %tb6-body)))
    (Base make-type %tb6 "FMT-COMMENT" (list (pair 'analyse (fn (_ buffer score chr)
      (if (= chr 59) (do (%score-set score 1 buffer) %tb6-body) ())))
      (pair 'read %tb6-r)))
    (def %tb6-ta (first (first (first (first (rest (first %tb6)))))))
    (%set-first! (first (first (first (rest (first %tb6))))) (List append (rest %tb6-ta) (list (first %tb6-ta))))
    (def %tb6-tokens (Tok read-str %tb6 "; hi\n(+ 1 2)"))
    (first (first %tb6-tokens)))
```
---
    '%comment

## token-read-string

### make-base includes sexp types

```scheme
(first (Tok read-str (Base make) "(+ 1 2)"))
```
---
    ('+ 1 2)

### multi-token sexp input

```scheme
(List length (Tok read-str (Base make) "(+ 1 2) (* 3 4)"))
```
---
    2

## type alist manipulation

### access type alist

```scheme
(do (def %tb7 ((Base make) raw)) (not (null? (first (first (first (first (rest (first %tb7)))))))))
```
---
    #t

### move entry from front to end

```scheme
(do (def %tb8 ((Base make) raw))
    (def %tb8-a (Base make-type %tb8 "A" (list (pair 'analyse (fn (_ buffer score chr) ())))))
    (def %tb8-b (Base make-type %tb8 "B" (list (pair 'analyse (fn (_ buffer score chr) ())))))
    (def %tb8-ta (first (first (first (first (rest (first %tb8)))))))
    (%set-first! (first (first (first (rest (first %tb8))))) (List append (rest %tb8-ta) (list (first %tb8-ta))))
    (def %tb8-new (first (first (first (first (rest (first %tb8)))))))
    (eq? (first (first %tb8-new)) %tb8-a))
```
---
    #t

### last entry wins scoring ties

```scheme
(do (def %tb9 (Base make-tok))
    (def %buf-tok (prim-ref 'buf 'tok))
    (def %tb9-r1 (fn (_ . args) 'first-type))
    (def %tb9-r2 (fn (_ . args) 'second-type))
    (Base make-type %tb9 "T1" (list (pair 'analyse (fn (_ buffer score chr)
      (if (and (>= chr 97) (<= chr 122)) (%score-set score 1 buffer) ())))
      (pair 'read %tb9-r1)))
    (Base make-type %tb9 "T2" (list (pair 'analyse (fn (_ buffer score chr)
      (if (and (>= chr 97) (<= chr 122)) (%score-set score 1 buffer) ())))
      (pair 'read %tb9-r2)))
    (first (Tok read-str %tb9 "x")))
```
---
    'first-type

## bare-children contract

A fresh base is the bare C ISA -- arithmetic, binding, eval -- and nothing
more.  The x layers (output verbs, the catalog protocol) live in the PARENT;
reaching into a child is done with parent closures or (Base bind), never by
expecting a library inside.  (The pre-x-printer C runtime bound display and
prim-ref into every child; that was incidental, and no consumer used it.)

### a child has no display

```scheme
(do (def %bc1 (Base make))
    (guard (e 'bare) (Base eval %bc1 (lit (display 42)))))
```
---
    'bare

### a child has no catalog protocol

```scheme
(do (def %bc2 (Base make))
    (guard (e 'bare) (Base eval %bc2 (lit (prim-ref 'int '+)))))
```
---
    'bare

### the C ISA is present: arithmetic, def, eval

```scheme
(do (def %bc3 (Base make))
    (Base eval %bc3 (lit (def x (* 6 7))))
    (Base eval %bc3 'x))
```
---
    42

### the parent reaches in with closures

```scheme
(do (def %bc4 (Base make))
    (Base bind %bc4 'shout (fn (_ v) (display v) (display "!")))
    (Base eval %bc4 (lit (shout 7))))
```
---
    7!

### a child built-in tree carries fewer write handlers than the parent's

The contract, OBSERVABLE through the reflection doors instead of
folklore: the parent's INTEGER write stack holds the C-era handler plus
the x printer's boot push; a fresh child's INTEGER tree never received
the boot push, so its stack is strictly shorter (and non-empty -- the C
registration itself installs one).  The child's tree is found by NAME
BYTES through the raw reflect walk -- child handles do not intern into
the parent, and the handler spines are C-built (pair? answers #f), so
the canonical List walkers must not touch them.

```scheme
(do
  (def %count (fn (self l) (if (null? l) 0 (+ 1 (self (rest l))))))
  (def %hb (Base make))
  (def %find-tree
    (fn (self nm al)
      (if (null? al) ()
        (if (str=? (%reflect-sym->str (%reflect-type-tree-name (rest (first al)))) nm)
          (rest (first al))
          (self nm (rest al))))))
  (def %child-n (%count
    ((Type wrap (%find-tree "INTEGER" (first (%hb cell (lit type-alist)))))
      cell (lit type-write-stack))))
  (def %parent-n (%count ((Type wrap (Type of 0)) cell (lit type-write-stack))))
  (list (> %parent-n %child-n) (> %child-n 0)))
```
---
    (#t #t)

## raw prims guard nil in a child base (#239)

A `(Base make)` child gets the C prims raw -- the lib wrappers
(lib/x/core/arithmetic.x) are absent -- so the bitwise family's nil guard
must live in the prims themselves. Before #239 each of these killed the
whole process.

One child per op here is incidental; a single child now survives
repeated caught errors (see "repeated caught errors" below, #253).

### the bitwise family raises catchably on nil operands

```scheme
(do (def %bn (Base make))
    (list (guard (e (lit R)) (Base eval %bn (lit (~ ()))))
          (guard (e (lit R)) (Base eval %bn (lit (& () 1))))
          (guard (e (lit R)) (Base eval %bn (lit (| 1 ()))))
          (guard (e (lit R)) (Base eval %bn (lit (^ () 1))))
          (guard (e (lit R)) (Base eval %bn (lit (<< 1 ()))))
          (guard (e (lit R)) (Base eval %bn (lit (>> () 1))))))
```
---
    ('R 'R 'R 'R 'R 'R)

## repeated caught errors leave the child usable (#253)

`base-eval` installs a setjmp handler in the target base. Its handler
pair-tree used to be built one wrapper shallower than `guard`'s, so the
shared `x_error_handler_saved_env` accessor (which reads the env one
level below an `(env . boundary)` cell) restored `first(env)` instead of
`env` on every caught error -- degrading the child's env-alist head each
time until a symbol lookup walked a non-pair and segfaulted (the
"fifth caught error" crash). The handler now matches `guard`'s shape and
restores both env and boundary.

### many caught errors, then the child still evaluates

```scheme
(do (def %b (Base make))
    (def %loop ())
    (set! %loop (fn (_ n) (if (eq? n 0) 'done
      (do (guard (e ()) (Base eval %b 'unbound)) (%loop (- n 1))))))
    (%loop 50)
    (Base eval %b (lit (+ 40 2))))
```
---
    42

### a child binding survives repeated caught errors

```scheme
(do (def %b (Base make))
    (Base eval %b (lit (def keep 77)))
    (guard (e ()) (Base eval %b 'n1)) (guard (e ()) (Base eval %b 'n2))
    (guard (e ()) (Base eval %b 'n3)) (guard (e ()) (Base eval %b 'n4))
    (guard (e ()) (Base eval %b 'n5)) (guard (e ()) (Base eval %b 'n6))
    (Base eval %b 'keep))
```
---
    77

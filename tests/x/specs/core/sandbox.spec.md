## Base make

### creates a base object

```scheme
(pair? (Base make))
```
---
    #f

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
      (if (or (= chr 32) (= chr 10)) (do (buffer-unread buffer) (score-set score (- 0 1) buffer))
        %tb1-a)))
    (Base make-type %tb1 "WORD" (list (pair 'analyse (fn (_ buffer score chr)
      (if (and (>= chr 33) (<= chr 126)) (do (score-set score (- 0 1) buffer) %tb1-a) ())))
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
      (if (or (= chr 32) (= chr 10)) (do (buffer-unread buffer) (score-set score (- 0 1) buffer))
        %tb2-a)))
    (Base make-type %tb2 "WORD" (list (pair 'analyse (fn (_ buffer score chr)
      (if (and (>= chr 33) (<= chr 126)) (do (score-set score (- 0 1) buffer) %tb2-a) ())))
      (pair 'read %tb2-r)))
    (Base make-type %tb2 "WS" (list (pair 'analyse (fn (_ buffer score chr)
      (if (= chr 32) (score-set score (- 0 1) buffer) ())))))
    (length (Tok read-str %tb2 "hello world")))
```
---
    2

### reader extracts buffer-token

```scheme
(do (def %tb3 (Base make-tok))
    (def %buf-tok (prim-ref 'buf 'tok))
    (def %tb3-r (fn (_ . args) (%buf-tok (first args))))
    (def %tb3-body ()) (set! %tb3-body (fn (_ buffer score chr)
      (if (or (= chr 32) (= chr 10)) (do (buffer-unread buffer) (score-set score (- 0 1) buffer))
        %tb3-body)))
    (Base make-type %tb3 "ALL" (list (pair 'analyse (fn (_ buffer score chr)
      (if (and (>= chr 33) (<= chr 126)) (do (score-set score (- 0 1) buffer) %tb3-body) ())))
      (pair 'read %tb3-r)))
    (str-length (first (Tok read-str %tb3 "hello"))))
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
        (do (buffer-unread buffer) (score-set score 1 buffer))
        %tb4-body)))
    (Base make-type %tb4 "LINE" (list (pair 'analyse (fn (_ buffer score chr)
      (if (and (>= chr 32) (<= chr 126)) (do (score-set score 1 buffer) %tb4-body) ())))
      (pair 'read %tb4-r)))
    (str-length (first (Tok read-str %tb4 "hello\n"))))
```
---
    5

### greedy negative scoring

```scheme
(do (def %tb5 (Base make-tok))
    (def %buf-tok (prim-ref 'buf 'tok))
    (def %tb5-r (fn (_ . args) (list 'tok (%buf-tok (first args)))))
    (def %tb5-body ()) (set! %tb5-body (fn (_ buffer score chr)
      (if (= chr 32) (do (buffer-unread buffer) (score-set score (- 0 1) buffer))
        %tb5-body)))
    (Base make-type %tb5 "WORD" (list (pair 'analyse (fn (_ buffer score chr)
      (if (and (>= chr 97) (<= chr 122)) (do (score-set score (- 0 1) buffer) %tb5-body) ())))
      (pair 'read %tb5-r)))
    (Base make-type %tb5 "WS" (list (pair 'analyse (fn (_ buffer score chr)
      (if (= chr 32) (score-set score (- 0 1) buffer) ())))))
    (first (first (Tok read-str %tb5 "abc def"))))
```
---
    'tok

### custom type coexists with built-in types

```scheme
(do (def %tb6 (Base make))
    (def %tb6-r (fn (_ . args) (list '%comment (%buf-tok (first args)))))
    (def %tb6-body ()) (set! %tb6-body (fn (_ buffer score chr)
      (if (= chr 10) (score-set score 1 buffer) %tb6-body)))
    (Base make-type %tb6 "FMT-COMMENT" (list (pair 'analyse (fn (_ buffer score chr)
      (if (= chr 59) (do (score-set score 1 buffer) %tb6-body) ())))
      (pair 'read %tb6-r)))
    (def %tb6-ta (first (first (first (first (rest (first %tb6)))))))
    (set-first! (first (first (first (rest (first %tb6))))) (append (rest %tb6-ta) (list (first %tb6-ta))))
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
(length (Tok read-str (Base make) "(+ 1 2) (* 3 4)"))
```
---
    2

## type alist manipulation

### access type alist

```scheme
(do (def %tb7 (Base make)) (not (null? (first (first (first (first (rest (first %tb7)))))))))
```
---
    #t

### move entry from front to end

```scheme
(do (def %tb8 (Base make))
    (def %tb8-a (Base make-type %tb8 "A" (list (pair 'analyse (fn (_ buffer score chr) ())))))
    (def %tb8-b (Base make-type %tb8 "B" (list (pair 'analyse (fn (_ buffer score chr) ())))))
    (def %tb8-ta (first (first (first (first (rest (first %tb8)))))))
    (set-first! (first (first (first (rest (first %tb8))))) (append (rest %tb8-ta) (list (first %tb8-ta))))
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
      (if (and (>= chr 97) (<= chr 122)) (score-set score 1 buffer) ())))
      (pair 'read %tb9-r1)))
    (Base make-type %tb9 "T2" (list (pair 'analyse (fn (_ buffer score chr)
      (if (and (>= chr 97) (<= chr 122)) (score-set score 1 buffer) ())))
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

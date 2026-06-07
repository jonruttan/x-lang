## make-base

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
(do (def b (Base make)) (Base eval b (lit (def x 10))) (Base eval b (lit x)))
```
---
    10

## base isolation

### parent binding not visible in child

```scheme
(do (def x 10) (def b (Base make)) (guard (e (lit isolated)) (Base eval b (lit x))))
```
---
    (lit isolated)

### child binding not visible in parent

```scheme
(do (def b (Base make)) (Base eval b (lit (def cx 42))) (guard (e (lit isolated)) cx))
```
---
    (lit isolated)

### two bases are independent

```scheme
(do (def a (Base make)) (def b (Base make)) (Base eval a (lit (def x 1))) (Base eval b (lit (def x 2))) (+ (Base eval a (lit x)) (Base eval b (lit x))))
```
---
    3

## base-eval

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
(do (def b (Base make)) (guard (e (lit caught)) (Base eval b (lit (error "boom")))))
```
---
    (lit caught)

## base-bind

### binds a value in target base

```scheme
(do (def b (Base make)) (Base bind b (lit x) 42) (Base eval b (lit x)))
```
---
    42

### binds a list in target base

```scheme
(do (def b (Base make)) (Base bind b (lit xs) (list 1 2 3)) (Base eval b (lit (first xs))))
```
---
    1

### does not affect parent

```scheme
(do (def b (Base make)) (Base bind b (lit z) 99) (guard (e (lit ok)) z))
```
---
    (lit ok)

## make-token-base

### creates a base object

```scheme
(not (null? (Base make-tok)))
```
---
    #t

### bare base produces no tokens

```scheme
(null? (token-read-string (Base make-tok) "hello"))
```
---
    #t

## base-make-type

### single custom type tokenizes

```scheme
(do (def %tb1 (Base make-tok))
    (def %tb1-r (fn (_ . args) (list (lit word) (buffer-token (first args)))))
    (def %tb1-a ()) (set! %tb1-a (fn (_ buffer score chr)
      (if (or (= chr 32) (= chr 10)) (do (buffer-unread buffer) (score-set score (- 0 1) buffer))
        %tb1-a)))
    (Base make-type %tb1 "WORD" (list (pair (lit analyse) (fn (_ buffer score chr)
      (if (and (>= chr 33) (<= chr 126)) (do (score-set score (- 0 1) buffer) %tb1-a) ())))
      (pair (lit read) %tb1-r)))
    (first (first (token-read-string %tb1 "hello"))))
```
---
    (lit word)

### multiple types with discard

```scheme
(do (def %tb2 (Base make-tok))
    (def %tb2-r (fn (_ . args) (list (lit word) (buffer-token (first args)))))
    (def %tb2-a ()) (set! %tb2-a (fn (_ buffer score chr)
      (if (or (= chr 32) (= chr 10)) (do (buffer-unread buffer) (score-set score (- 0 1) buffer))
        %tb2-a)))
    (Base make-type %tb2 "WORD" (list (pair (lit analyse) (fn (_ buffer score chr)
      (if (and (>= chr 33) (<= chr 126)) (do (score-set score (- 0 1) buffer) %tb2-a) ())))
      (pair (lit read) %tb2-r)))
    (Base make-type %tb2 "WS" (list (pair (lit analyse) (fn (_ buffer score chr)
      (if (= chr 32) (score-set score (- 0 1) buffer) ())))))
    (length (token-read-string %tb2 "hello world")))
```
---
    2

### reader extracts buffer-token

```scheme
(do (def %tb3 (Base make-tok))
    (def %tb3-r (fn (_ . args) (buffer-token (first args))))
    (def %tb3-body ()) (set! %tb3-body (fn (_ buffer score chr)
      (if (or (= chr 32) (= chr 10)) (do (buffer-unread buffer) (score-set score (- 0 1) buffer))
        %tb3-body)))
    (Base make-type %tb3 "ALL" (list (pair (lit analyse) (fn (_ buffer score chr)
      (if (and (>= chr 33) (<= chr 126)) (do (score-set score (- 0 1) buffer) %tb3-body) ())))
      (pair (lit read) %tb3-r)))
    (str-length (first (token-read-string %tb3 "hello"))))
```
---
    5

### deterministic positive scoring

```scheme
(do (def %tb4 (Base make-tok))
    (def %tb4-r (fn (_ . args) (buffer-token (first args))))
    (def %tb4-body ()) (set! %tb4-body (fn (_ buffer score chr)
      (if (= chr 10)
        (do (buffer-unread buffer) (score-set score 1 buffer))
        %tb4-body)))
    (Base make-type %tb4 "LINE" (list (pair (lit analyse) (fn (_ buffer score chr)
      (if (and (>= chr 32) (<= chr 126)) (do (score-set score 1 buffer) %tb4-body) ())))
      (pair (lit read) %tb4-r)))
    (str-length (first (token-read-string %tb4 "hello\n"))))
```
---
    5

### greedy negative scoring

```scheme
(do (def %tb5 (Base make-tok))
    (def %tb5-r (fn (_ . args) (list (lit tok) (buffer-token (first args)))))
    (def %tb5-body ()) (set! %tb5-body (fn (_ buffer score chr)
      (if (= chr 32) (do (buffer-unread buffer) (score-set score (- 0 1) buffer))
        %tb5-body)))
    (Base make-type %tb5 "WORD" (list (pair (lit analyse) (fn (_ buffer score chr)
      (if (and (>= chr 97) (<= chr 122)) (do (score-set score (- 0 1) buffer) %tb5-body) ())))
      (pair (lit read) %tb5-r)))
    (Base make-type %tb5 "WS" (list (pair (lit analyse) (fn (_ buffer score chr)
      (if (= chr 32) (score-set score (- 0 1) buffer) ())))))
    (first (first (token-read-string %tb5 "abc def"))))
```
---
    (lit tok)

### custom type coexists with built-in types

```scheme
(do (def %tb6 (Base make))
    (def %tb6-r (fn (_ . args) (list (lit %comment) (buffer-token (first args)))))
    (def %tb6-body ()) (set! %tb6-body (fn (_ buffer score chr)
      (if (= chr 10) (score-set score 1 buffer) %tb6-body)))
    (Base make-type %tb6 "FMT-COMMENT" (list (pair (lit analyse) (fn (_ buffer score chr)
      (if (= chr 59) (do (score-set score 1 buffer) %tb6-body) ())))
      (pair (lit read) %tb6-r)))
    (def %tb6-ta (first (first (first (first (rest (first %tb6)))))))
    (set-first! (first (first (first (rest (first %tb6))))) (append (rest %tb6-ta) (list (first %tb6-ta))))
    (def %tb6-tokens (token-read-string %tb6 "; hi\n(+ 1 2)"))
    (first (first %tb6-tokens)))
```
---
    (lit %comment)

## token-read-string

### make-base includes sexp types

```scheme
(first (token-read-string (Base make) "(+ 1 2)"))
```
---
    ((lit +) 1 2)

### multi-token sexp input

```scheme
(length (token-read-string (Base make) "(+ 1 2) (* 3 4)"))
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
    (def %tb8-a (Base make-type %tb8 "A" (list (pair (lit analyse) (fn (_ buffer score chr) ())))))
    (def %tb8-b (Base make-type %tb8 "B" (list (pair (lit analyse) (fn (_ buffer score chr) ())))))
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
    (def %tb9-r1 (fn (_ . args) (lit first-type)))
    (def %tb9-r2 (fn (_ . args) (lit second-type)))
    (Base make-type %tb9 "T1" (list (pair (lit analyse) (fn (_ buffer score chr)
      (if (and (>= chr 97) (<= chr 122)) (score-set score 1 buffer) ())))
      (pair (lit read) %tb9-r1)))
    (Base make-type %tb9 "T2" (list (pair (lit analyse) (fn (_ buffer score chr)
      (if (and (>= chr 97) (<= chr 122)) (score-set score 1 buffer) ())))
      (pair (lit read) %tb9-r2)))
    (first (token-read-string %tb9 "x")))
```
---
    (lit first-type)

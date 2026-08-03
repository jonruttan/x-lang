# @lib ../tests/x/lib/lint.x

## lint: AST walking

### detects undefined symbol reference

```scheme
(do
  (def %result (lint-forms (list (list '+ 'x 1)) () ()))
  (def %undef (lint-undefined (first %result) (first (rest %result))))
  (display (lint-has? "x" %undef)))
```
---
    #t

### defined symbol is not flagged undefined

```scheme
(do
  (def %forms (list (list 'def 'x 1) 'x))
  (def %result (lint-forms %forms () ()))
  (def %undef (lint-undefined (first %result) (first (rest %result))))
  (display (null? %undef)))
```
---
    #t

### detects unused definition

```scheme
(do
  (def %forms (list (list 'def 'x 1)))
  (def %result (lint-forms %forms () ()))
  (def %unused (lint-unused (first %result) (first (rest %result)) ()))
  (display (lint-has? "x" %unused)))
```
---
    #t

### %-prefixed names are not flagged unused

```scheme
(do
  (def %forms (list (list 'def '%internal 1)))
  (def %result (lint-forms %forms () ()))
  (def %unused (lint-unused (first %result) (first (rest %result)) ()))
  (display (null? %unused)))
```
---
    #t

## lint: first/rest argument check

### flags first applied to a quoted non-list

```scheme
(do
  (def %r (lint-forms (list (list 'first (list 'lit 'sym))) () ()))
  (display (null? (lint-first-rest %r))))
```
---
    #f

### does not flag first applied to a variable

```scheme
(do
  (def %r (lint-forms (list (list 'first 'xs)) () ()))
  (display (null? (lint-first-rest %r))))
```
---
    #t

### does not flag rest applied to a quoted list

```scheme
(do
  (def %r (lint-forms (list (list 'rest (list 'lit (list 1 2)))) () ()))
  (display (null? (lint-first-rest %r))))
```
---
    #t

## lint: tail-position def leak check

### flags a def inside a tail-position do

```scheme
(do
  (def %f (list 'fn (list '_ 'x)
            (list 'do (list 'def 'y 1) 'x)))
  (def %r (lint-forms (list %f) () ()))
  (display (lint-has? "y" (lint-leaks %r))))
```
---
    #t

### does not flag a non-tail def (it binds locally)

```scheme
(do
  (def %f (list 'fn (list '_ 'x)
            (list 'def 'y 1) 'x))
  (def %r (lint-forms (list %f) () ()))
  (display (null? (lint-leaks %r))))
```
---
    #t

### flags a def inside a tail if-branch

```scheme
(do
  (def %f (list 'fn (list '_ 'x)
            (list 'if 'c
              (list 'do (list 'def 'z 1) 2) 3)))
  (def %r (lint-forms (list %f) () ()))
  (display (lint-has? "z" (lint-leaks %r))))
```
---
    #t

## lint: pedantic checks (arity / non-callable / duplicate def)

### flags a call with the wrong number of arguments

```scheme
(do
  (def %fs (list
    (list 'def 'f (list 'fn (list '_ 'x 'y) 'x))
    (list 'f 1)))
  (def %r (lint-forms %fs () ()))
  (display (lint-has? "f" (lint-warnings-of "arity" %r))))
```
---
    #t

### does not flag a correct-arity call

```scheme
(do
  (def %fs (list
    (list 'def 'f (list 'fn (list '_ 'x) 'x))
    (list 'f 1)))
  (def %r (lint-forms %fs () ()))
  (display (null? (lint-warnings-of "arity" %r))))
```
---
    #t

### flags calling a non-callable '... head

```scheme
(do
  (def %r (lint-forms (list (list (list 'lit 'g) 1)) () ()))
  (display (null? (lint-warnings-of "call-nonfn" %r))))
```
---
    #f

### flags a duplicate top-level def

```scheme
(do
  (def %r (lint-forms (list (list 'def 'a 1) (list 'def 'a 2)) () ()))
  (display (lint-has? "a" (lint-warnings-of "dup-def" %r))))
```
---
    #t

## lint: pedantic checks (lexical shadow / malformed)

### flags a lexical shadow (inner binding hides an outer local)

```scheme
(do
  (def %r (lint-forms (list '(def f (fn (_ x) (fn (_ x) x)))) () ()))
  (display (lint-has? "x" (lint-warnings-of "shadow" %r))))
```
---
    #t

### flags a let-binding that shadows a param

```scheme
(do
  (def %r (lint-forms (list '(def f (fn (_ x) (let ((x 1)) x)))) () ()))
  (display (lint-has? "x" (lint-warnings-of "shadow" %r))))
```
---
    #t

### does not flag shadowing a global (de-noised)

```scheme
(do
  (def %r (lint-forms (list '(def f (fn (_ list) list))) () ()))
  (display (null? (lint-warnings-of "shadow" %r))))
```
---
    #t

### does not flag the rebind idiom (init mentions the shadowed name)

```scheme
(do
  (def %r (lint-forms (list '(def f (fn (_ lst) (let ((lst (rest lst))) lst)))) () ()))
  (display (null? (lint-warnings-of "shadow" %r))))
```
---
    #t

### does not flag self/_ shadows (conventional self slots)

```scheme
(do
  (def %r (lint-forms (list '(def f (fn (self x) (fn (self y) (self y))))) () ()))
  (display (null? (lint-warnings-of "shadow" %r))))
```
---
    #t

### flags a malformed if (missing branches)

```scheme
(do
  (def %r (lint-forms (list (list 'if 'c)) () ()))
  (display (null? (lint-warnings-of "malformed" %r))))
```
---
    #f

### does not flag a well-formed if

```scheme
(do
  (def %r (lint-forms (list (list 'if 'c 1 2)) () ()))
  (display (null? (lint-warnings-of "malformed" %r))))
```
---
    #t

## lint: pedantic checks (match clause body)

A match clause evaluates ONE body expression; anything after it is dead code
and the miss is silent (#163). Every hit wants a do-wrap, so there is no
allowlist. The warning name is the clause test's head symbol (atom tests
render whole; the writer is hijacked by the walk for lists and symbols).

### flags a match clause with more than one body expression

```scheme
(do
  (def %r (lint-forms (list (list 'match (list #t 1 2))) () ()))
  (display (lint-has? "#t" (lint-warnings-of "match-multi" %r))))
```
---
    #t

### the warning names a compound test by its head

```scheme
(do
  (def %r (lint-forms (list (list 'match (list (list 'null? 'v) 1 2))) () ()))
  (display (lint-has? "null?" (lint-warnings-of "match-multi" %r))))
```
---
    #t

### a do-wrapped clause body is clean

```scheme
(do
  (def %r (lint-forms (list (list 'match (list #t (list 'do 1 2)))) () ()))
  (display (null? (lint-warnings-of "match-multi" %r))))
```
---
    #t

### a single-expression clause body is clean

```scheme
(do
  (def %r (lint-forms (list (list 'match (list #t 1))) () ()))
  (display (null? (lint-warnings-of "match-multi" %r))))
```
---
    #t

## lint: value-call dispatch (the app surface)

A value call routes (Subject selector args...) through %class-call-handler:
the selector is a message name, not a variable reference. Without this the
apps -- class-call-heavy by style -- read every method spelling as
"Undefined". Subjects are recognised by resolving to a non-callable value;
locals and unbound heads keep plain call analysis.

### a selector after a non-callable subject is not a use

```scheme
(do
  (def %zsubject (pair 1 2))
  (def %r (lint-forms (list '(def f (fn (_ s) (%zsubject frobnicate s)))) () ()))
  (display (null? (lint-has? "frobnicate" (first (rest %r))))))
```
---
    #t

### an argument after a callable head is still a use

```scheme
(do
  (def %zfn (fn (_ a b) a))
  (def %r (lint-forms (list '(def g (fn (_ s) (%zfn frobwiggle s)))) () ()))
  (display (lint-has? "frobwiggle" (first (rest %r)))))
```
---
    #t

### method-ref's selector is not a use

```scheme
(do
  (def %r (lint-forms (list '(def h (fn (_ l) (method-ref %zsubject frobnicate)))) () ()))
  (display (null? (lint-has? "frobnicate" (first (rest %r))))))
```
---
    #t

### a nil env-param op lints (the slot is legal; it once crashed the walk)

```scheme
(do
  (def %r (lint-forms (list '(def z (op () () (z)))) () ()))
  (display (null? (lint-undefined (first %r) (first (rest %r))))))
```
---
    #t

### the embedder contract name is known unbound-by-design

```scheme
(do
  (def %r (lint-forms (list '(def q (fn (_) (guard (_ "x") %install-root)))) () ()))
  (display (null? (lint-undefined (first %r) (first (rest %r))))))
```
---
    #t

## lint: false-positive regressions (found by hardening)

### does not flag a 0-arg fn (empty params) called with no args

```scheme
(do
  (def %fs (list
    (list 'def 'f (list 'fn () 1))
    (list 'f)))
  (def %r (lint-forms %fs () ()))
  (display (null? (lint-warnings-of "arity" %r))))
```
---
    #t

### does not flag a data list with a literal head (operative argument)

```scheme
(do
  (def %r (lint-forms (list (list 'foo (list "0" 0))) () ()))
  (display (null? (lint-warnings-of "call-nonfn" %r))))
```
---
    #t

## lint: unused locals (params / let-bindings)

### flags a trailing unused parameter

```scheme
(do
  (def %r (lint-forms (list '(def f (fn (_ x y) x))) () ()))
  (display (lint-has? "y" (lint-warnings-of "unused" %r))))
```
---
    #t

### does not flag a positional (non-trailing) unused parameter

```scheme
(do
  (def %r (lint-forms (list '(def f (fn (_ x y) y))) () ()))
  (display (null? (lint-warnings-of "unused" %r))))
```
---
    #t

### does not flag an unused rest parameter

```scheme
(do
  (def %r (lint-forms (list '(def f (fn (_ x . more) x))) () ()))
  (display (null? (lint-warnings-of "unused" %r))))
```
---
    #t

### does not flag _ (the ignore slot)

```scheme
(do
  (def %r (lint-forms (list '(def f (fn (_ x) x))) () ()))
  (display (null? (lint-warnings-of "unused" %r))))
```
---
    #t

### flags an unused let-binding

```scheme
(do
  (def %r (lint-forms (list '(let ((b 1) (c 2)) b)) () ()))
  (display (lint-has? "c" (lint-warnings-of "unused" %r))))
```
---
    #t

### does not flag a used let-binding

```scheme
(do
  (def %r (lint-forms (list '(let ((b 1) (c 2)) (foo b c))) () ()))
  (display (null? (lint-warnings-of "unused" %r))))
```
---
    #t

## lint: guard error var

### flags an unused guard error var

```scheme
(do
  (def %r (lint-forms (list '(guard (e 1) (foo))) () ()))
  (display (lint-has? "e" (lint-warnings-of "unused" %r))))
```
---
    #t

### does not flag an error var used in a later handler form

```scheme
(do
  (def %r (lint-forms (list '(guard (e (bar) (baz e)) (foo))) () ()))
  (display (null? (lint-warnings-of "unused" %r))))
```
---
    #t

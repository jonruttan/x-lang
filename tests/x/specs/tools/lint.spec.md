## lint: AST walking

### detects undefined symbol reference

```scheme
(do
  (include "lib/x/tool/lint.x")
  (def %result (lint-forms (list (list (lit +) (lit x) 1)) () ()))
  (def %undef (lint-undefined (first %result) (first (rest %result))))
  (display (lint-has? "x" %undef)))
```
---
    #t

### defined symbol is not flagged undefined

```scheme
(do
  (include "lib/x/tool/lint.x")
  (def %forms (list (list (lit def) (lit x) 1) (lit x)))
  (def %result (lint-forms %forms () ()))
  (def %undef (lint-undefined (first %result) (first (rest %result))))
  (display (null? %undef)))
```
---
    #t

### detects unused definition

```scheme
(do
  (include "lib/x/tool/lint.x")
  (def %forms (list (list (lit def) (lit x) 1)))
  (def %result (lint-forms %forms () ()))
  (def %unused (lint-unused (first %result) (first (rest %result)) ()))
  (display (lint-has? "x" %unused)))
```
---
    #t

### %-prefixed names are not flagged unused

```scheme
(do
  (include "lib/x/tool/lint.x")
  (def %forms (list (list (lit def) (lit %internal) 1)))
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
  (include "lib/x/tool/lint.x")
  (def %r (lint-forms (list (list (lit first) (list (lit lit) (lit sym)))) () ()))
  (display (null? (lint-first-rest %r))))
```
---
    #f

### does not flag first applied to a variable

```scheme
(do
  (include "lib/x/tool/lint.x")
  (def %r (lint-forms (list (list (lit first) (lit xs))) () ()))
  (display (null? (lint-first-rest %r))))
```
---
    #t

### does not flag rest applied to a quoted list

```scheme
(do
  (include "lib/x/tool/lint.x")
  (def %r (lint-forms (list (list (lit rest) (list (lit lit) (list 1 2)))) () ()))
  (display (null? (lint-first-rest %r))))
```
---
    #t

## lint: tail-position def leak check

### flags a def inside a tail-position do

```scheme
(do
  (include "lib/x/tool/lint.x")
  (def %f (list (lit fn) (list (lit _) (lit x))
            (list (lit do) (list (lit def) (lit y) 1) (lit x))))
  (def %r (lint-forms (list %f) () ()))
  (display (lint-has? "y" (lint-leaks %r))))
```
---
    #t

### does not flag a non-tail def (it binds locally)

```scheme
(do
  (include "lib/x/tool/lint.x")
  (def %f (list (lit fn) (list (lit _) (lit x))
            (list (lit def) (lit y) 1) (lit x)))
  (def %r (lint-forms (list %f) () ()))
  (display (null? (lint-leaks %r))))
```
---
    #t

### flags a def inside a tail if-branch

```scheme
(do
  (include "lib/x/tool/lint.x")
  (def %f (list (lit fn) (list (lit _) (lit x))
            (list (lit if) (lit c)
              (list (lit do) (list (lit def) (lit z) 1) 2) 3)))
  (def %r (lint-forms (list %f) () ()))
  (display (lint-has? "z" (lint-leaks %r))))
```
---
    #t

## lint: pedantic checks (arity / non-callable / duplicate def)

### flags a call with the wrong number of arguments

```scheme
(do
  (include "lib/x/tool/lint.x")
  (def %fs (list
    (list (lit def) (lit f) (list (lit fn) (list (lit _) (lit x) (lit y)) (lit x)))
    (list (lit f) 1)))
  (def %r (lint-forms %fs () ()))
  (display (lint-has? "f" (lint-warnings-of "arity" %r))))
```
---
    #t

### does not flag a correct-arity call

```scheme
(do
  (include "lib/x/tool/lint.x")
  (def %fs (list
    (list (lit def) (lit f) (list (lit fn) (list (lit _) (lit x)) (lit x)))
    (list (lit f) 1)))
  (def %r (lint-forms %fs () ()))
  (display (null? (lint-warnings-of "arity" %r))))
```
---
    #t

### flags calling a non-callable (lit ...) head

```scheme
(do
  (include "lib/x/tool/lint.x")
  (def %r (lint-forms (list (list (list (lit lit) (lit g)) 1)) () ()))
  (display (null? (lint-warnings-of "call-nonfn" %r))))
```
---
    #f

### flags a duplicate top-level def

```scheme
(do
  (include "lib/x/tool/lint.x")
  (def %r (lint-forms (list (list (lit def) (lit a) 1) (list (lit def) (lit a) 2)) () ()))
  (display (lint-has? "a" (lint-warnings-of "dup-def" %r))))
```
---
    #t

## lint: pedantic checks (shadowing / malformed)

### flags a parameter that shadows a global

```scheme
(do
  (include "lib/x/tool/lint.x")
  (def %f (list (lit def) (lit f) (list (lit fn) (list (lit _) (lit list)) (lit list))))
  (def %r (lint-forms (list %f) () ()))
  (display (lint-has? "list" (lint-warnings-of "shadow" %r))))
```
---
    #t

### flags a malformed if (missing branches)

```scheme
(do
  (include "lib/x/tool/lint.x")
  (def %r (lint-forms (list (list (lit if) (lit c))) () ()))
  (display (null? (lint-warnings-of "malformed" %r))))
```
---
    #f

### does not flag a well-formed if

```scheme
(do
  (include "lib/x/tool/lint.x")
  (def %r (lint-forms (list (list (lit if) (lit c) 1 2)) () ()))
  (display (null? (lint-warnings-of "malformed" %r))))
```
---
    #t

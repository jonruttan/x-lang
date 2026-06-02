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

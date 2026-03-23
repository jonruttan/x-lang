## lint: AST walking

### detects undefined symbol reference

```scheme
(do
  (include "lib/x/lint.x")
  (def %result (lint-forms (list (list (lit +) (lit x) 1)) () ()))
  (def %undef (lint-undefined (first %result) (first (rest %result))))
  (display (includes? (lit x) %undef)))
```
---
    #t

### defined symbol is not flagged undefined

```scheme
(do
  (include "lib/x/lint.x")
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
  (include "lib/x/lint.x")
  (def %forms (list (list (lit def) (lit x) 1)))
  (def %result (lint-forms %forms () ()))
  (def %unused (lint-unused (first %result) (first (rest %result)) ()))
  (display (includes? (lit x) %unused)))
```
---
    #t

### %-prefixed names are not flagged unused

```scheme
(do
  (include "lib/x/lint.x")
  (def %forms (list (list (lit def) (lit %internal) 1)))
  (def %result (lint-forms %forms () ()))
  (def %unused (lint-unused (first %result) (first (rest %result)) ()))
  (display (null? %unused)))
```
---
    #t

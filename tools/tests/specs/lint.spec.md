## lint: AST walking

### detects undefined symbol reference

```scheme
(do
  (include "tools/lint-lib.x")
  (def %result (%lint-forms (list (list (lit +) (lit x) 1)) () ()))
  (def %undef (%lint-undefined (first %result) (first (rest %result))))
  (display (includes? (lit x) %undef)))
```
---
    t

### defined symbol is not flagged undefined

```scheme
(do
  (include "tools/lint-lib.x")
  (def %forms (list (list (lit def) (lit x) 1) (lit x)))
  (def %result (%lint-forms %forms () ()))
  (def %undef (%lint-undefined (first %result) (first (rest %result))))
  (display (null? %undef)))
```
---
    t

### detects unused definition

```scheme
(do
  (include "tools/lint-lib.x")
  (def %forms (list (list (lit def) (lit x) 1)
                    (list (lit def) (lit y) 2)
                    (lit y)))
  (def %result (%lint-forms %forms () ()))
  (def %unused (%lint-unused (first %result) (first (rest %result)) ()))
  (display (includes? (lit x) %unused)))
```
---
    t

### used definition is not flagged unused

```scheme
(do
  (include "tools/lint-lib.x")
  (def %forms (list (list (lit def) (lit x) 1)
                    (list (lit def) (lit y) 2)
                    (lit y)))
  (def %result (%lint-forms %forms () ()))
  (def %unused (%lint-unused (first %result) (first (rest %result)) ()))
  (display (null? (includes? (lit y) %unused))))
```
---
    t

### fn params are in scope

```scheme
(do
  (include "tools/lint-lib.x")
  (def %forms (list (list (lit fn) (list (lit a) (lit b))
                     (list (lit +) (lit a) (lit b)))))
  (def %result (%lint-forms %forms () ()))
  (def %undef (%lint-undefined (first %result) (first (rest %result))))
  (display (null? %undef)))
```
---
    t

### op params and env are in scope

```scheme
(do
  (include "tools/lint-lib.x")
  (def %forms (list (list (lit op) (list (lit x)) (lit e)
                     (list (lit eval) (lit x) (lit e)))))
  (def %result (%lint-forms %forms () ()))
  (def %undef (%lint-undefined (first %result) (first (rest %result))))
  (display (null? %undef)))
```
---
    t

### let bindings are in scope

```scheme
(do
  (include "tools/lint-lib.x")
  (def %forms (list (list (lit let)
                     (list (list (lit x) 1))
                     (lit x))))
  (def %result (%lint-forms %forms () ()))
  (def %undef (%lint-undefined (first %result) (first (rest %result))))
  (display (null? %undef)))
```
---
    t

### guard binding is in scope

```scheme
(do
  (include "tools/lint-lib.x")
  (def %forms (list (list (lit guard)
                     (list (lit err) (lit err))
                     (list (lit error) "boom"))))
  (def %result (%lint-forms %forms () ()))
  (def %undef (%lint-undefined (first %result) (first (rest %result))))
  (display (null? %undef)))
```
---
    t

### def allows self-reference

```scheme
(do
  (include "tools/lint-lib.x")
  (def %forms (list (list (lit def) (lit f)
                     (list (lit fn) (list (lit n))
                       (list (lit f) (list (lit -) (lit n) 1))))))
  (def %result (%lint-forms %forms () ()))
  (def %undef (%lint-undefined (first %result) (first (rest %result))))
  (display (null? (includes? (lit f) %undef))))
```
---
    t

### lit is opaque

```scheme
(do
  (include "tools/lint-lib.x")
  (def %forms (list (list (lit lit) (lit foo))))
  (def %result (%lint-forms %forms () ()))
  (display (null? (assoc-keys (first (rest %result))))))
```
---
    t

### quasiquote only walks unquoted parts

```scheme
(do
  (include "tools/lint-lib.x")
  (def %forms (list (list (lit quasi)
                     (list (lit a)
                       (list (lit unquote) (lit b))))))
  (def %result (%lint-forms %forms () ()))
  (def %uses (assoc-keys (first (rest %result))))
  (display (and (includes? (lit b) %uses)
                (not (includes? (lit a) %uses)))))
```
---
    t

### %-prefixed unused defs are suppressed

```scheme
(do
  (include "tools/lint-lib.x")
  (def %forms (list (list (lit def) (lit %internal) 1)))
  (def %result (%lint-forms %forms () ()))
  (def %unused (%lint-unused (first %result) (first (rest %result)) ()))
  (display (null? %unused)))
```
---
    t

### lib mode suppresses all unused warnings

```scheme
(do
  (include "tools/lint-lib.x")
  (def %forms (list (list (lit def) (lit x) 1)))
  (def %result (%lint-forms %forms () ()))
  (def %unused (%lint-unused (first %result) (first (rest %result)) t))
  (display (null? %unused)))
```
---
    t

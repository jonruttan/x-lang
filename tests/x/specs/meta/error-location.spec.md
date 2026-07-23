# Source-location error reporting

An unbound reference inside a `fn` body loaded from a file reports BOTH the
source file and the raise-site line -- via `(io error-line)` / `(io error-file)`
-- even though the `fn` runs at call time, long after its `include` popped. This
is what powers the REPL's `Error [file:line]:` prefix. Regression guard for the
snapshot that survives the guard's handler pop.

The fixture is `tests/x/lib/error-loc-fixture.x`; its `%not-a-real-binding`
sits on line 10.

## file + line for a runtime error in loaded code

### error-line is the fixture's unbound-reference line

```scheme
(do
  (def %el (prim-ref 'io 'error-line))
  (include "tests/x/lib/error-loc-fixture.x")
  (guard (e (%el)) (error-loc-boom ())))
```
---
    10

### error-file is the included fixture path

```scheme
(do
  (def %ef (prim-ref 'io 'error-file))
  (include "tests/x/lib/error-loc-fixture.x")
  (guard (e (%ef)) (error-loc-boom ())))
```
---
    "tests/x/lib/error-loc-fixture.x"

### a bare stdin error carries no file (error-file is "")

```scheme
(do
  (def %ef (prim-ref 'io 'error-file))
  (guard (e (%ef)) (error undefined-thing)))
```
---
    ""

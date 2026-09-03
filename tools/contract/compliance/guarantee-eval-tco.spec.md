# Compliance: `(guarantee eval/tco)`

Proper tail calls, unbounded. Not a performance claim: x-lang's library recurses in
tail position throughout, and binds a tail `def` globally BECAUSE of it, so an
engine without tail calls does not run slowly -- it overflows the stack in ordinary
library code.

The depth is bounded ABOVE by the allocation ceiling, not by ambition. Each
iteration conses an argument spine, and `gc/explicit-only` means none of it is
reclaimed mid-loop, so a long enough loop exhausts the harness's budget even on a
perfectly tail-recursive engine -- the two guarantees constrain each other. 60000
frames is far past any C stack (the same depth crashes this engine outright when
the call is NOT in tail position) and well inside the ceiling.

### deep tail recursion returns rather than crashing

```x
(def %loop (fn (self n) (match ((= n 0) (lit done)) (#t (self (- n 1))))))
(%ok (eq? (%loop 60000) (lit done)))
```
---
    *** ERROR: ok

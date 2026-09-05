# Conformance: the evaluator's state rides the base (profile `core`)

The save stack, the deferred tail, the interrupt flag, and the active
guard chain are base rows, named in `base-paths.x` and walkable from
x-lang. The save stack is the `def` question: empty at the top level,
held over a closure body's non-tail forms, released when the call
returns. The sigint row holds the object `%sigint-flag` names.

The tco and error-handler rows resolve on every engine; what they hold
mid-evaluation is the engine's own.

### the save stack is empty at top level, held in a body, released after

covers: eval

```x
(def %rowv (fn (_ n) (%walk (rest (rest (%assoc n %base-paths))) (%base))))
(def top (%rowv (lit save-stack)))
(def f (fn (_)
  (def inner (%rowv (lit save-stack)))
  inner))
(def held (f 0))
(def after (%rowv (lit save-stack)))
(match ((eq? top ()) ()) (#t (error "TOP-NOT-EMPTY")))
(match ((eq? held ()) (error "NEVER-HELD"))
       ((eq? after ()) (error "HELD-THEN-RELEASED"))
       (#t (error "STILL-HELD")))
```
---
    *** ERROR: HELD-THEN-RELEASED

### a def under a held save does not bind globally

covers: eval

```x
(def f (fn (_)
  (def %esr-local 41)
  %esr-local))
(def r (f 0))
(def g (fn (_ ok) ok))
(match ((eq? r 41) ()) (#t (error "BODY-DEF-BROKEN")))
(match ((eq? (guard (x (lit unbound)) %esr-local) (lit unbound)) (error "DEF-WAS-LOCAL"))
       (#t (error "DEF-LEAKED-GLOBAL")))
```
---
    *** ERROR: DEF-WAS-LOCAL

### the sigint row reaches the flag

covers: eval

```x
(def %rowc (fn (_ n) (%walk (rest (rest (%assoc n %base-paths))) (%base))))
(def sg (first (%rowc (lit sigint))))
(match ((eq? sg %sigint-flag) (error "ROW-IS-FLAG")) (#t (error "ROW-OTHER")))
```
---
    *** ERROR: ROW-IS-FLAG

### the tail and handler rows resolve

covers: eval

```x
(def %rowv (fn (_ n) (%walk (rest (rest (%assoc n %base-paths))) (%base))))
(def a (%rowv (lit tco-expr)))
(def b (%rowv (lit tco-env)))
(def c (%rowv (lit error-handler)))
(match ((eq? (%assoc (lit tco-expr) %base-paths) ()) (error "NO-TCO-EXPR-ROW"))
       ((eq? (%assoc (lit tco-env) %base-paths) ()) (error "NO-TCO-ENV-ROW"))
       ((eq? (%assoc (lit error-handler) %base-paths) ()) (error "NO-HANDLER-ROW"))
       (#t (error "ROWS-RESOLVE")))
```
---
    *** ERROR: ROWS-RESOLVE

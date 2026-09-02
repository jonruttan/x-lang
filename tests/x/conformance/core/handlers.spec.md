# Conformance: behaviour is a type handler (profile `core`)

EVALUATION and APPLICATION are type handlers: what evaluating a value
means is its type's registered `eval`, and a callable is a value whose
type registers `call`. The checks go through `type make`.

### a type's eval handler decides what evaluating its instances means

covers: type/make type/make-instance eval

An instance of a plain type is itself; an instance whose type registers
`eval` is whatever the handler answers. `(eval i)` evaluates the symbol
to the instance and then evaluates the INSTANCE — the second step is the
handler's.

```x
(def %tmake (%coord (lit type) (lit make)))
(def %minst (%coord (lit type) (lit make-instance)))
(def h (%tmake "CONF-EVAL"
  (pair (pair (lit eval) (fn (self v) 42)) ())))
(def i (%minst h 7))
(%ok (eq? (eval i) 42))
```
---
    *** ERROR: ok

### an instance of a type WITHOUT an eval handler is itself

covers: type/make type/make-instance eval

Absence of the handler means the value is its own meaning.

```x
(def %tmake (%coord (lit type) (lit make)))
(def %minst (%coord (lit type) (lit make-instance)))
(def h (%tmake "CONF-PLAIN" ()))
(def i (%minst h 7))
(%ok (eq? (eval i) i))
```
---
    *** ERROR: ok

### a type's call handler makes its instances callable

covers: type/make type/make-instance

A value is callable because its TYPE registers `call` — the same door
the reference's procedures, operatives and primitives come through, and
the door a class layer walks in through.

```x
(def %tmake (%coord (lit type) (lit make)))
(def %minst (%coord (lit type) (lit make-instance)))
(def h (%tmake "CONF-CALL"
  (pair (pair (lit call) (op (x) e 42)) ())))
(def i (%minst h 7))
(%ok (eq? (i 1 2) 42))
```
---
    *** ERROR: ok

### an instance of a type WITHOUT a call handler is not callable

covers: type/make type/make-instance

A head that is not callable makes the form DATA — the form answers
itself, nothing raises.

```x
(def %tmake (%coord (lit type) (lit make)))
(def %minst (%coord (lit type) (lit make-instance)))
(def h (%tmake "CONF-NOCALL" ()))
(def i (%minst h 7))
(def r (i 1 2))
(%ok (eq? (first (rest r)) 1))
```
---
    *** ERROR: ok

### a procedure's state rides slot 1 as (params body env . _)

covers: obj/->ptr ptr/ref-word ptr/->obj int/->ptr

Not decoration: `lib/x/tool/cov.x` walks a PROCEDURE's slot 1 for the
body forms, on whichever engine is underneath. The data offset is probed
the way `lib/x/boot/data.x` probes it; the word stride is the machine's.

```x
(def %o2p (%coord (lit obj) (lit ->ptr)))
(def %prw (%coord (lit ptr) (lit ref-word)))
(def %p2o (%coord (lit ptr) (lit ->obj)))
(def %i2p (%coord (lit int) (lit ->ptr)))
(def probe 12345)
(def %off (fn (self i) (match ((eq? (%prw (%o2p probe) i) probe) i) (#t (self (+ i 1))))))
(def d0 (%off 0))
(def f (fn (zz) 47))
(def state (%p2o (%i2p (%prw (%o2p f) (+ d0 8)))))
(%ok (eq? (first (first state)) (lit zz)))
```
---
    *** ERROR: ok

### make-callable's product is of the primitive type

covers: obj/make-callable type/of

The JIT door and the instruction table are one mechanism: a made
callable IS a primitive, distinguishable from one the engine registered
only by where its entry points.

```x
(def %mc (%coord (lit obj) (lit make-callable)))
(def %i2p (%coord (lit int) (lit ->ptr)))
(def %tof (%coord (lit type) (lit of)))
(def made (%mc (%i2p 4096)))
(def real (%coord (lit tok) (lit read)))
(%ok (eq? (%tof made) (%tof real)))
```
---
    *** ERROR: ok

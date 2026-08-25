# Conformance: behaviour is a type hook (profile `core`)

The engine's design intent, stated by its author: the interpreter can be
re-aimed at any syntax — a JavaScript interpreter, a C compiler, a CPU —
by re-registering types. The mechanism that makes that possible is that
EVALUATION and APPLICATION are type hooks: what evaluating a value means
is its type's registered `eval`, and a callable is a value whose type
registers `call`. These checks pin the mechanism through the front door
(`type make`), the way an embedded language registers itself.

Each asserts the observable that distinguishes doing from NOT doing: a
handler that runs changes the ANSWER, not merely a registration list.

### a type's eval handler decides what evaluating its instances means

covers: type/make type/make-instance core/eval

An instance of a plain type is itself; an instance whose type registers
`eval` is whatever the handler answers. `(eval i)` evaluates the symbol
to the instance and then evaluates the INSTANCE — the second step is the
hook's.

```scheme
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

covers: type/make type/make-instance core/eval

The other half of the law: absence of the hook means the value is its
own meaning. An engine that hardcoded instance evaluation could pass the
check above with a special case; passing both pins the dispatch.

```scheme
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

```scheme
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

```scheme
(def %tmake (%coord (lit type) (lit make)))
(def %minst (%coord (lit type) (lit make-instance)))
(def h (%tmake "CONF-NOCALL" ()))
(def i (%minst h 7))
(def r (i 1 2))
(%ok (eq? (first (rest r)) 1))
```
---
    *** ERROR: ok

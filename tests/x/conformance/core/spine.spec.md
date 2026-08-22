# Conformance: the evaluator spine (profile `core`)

The instructions the evaluator is made of, rather than the ones it operates on.
Several are reachable only as bare names because they ARE the binder.

### %base answers the interpreter's own base object

covers: %base

Everything reflective starts here: the prelude walks the committed base paths from
`(%base)` to reach the prims catalog, so an engine without it cannot even be asked
what it provides.

```scheme
(%ok (match ((eq? (%base) ()) ()) (#t 1)))
```
---
    *** ERROR: ok

### include loads a file relative to the current directory

covers: include

Repo-mode boot is a chain of includes, so an engine built without this primitive
cannot start the library at all -- which is why `io/include` is a capability in its
own right rather than an assumed convenience. The prelude has already exercised it
by the time this case runs.

```scheme
(%ok (match ((eq? %base-paths ()) ()) (#t 1)))
```
---
    *** ERROR: ok

### wrap makes an operative applicative

covers: wrap

```scheme
(def o (op (x) e x))
(def w (wrap o))
(%ok (= (w (+ 1 2)) 3))
```
---
    *** ERROR: ok

### unwrap recovers the very same operative

covers: unwrap

Identity, not equivalence: `same?`, so an engine that rebuilt an equal operative
would fail. The library relies on this to strip and re-wrap combiners without
losing their identity.

```scheme
(def o (op (x) e x))
(%ok (same? (unwrap (wrap o)) o))
```
---
    *** ERROR: ok

### atomic yields its body's value

covers: atomic

```scheme
(%ok (= (atomic (+ 20 22)) 42))
```
---
    *** ERROR: ok

### tail-eval evaluates a form in a supplied environment

covers: tail-eval

The operative's door back into evaluation: `e` is the CALLER's environment, so an
operative can decide what to evaluate and where.

```scheme
(def probe (op (x) e (tail-eval x e)))
(def y 40)
(%ok (= (probe y) 40))
```
---
    *** ERROR: ok

### eval! evaluates in the CURRENT environment

covers: eval!

Distinct from `tail-eval`: no environment is passed, so a symbol held in a variable
resolves against wherever the call sits. This is the REPL's door, and it is what
lets the compliance suite probe bare primitives from a data list.

```scheme
(def s (lit first))
(%ok (match ((eq? (eval! s) ()) ()) (#t 1)))
```
---
    *** ERROR: ok

### a fresh base can be made, and evaluated into

covers: base/make base/eval

The sandbox door (`docs/sandboxing-tutorial.md`). `(base eval B expr)` runs the
expression inside ANOTHER interpreter context -- not another environment, another
base -- which is x-lang's isolation story and the reason `base/make` exists.

```scheme
(def %mkb (%coord (lit base) (lit make)))
(def %beval (%coord (lit base) (lit eval)))
(def b (%mkb))
(%ok (= (%beval b (lit (+ 2 3))) 5))
```
---
    *** ERROR: ok

### a sandbox base does not see the host's bindings

covers: base/eval

The property that makes it a sandbox rather than a second env: a name defined out
here is unbound in there, so the expression raises and `guard` catches it.

```scheme
(def %mkb (%coord (lit base) (lit make)))
(def %beval (%coord (lit base) (lit eval)))
(def b (%mkb))
(def host-only 99)
(%ok (guard (e 1) (match ((= (%beval b (lit host-only)) 99) ()) (#t ()))))
```
---
    *** ERROR: ok

### a name can be bound INTO a base, and stays there

covers: base/bind

The capability-handing door of the sandbox (`docs/sandboxing-tutorial.md`): a host
decides what a child base can see by binding it, one name at a time. The second
half is what makes it a capability model rather than a naming convenience -- a
name bound into one base is unbound in another, so a base gets exactly what it was
given.

```scheme
(def %mkb (%coord (lit base) (lit make)))
(def %bind (%coord (lit base) (lit bind)))
(def %beval (%coord (lit base) (lit eval)))
(def b1 (%mkb))
(def b2 (%mkb))
(%bind b1 (lit answer) 42)
(%ok (match ((= (%beval b1 (lit answer)) 42)
              (guard (_ 1) (%seq (%beval b2 (lit answer)) ())))
             (#t ())))
```
---
    *** ERROR: ok

## %seq, %cc-invoke, base/make-tok and base/make-type -- not defined here

`%seq` does not return a value the way a call does: it PRODUCES A TCO
CONTINUATION for the evaluator to resolve in tail position (see
`lib/x/boot/operatives.x`, which notes it must propagate the environment to
exactly that continuation). Asked for a value directly it answers neither its
first argument, its last, nor nil. Defining it in isolation would mean pinning
the shape of an internal handoff rather than a behaviour a library can rely on;
what IS observable is do-body sequencing, and that is `operatives.x`'s contract,
covered by the library's own suite.

`%cc-invoke` is the continuation-application half of `call/cc`, reachable only
with a continuation in hand; the observable behaviour is `call/cc`'s, which
`core/evaluation.spec.md` and `core/catalog-ops.spec.md` both define.

`base/make-tok` and `base/make-type` construct tokenizer and type objects whose
contracts are the reader's and the type registry's, not the spine's. They belong
with those families, and they are named here so the gap is a decision rather than
an oversight.

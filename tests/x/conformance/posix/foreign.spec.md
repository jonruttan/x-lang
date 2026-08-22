# Conformance: the foreign and syscall doors (profile `posix`)

The capabilities a sandboxed or wasm engine drops. `tools/contract/features.x`
splits the ISA's `ffi` tag three ways precisely so these can be absent while the
pointer CASTS stay mandatory: `lib/x/boot` needs the casts and never touches this
family.

Everything here has real side effects on the host, so the cases stay inside
operations that cannot damage anything: resolving a libc symbol, calling a pure
one, and asking the kernel to fail.

### the process's own symbols can be opened and resolved

covers: ffi/dlopen ffi/dlsym

`(ffi dlopen () 1)` is the self/global handle -- the form `lib/x/sys/socket.x` and
`lib/x/sys/posix.x` both use to reach libc without naming a file.

```scheme
(def %dlopen (%coord (lit ffi) (lit dlopen)))
(def %dlsym (%coord (lit ffi) (lit dlsym)))
(def lib (%dlopen () 1))
(%ok (match ((eq? lib ()) ()) (#t (match ((eq? (%dlsym lib "strlen") ()) ()) (#t 1)))))
```
---
    *** ERROR: ok

### a resolved symbol can be called through a pointer

covers: ptr/call

`strlen` is chosen because it is pure, cannot fail, and its answer is checkable
without trusting anything else in the suite.

```scheme
(def %dlopen (%coord (lit ffi) (lit dlopen)))
(def %dlsym (%coord (lit ffi) (lit dlsym)))
(def %pcall (%coord (lit ptr) (lit call)))
(def lib (%dlopen () 1))
(%ok (= (%pcall (%dlsym lib "strlen") "hello") 5))
```
---
    *** ERROR: ok

### an unresolvable symbol answers nil rather than crashing

covers: ffi/dlsym

The failure mode matters as much as the success: the library branches on a nil
handle in several places rather than guarding every lookup.

```scheme
(def %dlopen (%coord (lit ffi) (lit dlopen)))
(def %dlsym (%coord (lit ffi) (lit dlsym)))
(def lib (%dlopen () 1))
(%ok (eq? (%dlsym lib "no_such_symbol_anywhere_at_all") ()))
```
---
    *** ERROR: ok

### the clock answers a number that does not go backwards

covers: sys/clock

```scheme
(def %clock (%coord (lit sys) (lit clock)))
(def t0 (%clock))
(%burn 20000 ())
(%ok (match ((< (%clock) t0) ()) (#t 1)))
```
---
    *** ERROR: ok

### the syscall door reaches the kernel and reports failure as a negative

covers: syscall

The raw contract is the whole of it: hand the kernel a number and its arguments,
and answer what it answers -- a negative value being `-errno`, which every caller
in `lib/x/sys/` folds. `write` to a closed descriptor is the cheapest failure that
asks nothing of the machine.

THE NUMBER COMES FROM THE ENGINE'S DECLARATION, not from the harness. Syscall
numbers are per-OS and per-arch, and this case could not be written until the
engine stamped `(param os ...)` / `(param arch ...)` beside its binary: before
that, a case here would have pinned the harness's `uname` guess -- the platform
of the machine RUNNING the suite, not the platform the engine was BUILT for. The
table below is platform knowledge, which is what it is; selecting a row from it
with a declared fact is the part that was missing.

An unrecognised platform fails loudly rather than passing: a case that quietly
skips is a case that proves nothing.

```scheme
(def %sys-write
  (match
    ((eq? %param-os (lit darwin)) 4)
    ((eq? %param-os (lit linux))
      (match ((eq? %param-arch (lit x86-64)) 1)
             ((eq? %param-arch (lit arm64)) 64)
             ((eq? %param-arch (lit i386)) 4)
             (#t ())))
    (#t ())))
(%ok (match ((eq? %sys-write ()) ()) (#t (< (syscall %sys-write 999 "x" 1) 0))))
```
---
    *** ERROR: ok

### the signature-driven call carries doubles as bit patterns

covers: ffi/call

`ptr/call` cannot express a double: the engine's fixnum is an integer and there is
no float type at this level -- floats are x-lang (`lib/x/num/float.x`). `ffi/call`
is the door for conventions that need one, and it solves the representation
problem by passing the IEEE-754 BITS through an integer in both directions.

That is what makes it testable bare: both sides are plain integers here, and the
values below are the bit patterns of 4.0, 2.0, 3.0 and 9.0. The convention set is
small and closed -- `d->d`, `dd->d` and the arithmetic forms -- rather than a
general signature language, so an engine has to match the spellings exactly.

```scheme
(def %dlopen (%coord (lit ffi) (lit dlopen)))
(def %dlsym (%coord (lit ffi) (lit dlsym)))
(def %fcall (%coord (lit ffi) (lit call)))
(def lib (%dlopen () 1))
(%ok (match ((= (%fcall "d->d" (%dlsym lib "sqrt") 4616189618054758400) 4611686018427387904)
              (= (%fcall "dd->d" (%dlsym lib "pow") 4613937818241073152 4611686018427387904)
                 4621256167635550208))
             (#t ())))
```
---
    *** ERROR: ok

### an installed interrupt handler sets a flag instead of killing the process

covers: sigint-install sigint-restore

The engine's part of ctrl-c. With the default disposition `SIGINT` terminates the
process; with a handler installed it sets `%sigint-flag`, which the evaluator
polls and the REPL turns into a cancelled expression (`lib/x/repl/loop.x`).

The case raises the signal at itself through libc `raise`, which is the only way
to observe the difference, and that is safe here for a reason worth stating: this
runner gives each case ITS OWN engine process, so signal disposition cannot leak
into another case. A broken `install` does not corrupt the run -- it kills that one
process, which the runner reports as a crash rather than as a wrong answer.

An earlier version of this file exempted the pair on the grounds that a failure
"would leave the harness's own process altered, and every later case in the same
run would inherit it". That was simply wrong about the harness.

`restore` runs before the assertion, so the process ends as it began.

```scheme
(include "tools/contract/obj-layout.x")
(def %o2p (%coord (lit obj) (lit ->ptr)))
(def %refw (%coord (lit ptr) (lit ref-word)))
(def %doff (* %param-word-size %obj-meta-len))
(def %dlopen (%coord (lit ffi) (lit dlopen)))
(def %dlsym (%coord (lit ffi) (lit dlsym)))
(def %pcall (%coord (lit ptr) (lit call)))
(def lib (%dlopen () 1))
(def before (%refw (%o2p %sigint-flag) %doff))
(sigint-install)
(%pcall (%dlsym lib "raise") 2)
(def after (%refw (%o2p %sigint-flag) %doff))
(sigint-restore)
(%ok (match ((= before 0) (match ((= after 0) ()) (#t 1))) (#t ())))
```
---
    *** ERROR: ok

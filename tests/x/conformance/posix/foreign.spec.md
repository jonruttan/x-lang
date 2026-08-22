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

## syscall, ffi/call, sigint-install and sigint-restore -- not defined here

`syscall` cannot be given a PORTABLE case here. Syscall numbers are per-OS and
per-arch -- `lib/x/platform/data/` carries three tables for that reason -- so a
case must either name a number (and be wrong on the next platform) or receive one
from the harness. Injecting a per-`uname` table into the runner is exactly the
platform dependency this suite exists to make declarative, and it is what the
engine's own bare harness does today. The right source is the `(param os ...)` /
`(param arch ...)` block an engine will stamp beside its binary; until that lands,
a case here would be pinning the harness's guess rather than the engine's
behaviour.

(An invalid number is not a substitute: `(syscall 999999)` kills the process
outright rather than returning `-errno`, so the failure path is not observable
this way either.)

`ffi/call` is the SIGNATURE-driven variant of `ptr/call`, used where an argument
or return needs a type the pointer call cannot infer (floats, in
`lib/x/num/float.x`). Its contract is the signature language's, and pinning it
here would freeze a notation the library still owns; `ptr/call` above covers the
door itself.

`sigint-install` and `sigint-restore` mutate PROCESS-GLOBAL signal state. A case
that failed between install and restore would leave the harness's own process
altered, and every later case in the same run would inherit it. They are exercised
by the REPL's interactive tests, under a booted engine that can put them back.

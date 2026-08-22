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

## ffi/call, sigint-install and sigint-restore -- not defined here

(`syscall` was here until the engine began declaring its platform; see the case
above. The old objection was real -- a case must not pin the harness's guess --
and it was answered by giving the engine somewhere to state the fact.)

One thing learned the hard way and worth keeping: an INVALID number is not a
substitute for a failing call. `(syscall 999999)` kills the process outright
rather than returning `-errno`, so the failure path is not observable that way.
The case above uses a real number and a closed descriptor.

`ffi/call` is the SIGNATURE-driven variant of `ptr/call`, used where an argument
or return needs a type the pointer call cannot infer (floats, in
`lib/x/num/float.x`). Its contract is the signature language's, and pinning it
here would freeze a notation the library still owns; `ptr/call` above covers the
door itself.

`sigint-install` and `sigint-restore` mutate PROCESS-GLOBAL signal state. A case
that failed between install and restore would leave the harness's own process
altered, and every later case in the same run would inherit it. They are exercised
by the REPL's interactive tests, under a booted engine that can put them back.

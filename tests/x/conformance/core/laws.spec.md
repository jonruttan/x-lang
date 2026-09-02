# Conformance: behavioural laws (profile `core`)

Behaviour the library depends on that no ISA row can express — see
[docs/engine-laws.md](../../../../docs/engine-laws.md). Every check here was
added because a second engine broke the law while every one of its instructions
resolved.

Each asserts the observable that distinguishes DOING it from not doing it. That
is the whole discipline: `applicative/gc-hooks.spec.md` asks whether a registered
hook survives a collection, which is true of a hook nobody calls, and it passed
13 of 13 against an engine whose collector never invoked one.

### eq? compares the operand word, not the type

covers: obj/eq? str/byte-ref

A CHARACTER equals the INTEGER of its code, because `eq?` reads slot 0 of both
operands without asking their kinds. `lib/x/boot/printer.x` rests on it: the
escape classifier is handed `(str byte-ref s i)` and matches it against 34, 92,
10, 9 and 13. An engine that type-gates the comparison misses every arm, and
prints a quote unescaped and a newline as `\x0a`.

```x
(def %bref (%coord (lit str) (lit byte-ref)))
(%ok (eq? (%bref "A" 0) 65))
```
---
    *** ERROR: ok

### a predicate answers the `#t` object

covers: obj/eq? obj/same?

Never a symbol, never nil. Both of those branch correctly, so nothing that merely
TESTS a predicate can tell the difference — only printing one can, which is why
this asserts identity with `#t` rather than truth.

```x
(%ok (same? (eq? 1 1) #t))
```
---
    *** ERROR: ok

### a false answer is `#f`, and is not nil

covers: obj/eq?

```x
(%ok (match ((eq? (eq? 1 2) ()) ()) (#t (same? (eq? 1 2) #f))))
```
---
    *** ERROR: ok

### apply is a tail call

covers: apply

Not an optimisation detail: `lib/x/core/control.x` expands `(let ...)` to
`(apply (eval (fn ...)) vals)`, so an `apply` that runs its callee to a value
instead of parking it makes every `let` in tail position grow the host stack.
Fifty thousand frames is past what an 8MB stack survives.

```x
(def go (fn (self n) (match ((< n 1) 1) (#t (apply self (pair (- n 1) ()))))))
(%ok (= (go 50000) 1))
```
---
    *** ERROR: ok

### byte-sub addresses bytes; it does not slice the NUL-bounded value

covers: str/byte-sub bytes/->str str/byte-len

A buffer a syscall filled is binary. `(str make 4096)` handed to
`getdirentries64` has a NUL in its fifth byte and real records after it, so an
engine whose `byte-sub` stops at the first NUL cannot read a dirent name at
offset 21 — `File list-dir` then answers a list of empty strings. `byte-ref`
beside it always addressed raw bytes; the two must agree.

```x
(def %sub (%coord (lit str) (lit byte-sub)))
(def %b2s (%coord (lit bytes) (lit ->str)))
(def %bref (%coord (lit str) (lit byte-ref)))
(def s (%b2s (pair 65 (pair 0 (pair 66 ())))))
(%ok (eq? (%bref (%sub s 2 1) 0) 66))
```
---
    *** ERROR: ok

### and the value is still NUL-bounded, so that is addressing and not slicing

covers: str/byte-len bytes/->str

```x
(def %len (%coord (lit str) (lit byte-len)))
(def %b2s (%coord (lit bytes) (lit ->str)))
(%ok (= (%len (%b2s (pair 65 (pair 0 (pair 66 ()))))) 1))
```
---
    *** ERROR: ok

### the tower operators offer their operands' type-ops first

covers: type/make type/make-instance int/+

Generic-operator dispatch (`x_type_op_try`). Every value carries a type tag, so
"is it typed" is not the test — CARRYING A HANDLER is: a type that registers `+`
receives `(handler a b)` and owns the coercion. An engine without the dispatch
adds the operand words and answers a machine integer, which is how
`(+ 2.0 2.0)` once answered a float's bit pattern.

```x
(def %tmake (%coord (lit type) (lit make)))
(def %minst (%coord (lit type) (lit make-instance)))
(def h (%tmake "CONF-OPS"
  (pair (pair (lit ops) (pair (pair (lit +) (fn (_ a b) 42)) ())) ())))
(def i (%minst h 7))
(%ok (= (+ i 1) 42))
```
---
    *** ERROR: ok

### a set interrupt flag raises STOP while a handler is active

covers: set!

Publishing the OS interrupt into `%sigint-flag` is half the contract; the
evaluator must READ it back. The reference checks it at eval_start: flag set and
an error handler active -> raise STOP. No signal is involved here — the flag is
set by hand, exactly as `core/signal.spec.md` does.

The flag's value word is found by PROBING, the way `lib/x/boot/data.x` finds
`%data-off-0`: make an integer with a known value and scan word offsets for it.
That keeps the check layout-agnostic, which decision L1 requires — the offset is
the ENGINE's, not the contract's.

```x
(def %o2p (%coord (lit obj) (lit ->ptr)))
(def %prw (%coord (lit ptr) (lit ref-word)))
(def %psw (%coord (lit ptr) (lit set-word!)))
(def probe 12345)
(def %off (fn (self i) (match ((= (%prw (%o2p probe) i) 12345) i) (#t (self (+ i 1))))))
(def off (%off 0))
(def r (guard (e 99) (%psw (%o2p %sigint-flag) off 1) (+ 1 2)))
(%ok (= r 99))
```
---
    *** ERROR: ok

### and the flag is CLEARED by the raise

covers: obj/->ptr ptr/ref-word ptr/set-word!

Cleared FIRST, so a handler that returns does not re-trip on its next form.

```x
(def %o2p (%coord (lit obj) (lit ->ptr)))
(def %prw (%coord (lit ptr) (lit ref-word)))
(def %psw (%coord (lit ptr) (lit set-word!)))
(def probe 12345)
(def %off (fn (self i) (match ((= (%prw (%o2p probe) i) 12345) i) (#t (self (+ i 1))))))
(def off (%off 0))
(guard (e ()) (%psw (%o2p %sigint-flag) off 1) (+ 1 2))
(%ok (= (%prw (%o2p %sigint-flag) off) 0))
```
---
    *** ERROR: ok

# Engine Laws

Behaviour the language requires of an engine that `x-engine.xon` does not state and
`isa.x` cannot express. Each row here is a law a second implementation broke, found
by running x-lang on it and reading the reference to see why.

They belong with the **guarantees** in [engine-contract.md](engine-contract.md):
a capability says a group of instructions is *reachable*, and every law below was
broken by an engine whose instructions all resolved.

## Why these were invisible

`tools/check/isa.sh` proves every row RESOLVES. It cannot prove a row *does*
anything, and five of the eight laws below were absent mechanisms rather than
wrong answers — an absence answers nil or a raw word, never an error.

The conformance suite missed them for a sharper reason, and it is the rule for
writing the checks:

> **Assert the observable that distinguishes doing it from not doing it.**

`applicative/gc-hooks.spec.md` asks whether a registered hook *survives a
collection*. That is true of a hook nobody ever calls, so it passed 13 of 13
against an engine whose collector never invoked a hook. A hook that COUNTS its
calls tells the two apart in one line.

## The laws

| # | law | distinguishing check | how absence looks |
|---|---|---|---|
| 1 | `eq?` compares the OPERAND WORD, not the type | `(eq? #\A 65)` is `#t` | the printer's escape table misses every arm |
| 2 | a predicate answers the base's TRUE/FALSE objects | `(same? (eq? 1 1) #t)` | invisible to branching; only printing shows it |
| 3 | the tower operators offer their operands' type-ops first | a type registering `+` receives it | tower arithmetic answers raw words |
| 4 | the collector INVOKES registered hooks, marks before sweeping | a counting hook reaches N after N collections | nothing; the survival spec still passes |
| 5 | `apply` is a TAIL call | 50k frames of `(let ((m (- n 1))) (self m))` | stack overflow, whole batch dies |
| 6 | a set interrupt flag raises `STOP` under a handler | set `%sigint-flag` inside a `guard` | the flag is written and never read |
| 7 | a pointer into the engine's heap crosses the foreign door as a REAL address | `(Proc run! (list "/bin/sh" "-c" "exit 3"))` is `3` | a constant status, whatever the child did |
| 8 | `str byte-sub` ADDRESSES bytes; it does not slice the NUL-bounded value | a byte past an embedded NUL | every dirent name reads empty |

### 1 — `eq?` compares the operand word

`x_prim_eq` is one expression: `a == b || (!isnil(a) && !isnil(b) && x_intval(a)
== x_intval(b))`. It reads slot 0 of both operands without asking whether they
are the same kind, so a CHARACTER equals the INTEGER of its code.

`lib/x/boot/printer.x` depends on it: `%print-str-esc?` and
`%print-str-esc-byte` are handed `(str byte-ref s i)` — a character — and match
it against 34, 92, 10, 9, 13. Type-gating the comparison made every arm miss, so
a quote printed unescaped, a newline came out `\x0a`, and a carriage return lost
its backslash.

It follows that **a sentinel must not carry a small integer in slot 0**:
`x_token_eof_prim`'s value word is its own address, or `%token-eof` would be
`eq?` to `0` and `lib/x/repl/loop.x` would read a literal `0` as end of input.

### 2 — predicates answer `#t` and `#f`

Never a symbol, never nil. `x_prim_eq`, `x_prim_same`, `x_prim_lt` and `type`'s
predicates all return `x_firstobj(x_eval_field_true(p_base))` or the false field
— base fields a child base inherits (`x-prim/base.c`).

Both a symbol and nil branch correctly, so nothing that merely *tests* a
predicate can see the difference. What sees it is printing one.

### 3 — generic-operator dispatch

`x_type_op_try`. Every value carries a type tag, ints included, so "is it typed"
is not the test — CARRYING A HANDLER is. If either operand's type registers a
handler for the operator, it is called as `(handler a b)` and owns the coercion.

When both sides carry one: same type takes `a`'s; otherwise the side whose type
declares a conversion FROM the other absorbs it; neither declaring the other
falls through. Offered by `+ - * / %` and `<` `=`, and NOT by the bitwise family
(ruling #52: bitwise has no tower semantics).

### 4 — the collector invokes the hooks

`x_heap_mark_phase` opens with `x_heap_run_hooks(mark_hooks)`;
`x_heap_sweep_phase` opens with the free hooks. The engine IS the consuming
layer.

**Mark hooks run BEFORE any marking**, and that ordering was paid for with a
use-after-free: everything a hook allocates is born unmarked, so hooks running
after the mark passes let an allocation that escaped into reachable state be
freed by the same sweep.

### 5 — `apply` is a tail call

`x_prim_apply` binds the parameters and returns `x_eval_body_tco`. This is not
an optimisation detail: `let` is BUILT on apply — `lib/x/core/control.x` expands
`(let ...)` to `(apply (eval (fn ...)) vals)` — so an apply that settles makes
every `let` in tail position grow the host stack.

### 6 — the interrupt flag raises `STOP`

Publishing an OS interrupt into the flag is half the contract. `x_eval_start`
reads it every iteration: if set AND an error handler is active, it clears the
flag and raises `STOP`. Clearing first so a handler that returns does not
re-trip; requiring a handler because an uncatchable raise ends the run instead of
interrupting the computation.

x-lang sets the flag directly to test this — no signal involved.

### 7 — pointers cross the foreign door as real addresses

The reference has no equivalent law because its heap IS process memory. An engine
whose heap is its own array must resolve an address inside it before it crosses
the door, exactly as it already does for a string's bytes.

`Sys wait` is the case that finds it: x-lang hands `waitpid` a four-byte region
as `(%str->ptr s)` and reads the status back.

### 8 — `byte-sub` addresses bytes

A buffer handed to a syscall is binary. `(str make 4096)` filled by
`getdirentries64` has a NUL in its fifth byte and real records after it, so a
`byte-sub` that stops at the NUL cannot read a dirent name at offset 21.
`byte-ref` beside it addresses raw bytes; the two must agree.

## Open contract question

The compiled-C lane is an **undeclared assumption**, not a law. `x/tool/compile.x`
builds against the engine's own C headers (`-Iengine/include`), and nothing in
`x-engine.xon` says an engine can host a compiled prim — the two engines'
`provides` lists differ only by `instr/cov`/`instr/profile` against
`meta/identity`/`meta/platform`.

Today `boot/tower-compiled.x` probes for the header directories and keeps its
interpreted analysers when they are absent. A declared capability would say it
properly, and would turn `ext/jit-*.spec.md` and `ext/asm.*.spec.md` from
failures into *not applicable* for an engine that never claimed the lane.

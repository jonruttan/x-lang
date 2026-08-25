# Engine Laws

Behaviour the language requires of an engine that `x-engine.xon` does not
state and `isa.x` cannot express. A capability in
[engine-contract.md](engine-contract.md) says a group of instructions is
reachable; a law says what an instruction must do.

A check for a law asserts the observable that distinguishes doing it from
not doing it — a hook that counts its calls, not a hook that survives a
collection.

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
| 9 | evaluation and application are TYPE HANDLERS | replacing a made type's `eval` handler changes what `(eval i)` answers | registration writes a row the evaluator never reads |

### 1 — `eq?` compares the operand word

`x_prim_eq` is one expression: `a == b || (!isnil(a) && !isnil(b) && x_intval(a)
== x_intval(b))`. It reads slot 0 of both operands without asking their kinds,
so a CHARACTER equals the INTEGER of its code. `lib/x/boot/printer.x` depends
on it: `%print-str-esc?` and `%print-str-esc-byte` match `(str byte-ref s i)` —
a character — against 34, 92, 10, 9, 13.

A sentinel must not carry a small integer in slot 0. `x_token_eof_prim`'s value
word is its own address; `%token-eof` is never `eq?` to a byte.

### 2 — predicates answer `#t` and `#f`

Never a symbol, never nil. `x_prim_eq`, `x_prim_same`, `x_prim_lt` and `type`'s
predicates return the base's true and false fields, which a child base inherits
(`x-prim/base.c`).

### 3 — generic-operator dispatch

`x_type_op_try`: if either operand's type registers a handler for the operator,
the handler is called as `(handler a b)` and owns the coercion. When both sides
carry one, the same type takes `a`'s; otherwise the side whose type declares a
conversion FROM the other absorbs it; with neither declaring, the operator falls
through. Offered by `+ - * / %`, `<` and `=`, and not by the bitwise family.

### 4 — the collector invokes the hooks

`x_heap_mark_phase` opens with `x_heap_run_hooks(mark_hooks)`;
`x_heap_sweep_phase` opens with the free hooks. Mark hooks run BEFORE any
marking: a hook's allocations are born unmarked, and a hook that runs after the
mark passes can have an allocation that escaped into reachable state freed by
the same sweep.

### 5 — `apply` is a tail call

`x_prim_apply` binds the parameters and returns `x_eval_body_tco`.
`lib/x/core/control.x` expands `(let ...)` to `(apply (eval (fn ...)) vals)`;
an apply that settles grows the host stack under every `let` in tail position.

### 6 — the interrupt flag raises `STOP`

`x_eval_start` reads the flag every iteration. Set, with an error handler
active, it clears the flag and raises `STOP`; it clears before raising, and it
raises only under an active handler. x-lang sets `%sigint-flag` directly to
test it.

### 7 — pointers cross the foreign door as real addresses

An engine whose heap is its own array resolves an address inside it to a real
one before it crosses the foreign door, as it does for a string's bytes.
`Sys wait` hands `waitpid` a four-byte region as `(%str->ptr s)` and reads the
status back.

### 8 — `byte-sub` addresses bytes

A buffer handed to a syscall is binary: `(str make 4096)` filled by
`getdirentries64` holds a NUL in its fifth byte and records after it.
`byte-sub` addresses raw bytes, as `byte-ref` does.

### 9 — evaluation and application are type handlers

A `type make` type with an `eval` handler decides what evaluating its
instances means; with a `call` handler its instances are callable; with
neither, an instance is itself and a form headed by one is data. Checked by
`tests/x/conformance/core/handlers.spec.md`.

## Open contract question

The compiled-C lane is undeclared. `x/tool/compile.x` builds against the
engine's own headers (`-Iengine/include`); nothing in `x-engine.xon` says an
engine hosts a compiled prim. `boot/tower-compiled.x` probes for the header
directories and keeps its interpreted analysers when they are absent;
`ext/jit-*.spec.md` and `ext/asm.*.spec.md` assume the lane.

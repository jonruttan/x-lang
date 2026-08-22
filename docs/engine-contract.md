# The Engine Contract

x-lang is a language, not an implementation. `x-engine-c` is one engine; another
may be written in any language that can meet the terms below. This document is
those terms — what an engine must provide, what it must promise, what it merely
reports, and how the language finds out.

It is written for someone building a second engine. Everything here is checked by
something in the tree; where a claim is not checked, it says so.

## The three kinds of row

An engine describes itself in `x-engine.xon`. Three kinds of statement live there,
and they are compared three different ways. Collapsing them is the mistake the
vocabulary exists to prevent.

| kind | means | compared by |
|---|---|---|
| **capability** | a group of instructions is reachable | superset — a richer engine is never refused |
| **guarantee** | a behaviour the engine promises, usually by *not* doing something | must-hold |
| **parameter** | a value the engine reports (word size, byte order, arch) | never a requirement; checked where consumed |

A parameter must never appear in a requirements list. `word-size = 8` as a global
requirement would lock out the 32-bit Pi, which is a supported target — and it
would be false besides, since the layout descriptors are expressed in words and the
library sizes a word at boot. Where a specific module genuinely does depend on a
value, it carries a row in `tools/contract/constraints.x` and a marker at the code.

The closed vocabulary is `tools/contract/features.x`. The language owns it: an
engine that defined the terms would be choosing the ones it is judged by.

## Capabilities

Groups partition the engine's instruction manifest (`tools/contract/isa.x`).
`tools/check/engine-contract.sh` proves that partition **total and disjoint**, so a
new instruction cannot appear unclassified.

A capability means *the coordinates in that group resolve* — `(prim-ref 'ns 'method)`
finds something callable, or the bare name is bound. It does **not** mean
"implemented natively". `lib/x/boot/reflect.x` already replaces engine primitives
with x-level ones under the same catalog names. The contract is the coordinate, not
the language it is written in.

**A tag is not a group.** The `ffi` tag carries eleven instructions that split three
ways, and treating it as one would make `dlopen` mandatory for every engine
including a sandboxed one:

- `reflect/ptr-casts` — object↔pointer↔integer materialization. **Mandatory.**
  The boot reads object header words through these.
- `isa/ffi-call` — `dlopen`, `dlsym`, calling through a pointer. Optional.
- `isa/syscall` — the raw kernel door. Optional.

`lib/x/boot` reaches all six casts and reaches the foreign door zero times.

## Guarantees

Behaviours no manifest can show, because they are things the engine does *not* do.
The library's correctness rests on them anyway.

- `gc/explicit-only` — allocation never collects; only an explicit call does.
- `gc/non-moving` — a live object's address is stable for its lifetime.
- `eval/tco` — proper tail calls, unbounded.
- `str/nul-terminated` — a string value is a C string; bytes past the NUL are
  unobservable.
- `int/ptr-same-width` — the fixnum and the pointer are the same width.

### What the engine requires of *you*

Guarantees run one way — the engine promising, the library relying. There is one
obligation that runs the other way, and it belongs here because nothing else in
the vocabulary carries it:

**Operatives are banned inside the tokenizer's read.** Code reached from a reader
callback must use the primitive `if`, never an op (`docs/syntax.md` states this as
a ruling, and `lib/x/reader/lit-reader.x` is written to it).

This was previously mis-declared as a *guarantee* named `tok/callback-no-alloc`,
on the belief that callbacks must not allocate. That belief is obsolete —
`lit-reader.x` records that re-entering the tokenizer from a reader handler is safe
*because* collection is explicit-only — and the real constraint is about operatives
rather than allocation. It is a requirement on callback authors, so it is written
here rather than declared as something an engine provides.

The first two guarantees are not academic. Six sites in the library hold a raw pointer as an
integer across an allocating expression on the collection promise alone. An engine
that collected during allocation would break all six with no error and no crash at
the point of damage.

`eval/tco` is semantic, not a performance note: the library recurses in tail
position throughout and binds a tail `def` globally *because* of it. An engine
without tail calls does not run slowly, it overflows the stack in ordinary code.

## Profiles

Four tiers, so a partial engine has a target instead of an all-or-nothing wall.
Each includes the one before it.

| profile | adds | boots |
|---|---|---|
| `core` | the spine, allocation, machine ops, raw memory, types, the reader, byte I/O, reflection | the language |
| `gc` | collection | the REPL loop, the GC module |
| `posix` | OS facilities, the syscall door, the foreign door | File, Proc, sockets |
| `full` | coverage and profiling instrumentation | the tooling |

The interesting boundary is `core|gc`: an engine with **no foreign door, no
syscalls and no collector** still boots x-lang. Of roughly 150 files in `lib/` and
`apps/`, eighteen need anything above `core`. That is the shape of the sandbox
dialect, and the first target worth aiming a new engine at.

The tiers are what the library *is*, not a tidy diagram. `posix` cannot be
separated from the foreign door because `lib/x/sys/posix.x` fetches `dlopen`
alongside `syscall`.

## The invocation protocol

How the wrapper drives the engine. This was assumed everywhere and written down
nowhere until this document.

The engine owes exactly three things:

1. **It reads its program from standard input** and evaluates as it reads. The
   wrapper concatenates the library entry, any pinned forms, and the user's file
   onto one pipe.
2. **It binds every argument-vector element** as a list named `args`.
3. **It writes diagnostics to standard error**, prefixed `*** ERROR: `.

That is all. In particular the engine **parses no flags**. `--batch`, `--quiet`
and `--no-color` are read by x-lang code (`lib/x/repl/banner.x`,
`lib/x/tool/contract.x`), and the reclaiming of terminal input from file
descriptor 3 is `lib/x/repl/loop.x` calling `dup2` through the syscall door. Those
are conventions between the wrapper and the library; an engine that binds `args`
and offers the syscall door supports them without knowing they exist.

Two forms may be emitted ahead of the program as data, never evaluated by the
shell: the install root, and a project's pin manifest path. Both are consumed by
library code after boot.

A bare engine has no printer — `display` and `write` are x-lang — and does not echo
results either. With no library loaded, the only way a program can be observed is
by raising an error. Both bare suites rely on this.

## What an engine ships

    tools/contract/isa.x            the instruction manifest, with a tag per row
    tools/contract/obj-layout.x     object header layout, in WORDS
    tools/contract/base-paths.x     interpreter state as first/rest walks
    tools/contract/base-layout.x    the base spine descriptor
    tools/contract/claims.x         the guarantees it asserts
    x-engine.xon                    generated self-description

The layout descriptors travel with the engine because the library is reflective:
it reads object header words directly. Every engine ships its own, and the library
includes the booting engine's. This makes word-addressability a permanent
requirement — an engine must expose object↔pointer casts and word load/store over
a flat arena — but it does **not** make any particular width a requirement.

`x-engine.xon` is generated by x-lang's `tools/contract/gen-engine-xon.sh` run
against the engine directory. Capabilities, profiles and digests are derived from
the engine's own files; guarantees are copied from `claims.x`. Parameters are
absent by design: word size and architecture are facts of a *build*, not of a
source tree, and are stamped beside the binary at install time.

## How an engine is checked

Three suites, asking three different questions.

**The contract gate** (`make check-engine-contract`) reads only files. It holds the
capability partition against the instruction manifest, keeps profiles closed,
refuses a parameter in a requirements list, re-derives what the library needs from
its own call sites, and answers the resolver's question: does this engine provide
what x-lang requires?

**Conformance** (`make conformance`) asks *is this a correct x-lang evaluator?* It
is the language's definition of correct, it loads nothing, and it runs against any
engine via `X_BIN`. It lives here rather than in an engine because an implementation
that owned it would become the arbiter every other implementation is judged
against.

**Compliance** (`make check-compliance`) asks *does this engine do what it claims?*
Every check is generated from a row of the engine's own `x-engine.xon`, so the
suite cannot drift from the declaration it audits. It matters because the contract
gate compares declarations as text: an engine that over-declares passes it, is
chosen, and fails in the field — loudly for a capability, silently for a guarantee.

Under-declaring is harmless; an engine is simply treated as less capable than it
is. So compliance only ever tests in the over-declaring direction.

Coverage of the conformance suite is a ratchet, not a target: it may grow freely,
and a row that loses coverage fails. Rows with no case carry their reason in prose
beside the subject, because "no case exists" and "no case should exist" are
indistinguishable in a report.

## Writing a second engine

The order that gets you running soonest:

1. Meet the `core` profile, and ship the four contract files describing your own
   layout. `tools/contract/features.x` lists what `core` names.
2. Write `claims.x` for the guarantees you actually make. Claim less rather than
   more: under-declaring costs you capability, over-declaring costs correctness.
3. Generate `x-engine.xon` with x-lang's generator.
4. Run conformance and compliance against your binary. Both take `X_BIN`.
5. Add `gc`, then `posix`, as you want the library tiers that need them.

The bar for step 1 is lower than it looks — no collector, no syscalls, no foreign
door — and higher in one specific way: the reflective library needs word-addressed
objects, so an arena with raw word access is not optional.

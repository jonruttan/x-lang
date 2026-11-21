# Design Rulings

Decisions about where a change belongs. Each one settles a question that
recurs in review, so a pull request can be measured against it before it is
written and a review can cite it by number.

A ruling is not a gate. Where a gate can hold one, the gate is named; the
rest are held in review. [Engine Laws](engine-laws.md) states what an engine
must do; [Code quality criteria](code-quality.md) states what counts as a
defect in `.x` source; this page states which layer answers a need.

## The rulings

| # | ruling | a change that breaks it |
|---|---|---|
| 1 | the engine grows doors, not behaviour | a branch, flag or case added to the C |
| 2 | no primitive is added for speed | a native hash, a raw accessor beside a reflective one |
| 3 | a derived form's cost is the library's | a derived form moved into the engine |
| 4 | the engine does not guard and does not address the user | an argument check or a message in a primitive |
| 5 | engine state lives in the base | a mutable static; a routine that is not `(base, args)` |
| 6 | one mechanism, as many doors as callers | a second evaluator, resolver or walker |
| 7 | a defect is fixed in the structure that allows it | code that corrects the consequence on every path |
| 8 | a tool asks the language | awk or sed deriving what x source means |
| 9 | slow platform code is fixed where it lives | a bundle rewritten around a slow library path |
| 10 | generic machinery comes from `lib/x` | a bundle's own option parser, lexer or float routine |
| 11 | a dialect is what is loaded | a module moved down the ladder |
| 12 | the word width is the platform's | a constant or shift that assumes 64 bits |
| 13 | no runtime requires a C compiler | a compiled lane with no interpreted fallback |
| 14 | capabilities are written in x | a vendored or linked third-party library |
| 15 | I/O reads on demand | an `open` that reads the whole source |
| 16 | a loop is a tail call | a larger stack offered for deep recursion |

## The engine

### 1 — the engine grows doors, not behaviour

The engine is a scriptable interpreter, kept small on purpose. Its dispatch
routines (evaluation, application, environment lookup, token reading) are
called through slots of the base, listed in the engine's
`tools/contract/base-slots.x`, and `Base slot!` replaces one with a routine
compiled in x-lang.

A need that seems to call for different engine behaviour is first a question
of which slot routine decides that behaviour. An engine change is weighed by
what it opens: a slot, a door or a contract row that lets x-lang reach
something it could not is the kind the engine takes. A change that adds a
case, a flag meaning or a behaviour to the C is not, at any size.

### 2 — no primitive is added for speed

x is reflective: what a static language fixes at build time is made at run
time and is reachable from the language. A cost in the library is answered
from the primitives that exist, by reading what they accept and building the
fast path from them, or by compiling the routine through the existing lanes.
Hashing, slot access and object lookup are library code.

### 3 — a derived form's cost is the library's

`do`, `let`, `and`, `or` and their kin are built from the primitive set. A
slow derived form gets a leaner definition in x-lang. The engine does not
absorb one to make it free; that moves library policy into C.

### 4 — the engine does not guard and does not address the user

The engine reports state; the interface decides what to do with it. A
primitive does not check what a program hands it: guards are library work,
compiled where their cost matters. The engine words and formats nothing a
user reads, since it does not know the user's language or the syntax being
read. A reader that stops mid-token reports that; the interactive session
decides to ask for more input.

The same line covers content. The engine reserves an object's metadata
words and recovers the allocation; what the words hold is the library's.

### 5 — engine state lives in the base

The engine declares no mutable static or global. State is a base slot or a
field reached from the base, so two bases in one process share nothing by
accident. Every routine declared in an engine header or exported to compiled
code takes `(base, args)`, with `args` an argument list or an argument run,
and returns an object.

## The platform

### 6 — one mechanism, as many doors as callers

A caller with a new need gets a door onto the mechanism that exists, or that
mechanism's contract is widened. It does not get its own copy. This holds for
evaluation (one top-level bracket, entered by the loader and by `eval!`), for
body walking, and for resolution: `bundle.xon` declares a dependency, the pin
acquires it, and `x.sh` resolves it against the installed langs with the
version held by equality. A tool that probes for a sibling directory or reads
its own environment variable is a second resolver, and it drops the version
check the first one makes.

### 7 — a defect is fixed in the structure that allows it

A fix starts from what about the structure lets the defect happen: where an
object lives, which chain it is on, who owns it. Code that compensates has to
be right on every path and costs on every run. A structural fix leaves the
existing machinery to do its job.

### 8 — a tool asks the language

The loader is the one implementation of load semantics. A tool that needs a
semantic fact about x source (which module a form belongs to, what a name is
bound to, what a file includes) loads the source and inspects the
environments and registry the language keeps. Shell, awk and sed stand in for
tools not yet written in x; a stand-in records what the loader does and never
decides what the loader has not defined.

### 9 — slow platform code is fixed where it lives

A slow library path is a defect in the library. It is fixed at its source
and reported with the numbers. It is not a reason to avoid the facility: a
module stays scoped, a caller keeps using the door. A speed request made of
a bundle is a benchmark of the language, and the bundle is not rewritten to
use a narrower part of it.

### 10 — generic machinery comes from `lib/x`

A bundle keeps its own language's layer: argument conversion, error rules,
messages. What is generic comes from the platform:

- the command line from `Opts` (`lib/x/sys/opts.x`);
- lexing and reading from `Lexer` (`lib/x/reader/lexer.x`) and a tokenizer
  base with registered types;
- floats and libm functions from `lib/x/num/float.x`, which stores the IEEE
  double bits and binds libm itself.

Where `lib/x` has no class for a generic need, the library is proposed and
built in x-lang, and the bundle uses it. [Code quality criteria §1.5](code-quality.md)
is the same ruling at the scale of one function.

### 11 — a dialect is what is loaded

Helium, xenon and radon are a ladder of what has been loaded, not readers
with separate powers ([Dialects](dialects.md)). A helium program that wants a
module imports it. A module is not moved down the ladder so that a lower
dialect reads more, and a dialect is not described as lacking a capability.

### 12 — the word width is the platform's

The engine takes the platform's word, at any width. A narrower target is a
build leg. Library code takes masks and shifts from the word size and writes
a constant past 2^31 in hex, since a decimal literal wider than the word
reads as a Bigint once `x/num/bigint` is loaded.

### 13 — no runtime requires a C compiler

A compiled path is a ladder: the built-in assembler first, a hosted C
compiler where one is present, the interpreted definitions last. Each rung
that refuses drops to the next (`lib/x/boot/tower-compiled.x`). An install
with no toolchain runs everything.

### 14 — capabilities are written in x

A capability the platform lacks is written in x and compiled. A host library
is bound through the foreign doors only where the host already provides it
(libc, libm, SDL3 for the graphical front end); none is vendored, linked in
or shipped with an image.

### 15 — I/O reads on demand

Opening a file or stream opens a descriptor. Reads pull what is asked for. A
source with no end (a pipe, a device) is the test.

### 16 — a loop is a tail call

Tail calls run in constant stack ([Specification](spec.md)). The depth of
non-tail recursion is bounded by the C stack, and a larger stack is not
offered as a remedy.

## Related

- [Bundle Checklist](bundle-checklist.md) G1: collection is the
  application's; x collects only when asked.
- [The Engine Contract](engine-contract.md): what an engine must provide,
  and how a second engine is checked against the reference engine.
- [Scaling to Many Langs](lang-scale.md): the rulings on how bundles are
  pinned, checked and registered.

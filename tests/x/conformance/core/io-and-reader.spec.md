# Conformance: byte output, and what the reader family cannot be asked here

The I/O boundary and the tokenizer's buffers. One instruction here has a case; the
rest are deferred with their reasons, because the harness itself is the obstacle
and pretending otherwise would leave four silent gaps in the coverage report.

### write-str emits bytes to stdout and answers nil

covers: io/write-str

Both halves are asserted at once. The written bytes land on stdout ahead of the
assertion's own `*** ERROR:` line and share it, so the expected value below proves
the side effect happened AND that the primitive answers nil rather than a count --
a distinction an engine could easily get wrong in either direction, since nothing
in the library reads the return.

```scheme
(def %w (%coord (lit io) (lit write-str)))
(%ok (eq? (%w "zz") ()))
```
---
    zz*** ERROR: ok

## io/read, io/read-char and io/repl-read -- the harness IS the obstacle

These read from stdin, and in this harness stdin is the PROGRAM: the runner pipes
the prelude and the case source into the engine on the same descriptor. A case
that read a character would consume its own remaining source, and one that read to
EOF would consume the rest of the run. That is not a property of the engine and no
assertion here would be about it.

Exercising them needs a harness that separates program text from input -- the
wrapper's fd-3 arrangement, which exists exactly for this and is a capability in
its own right (`io/fd3-stdin`). Reaching them from x-lang's suite means teaching
this runner that trick; until then the honest record is that they are undefined
here, not that they pass.

## buf/* and tok/* -- the tokenizer's own machinery

`buf/make`, `append`, `read`, `read-text`, `reset`, `retain`, `last-char`, `tok`
and the two `tok/*` entries are the reader's inner loop, not a general-purpose
byte API. A buffer carries a read cursor, a retained-token region, and flags that
decide whether exhaustion answers EOF or EXTENDS FROM STDIN -- and getting the
flag wrong makes the harness hang rather than fail. Probing them bare crashed the
engine outright on the obvious call shapes.

They also run under a constraint nothing else here does: code reached inside the
token read must not allocate, which is why `lib/x/reader/lit-reader.x` is written
the way it is. A conformance case that called them from ordinary x-lang would be
testing them outside the conditions they exist under.

Their observable contract is the READER's -- what the tokenizer produces for given
source text -- and that is a language-level property the library's own dialect and
reader specs already cover. Defining it at the instruction level needs the reader
family modelled first; this file names the gap so it stays a decision.

## obj/make and obj/make-callable -- construction, deferred

Allocating a bare object and turning a value into a callable are the two
constructors x-lang's own object model is built from, but their arguments are
layout-dependent (slot counts, header flags) and the descriptors that give those
numbers meaning are the engine's `obj-layout.x`. A case written against the C
build's numbers would be asserting one engine's layout as the contract, which is
precisely what decision L1 exists to avoid. They belong with a layout-aware
tranche that reads the descriptors first.

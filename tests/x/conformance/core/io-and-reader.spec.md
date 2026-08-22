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
wrapper's fd-3 arrangement, which exists exactly for this. That arrangement is
NOT an engine capability, incidentally: `lib/x/repl/loop.x` performs the `dup2`
itself through the syscall door, so an engine supports it by having that door and
nothing more. Reaching these from x-lang's suite means teaching this runner the
same trick; until then the honest record is that they are undefined here, not
that they pass.

## the remaining buf/* rows -- the tokenizer's own marks

These nine rows are one protocol, not nine instructions, and the reason they stay
undefined is now a specific gap rather than a shrug. What follows is the model,
recovered from the engine's C and from `lib/x/num/bigint.x`, which registers a
real reader type.

**The protocol.**

1. `(base make-tok)` makes a base with NO types registered -- deliberately bare,
   "for custom tokenizer type registration on an isolated base".
2. `(base make-type TOKBASE "NAME" handlers)` registers a reader type on it. The
   handler alist carries `analyse` and `read`.
3. `analyse` is `(fn (_ buffer score chr))` and it is a STATE MACHINE whose states
   are functions: it returns the analyser for the next character to continue,
   `()` to reject, or records a match through the score object to accept.
   `lib/x/num/bigint.x` is the worked example -- `%big-analyse` dispatches on the
   first character, `%big-digits` loops while digits arrive, and on a non-digit it
   pushes the character back and scores.
4. `(tok read-str TOKBASE text)` drives every registered type's analyser over the
   text, scores them against each other, and calls the winner's `read`.

So the buffer is never the subject. It is the tape the analysers run over, and
its marks -- write, read, and the retain mark -- are moved by the tokenizer in an
order only the tokenizer knows.

**Why driving it by hand pins garbage.** Make a read-only buffer over a
`(str make 32)` region, append two characters, read twice: `tok` answers length 2
and `last-char` answers the second character, which looks like working semantics.
The same `read` returns a character that is neither appended one, nor NUL, nor
nil. `(str make N)` is not promised to return zeroed memory, so the constructor's
write mark lands past whatever bytes were there and the cursor reads them. Two
cases were written green on that before the third disagreed.

**The protocol itself is now defined**, in `core/reader.spec.md`: the two scoring
helpers were rebuilt from primitives (a buffer's marks are two integer cells
reachable through `obj ->ptr` + `ptr ref-word`), and the missing precondition was
not a precondition at all -- a token must be DELIMITED, because the accept branch
runs only when a character arrives that the state rejects. `"42"` scores nothing;
`"42 "` scores. That covers `base/make-tok`, `base/make-type`, `tok/read-str` and
`buf/read`.

**What stays undefined is the rest of the buffer surface** -- `buf/make`,
`append`, `read-text`, `reset`, `retain`, `last-char`, `tok`, and `tok/read`.
The reader case does not require them individually, and the standard a case has
to meet is that breaking the row breaks the case. Claiming them because the
tokenizer touches them somewhere would be the hollow coverage this suite exists
to avoid: it moves the number without defining behaviour.

Defining them needs the tokenizer's mark discipline modelled the way the reader
protocol now is -- what `retain` means between tokens, what `tok` returns and
when it is valid -- not another round of driving them by hand.

## obj/make and obj/make-callable -- construction, deferred

Allocating a bare object and turning a value into a callable are the two
constructors x-lang's own object model is built from, but their arguments are
layout-dependent (slot counts, header flags) and the descriptors that give those
numbers meaning are the engine's `obj-layout.x`. A case written against the C
build's numbers would be asserting one engine's layout as the contract, which is
precisely what decision L1 exists to avoid. They belong with a layout-aware
tranche that reads the descriptors first.

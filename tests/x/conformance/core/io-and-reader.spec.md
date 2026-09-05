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

```x
(def %w (%coord (lit io) (lit write-str)))
(%ok (eq? (%w "zz") ()))
```
---
    zz*** ERROR: ok

## io/read, io/read-char, io/repl-read and tok/read -- the program IS the input

These read from the base's input, and in a bare harness the base's input is the
program: the runner pipes the prelude and the case source into the engine on
stdin, so a case that read a character would consume its own remaining source.

Three ways round it were tried, and each failed differently. Together the failures
say the obstacle is not the harness.

**Input after the program.** The read-eval loop reads a form, evaluates it, reads
the next. Data placed after the last form is not reachable by the case: the loop
gets there first, and the tokenizer's read-ahead puts even the timing outside the
case's control.

**Filling a sandbox base's buffer.** `(base make)` sets up a read buffer, the
layout contract exposes it (`buffer base f r f f r r r r r f`), and the walk to it
works. Appending to it does not -- `buf append` on a live base's buffer crashes.
That buffer belongs to a running read-eval loop and is not an arbitrary sink. A
sandbox base also does not bind `read-char` under its flat name, so the read would
have needed another door regardless.

**The wrapper's fd-3 arrangement.** `x.sh` saves the terminal on fd 3 and the REPL
reclaims it with `dup2 3 0` (`lib/x/repl/loop.x`). Reproduced by hand the redirect
works, and then the ENGINE'S OWN LOOP consumes the input: after `dup2` to a file
holding `abc`, the next thing to read a form was the loop, which answered
`Unbound SYMBOL 'abc`. `read-char` pulls from the base's buffer and that buffer
refills from fd 0, so moving fd 0 hands the input to the loop rather than to the
case.

**What that adds up to.** Reading and evaluating share one stream by construction,
and nothing in the ISA offers a second: there is no primitive that reads from a
descriptor or a string of the caller's choosing. These rows are therefore not
testable bare without an engine-side affordance that does not exist today -- which
makes this a question about the contract rather than about the suite, and the
honest place for it is here rather than in a case that pretends otherwise.

The library exercises them through the REPL, where the loop reclaiming its own
input is the behaviour under test rather than an obstacle to it.

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

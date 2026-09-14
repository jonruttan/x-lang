# The interactive session

`sh x.sh` with a terminal gives you a line editor. Not a wrapper around one —
`rlwrap` was the documented answer here until this existed, and the advice is
gone because it is no longer needed. Arrow keys, the readline chords, history
that outlives the session, Tab completion over every documented name, and
colour applied to what you type as you type it.

Nothing has to be enabled. With no terminal — a pipe, `-f`, `-c`, a spec
harness — none of it loads and the session reads exactly as it always did.

```sh
sh x.sh -l xe
```

## Keys

| Key | Does |
|---|---|
| Left / Right, ctrl-b / ctrl-f | one character |
| ctrl-Left / ctrl-Right, meta-b / meta-f | one word |
| Home / End, ctrl-a / ctrl-e | ends of the line |
| Backspace, Delete | delete backwards, delete forwards |
| ctrl-w, meta-Backspace | kill the word before the cursor |
| ctrl-k, ctrl-u | kill to the end, kill to the start |
| ctrl-y | yank back what was last killed |
| Up / Down, ctrl-p / ctrl-n | history |
| Tab | complete |
| ctrl-l | clear the screen |
| ctrl-c | abandon the line, keep the session |
| ctrl-d | end the session (on an empty line); delete forwards otherwise |
| Enter | evaluate |

Motion is by character, not by byte, so an accented letter or an emoji moves
one step and never gets split in half.

## Multi-line forms

A form that is not finished when you press Enter continues on the next line,
under a `..` prompt:

```
> (def sq
..   (fn (_ n) (* n n)))
#<fn>
> (sq 7)
49
```

The reader decides when it is finished, not a paren count in the editor —
which is the same decision the evaluator makes, so a string containing a
bracket cannot confuse it. ctrl-c abandons the whole entry.

A single line may also hold several forms, and each prints its own result.

## History

History is kept in `$XDG_STATE_HOME/x/history`, or `~/.local/state/x/history`
when that is unset. It is appended one line at a time rather than written out
at exit, so a session that is killed or crashes still keeps what it typed, and
two sessions running at once interleave instead of one overwriting the other.

Each edited line is one entry, so the two lines of a multi-line definition
are recalled separately — and an entry can never contain a newline, which is
what keeps the one-line-per-entry file format honest. Blank lines are not
recorded, and neither is a line identical to the one before it.

Set `X_HISTORY` to keep it somewhere else. Set `X_HISTORY` to the empty string
to turn persistence off entirely — what you want in a session that will handle
a credential.

```sh
X_HISTORY= sh x.sh          # this session leaves no trace on disk
```

## Completion

Tab completes against the documentation registry — the same names
`(apropos "...")` searches — so anything a module documents completes as soon
as that module is loaded, with no separate list to keep in step.

Because methods dispatch subject-last, completion reads the form you are
inside:

```
> (Str8 sta<TAB>
> (Str8 starts?
```

`Str8` at the head of the open form is put back on the front of `sta` before
the search, because `Str8/starts?` is what the registry actually calls it. A
Tab that could mean several things extends as far as they agree; a second Tab
lists them.

## Colour

What you type is coloured as you type it, using the same palette printed
results use: constructs bold magenta, numbers yellow, strings green,
characters magenta, `#t`/`#f` bold red, class names bold cyan, `%`-private
names dim, comments dim.

**The reader decides the colour.** An atom's class is settled by handing its
bytes to the base and taking the type of the value that comes back, so
`3.14`, `1/2`, `0xff` and `#\newline` are coloured correctly without the
painter knowing any of their syntax — and a lang that registers a new literal
form colours correctly the moment it loads. The colour and the evaluator
cannot disagree, because there is only one opinion.

Colour follows the same switches everything else does: `NO_COLOR`,
`TERM=dumb`, or `--no-color` turn it off, and with it off the painter is an
identity function and costs nothing.

## Long lines

A line longer than the terminal scrolls sideways within its row rather than
wrapping onto more rows. That keeps the cursor arithmetic to one dimension —
nothing to get wrong when the terminal is resized mid-line — and it bounds the
cost of a redraw by the width of the terminal rather than the length of the
line.

## When it is not there

The editor needs a terminal on standard input and a build whose `termios`
calls resolve. Without either, `repl` is left alone and the C reader's loop
runs, exactly as before. Nothing announces this; the session simply behaves
the way it did when `rlwrap` was the advice.

## The pieces

Four modules, each usable on its own, and only one of them touches a
descriptor:

| Module | Holds |
|---|---|
| [`x/repl/edit`](../lib/x/repl/edit.x) | the buffer, the cursor, the kill ring, the history walk — no terminal at all |
| [`x/repl/term`](../lib/x/repl/term.x) | raw mode, the window geometry, and turning bytes into keys |
| [`x/repl/paint`](../lib/x/repl/paint.x) | colouring a line that may still be half-typed |
| [`x/repl/line`](../lib/x/repl/line.x) | the loop that joins them, plus history and completion |

The split is what makes the thing testable. `Edit` is pure and `Term key`
takes a byte-reading function rather than a descriptor, so nearly all of the
behaviour is checked by the ordinary spec harness with no pty anywhere:
`tests/x/specs/lib/repl-edit.spec.md`, `repl-term.spec.md`,
`repl-paint.spec.md`.

## Replacing it

`repl` is a plain global, and installing a different loop over it is the seam
langs already use — x-python and x-ash both read their own syntax that way.
`x/repl/line` installs itself the same way and only when it has a terminal to
drive. `%repl-prompt`, `%repl-prompt-more` and `%repl-print` are the smaller
adjustments that do not need a new loop.

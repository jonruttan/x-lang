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

## Brackets

Parens are coloured by nesting depth, cycling yellow, magenta, cyan from the
outside in, so both halves of a pair share a colour and the eye can pair
them at a glance. A close paren with nothing to close is bold red; an open
paren that is not closed yet is simply its depth's colour, since that is the
state of every line while it is being typed. The pair beside the cursor is
drawn inverse on top of its colour: a close just before the cursor is
preferred, so a pair lights as its close is typed, and an open under the
cursor is matched forward. When the line is submitted it is drawn once more
with no cursor, so the depth colours stay in the transcript and the inverse
does not.

Strings, comments and character literals are stepped over, so `#\(` is not
an open paren and a paren inside a string is not counted. The depths are
worked out on the whole line, not the visible window, so a line that has
scrolled sideways still colours correctly.

`(Paint marks line at)` answers the marks for a cursor position, one per
paren as `(offset depth focused)`, and `(Paint line text marks)` paints them,
so the two can be used apart from the editor.

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

## Colouring another language

`%repl-paint` is the third customisation point beside `%repl-prompt` and
`%repl-print`: a function from the line's text to the text to display for it.
Set it and the editor uses it from the next keystroke. It is called with a
second argument, the bracket marks for that redraw as `(offset depth focused)`
lists translated into the window; a painter written for one argument ignores
it.

`%repl-marks` is the fourth: a function from the whole line and the cursor
offset to those marks, one per bracket as `(offset depth focused)`, depth
being the nesting level from 0, -1 for a close with nothing to close, and
focused true on the pair the cursor is beside. A lang whose brackets are not
x-lang's sets its own, or leaves it nil to mark nothing. It is installed and
guarded the same way as `%repl-paint`.

```x
(set! %repl-paint (fn (_ s) (my-lang-highlight s)))
```

It exists because colouring is the only part of a session that is about the
language being typed. Reading a key, moving a cursor and remembering a line
are the same job whatever the syntax is, and this editor does them for every
lang that has not replaced the loop. Where the tokens begin and end is not the
same job, and the langs do not even agree on where that answer lives: x-logo
registers its tokens as types on the base, while x-python parses Python itself
and never touches the base tokenizer. One painter cannot serve both.

The platform installs its own painter over nil, or over the painter it last
installed, and over nothing else -- so a lang's painter survives whether it is
set before the editor loads or after, and across a state image reload. Nil
means *no painter installed*, not *no colour*: `--no-color`, `NO_COLOR` and
`TERM=dumb` are what answer the colour question, and the platform painter
honours all three by returning its argument untouched.

A painter that raises does not take the keystroke down with it. The line is
drawn unpainted for that redraw.

## Reading another language

`%repl-eval-line` is the fifth seam, and the one that lets a lang keep the
editor: a function from the finished line's text to nothing, which reads it,
evaluates what it holds and prints the results. The platform's hands the text
to the x reader and reads on under `%repl-prompt-more` while the reader says
the form is unfinished. A lang whose syntax is not x-lang's sets its own —
one that collects a block to the blank line and parses Python, say — and the
keys, the history, the colour and the completion around it stay. It asks for
further lines itself with `(Line read %repl-prompt-more)`.

`%repl-complete` is the sixth: Tab's candidate source, a function from the
edit buffer to `(typed . names)`, or nil for a Tab that does nothing.
`(Line completer)` reads and sets it.

## Switching languages

The seven seams together are what a prompt is, and `Lang` keeps them as a
named bundle so a session can move between languages:

```x
(Lang register! "python"
  (list (pair '%repl-prompt ">>> ")
        (pair '%repl-prompt-more "... ")
        (pair '%repl-print %py-print)
        (pair '%repl-paint %py-paint)
        (pair '%repl-marks ())
        (pair '%repl-complete %py-complete)
        (pair '%repl-eval-line %py-eval-line)))
```

`(lang python)` installs it, and the next line the editor reads is Python,
coloured as Python; `(lang)` lists what is registered and names the current
one. A lang's own spelling of the switch is a call to the same `Lang use!`.
A seam a bundle does not name takes x-lang's value for it, so nil is said
rather than left out: no painter, Tab off.

x-lang's own bundle is `"x"`, assembled by the files that own its parts as
they load and re-assembled after a state image loads, so switching back
restores the coloured printer, the painter and the completer of the running
process rather than the ones a snapshot carried.

## Replacing it

`repl` is a plain global, and installing a different loop over it is the seam
langs used before `%repl-eval-line` existed — x-python and x-ash both read
their own syntax that way, and a lang that does so gives up the editor.
`x/repl/line` installs itself the same way and only when it has a terminal to
drive.

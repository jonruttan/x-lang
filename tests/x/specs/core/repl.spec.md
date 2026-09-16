# REPL operative: %repl-prompt / %repl-print
# @weight 1

The REPL is an x-lang operative (`lib/x/repl/loop.x`), and its prompt and print
path are **customizable variables** rather than C hooks. These were previously
untested. The print-path tests use the harness's full-output (```` ```output ````)
mode, since `%repl-print` emits during evaluation. Each customization test
saves and restores the variable so it cannot leak into later tests (the batch
harness itself drives output through `%repl-print`).

## %repl-prompt

### the default prompt is "> "

```x
%repl-prompt
```
---
    "> "

### is a customizable variable (set! then restore)

```x
(do
  (def %old %repl-prompt)
  (set! %repl-prompt "x> ")
  (def %r %repl-prompt)
  (set! %repl-prompt %old)
  %r)
```
---
    "x> "

## %repl-print

### writes a value, then a newline

```x
(do (%repl-print 42) ())
```
---
```output
42
```

### writes strings in read syntax (quoted)

```x
(do (%repl-print "hi") ())
```
---
```output
"hi"
```

### prints nothing for nil -- just the newline (no "()")

```x
(do (%repl-print ()) (display "after") (newline))
```
---
```output
after
```

### is customizable: a custom printer takes effect, then restores

```x
(do
  (def %old %repl-print)
  (set! %repl-print (fn (_ r) (display "P=") (write r) (newline)))
  (%repl-print 7)
  (set! %repl-print %old)
  ())
```
---
```output
P=7
```

## %banner

### a dialect banner names the dialect, its version, and the exit path

```x
(do
  (def %on %lang-name) (def %ov %lang-version)
  (set! %lang-name "x-test") (set! %lang-version "1.0")
  (%banner)
  (set! %lang-name %on) (set! %lang-version %ov)
  ())
```
---
```output
x-test v1.0 on x-lang
(help) for help; (quit) or ctrl-d to exit
```

### the base dialect does not claim to run on itself

```x
(do
  (def %on %lang-name) (def %ov %lang-version)
  (set! %lang-name "x-lang") (set! %lang-version "1.0")
  (%banner)
  (set! %lang-name %on) (set! %lang-version %ov)
  ())
```
---
```output
x-lang v1.0
(help) for help; (quit) or ctrl-d to exit
```

## quit

### the binding exists (calling it would end the harness process)

```x
(null? quit)
```
---
    #f

## %repl-platform-repl

`repl` is the seam a lang replaces to read its own syntax — x-python and
x-ash both do — and `x/repl/line` replaces it too when it has a terminal.
Two installers over one global need a way to tell whose it currently is, so
the loop records its own by identity. Without that anchor the last one to
load wins, and a lang bundle loses its reader to the line editor, because a
bundle's entry runs before the launcher that imports it.

### the loop records its own repl, by identity

```x
(same? repl %repl-platform-repl)
```
---
    #t

### a replaced repl is detectably not the platform's

```x
(do (def %spec-old repl)
    (set! repl (op () () ()))
    (let ((replaced (same? repl %repl-platform-repl)))
      (set! repl %spec-old)
      (list replaced (same? repl %repl-platform-repl))))
```
---
    (#f #t)

## %repl-paint

The third customisation point beside `%repl-prompt` and `%repl-print`. It
exists because colouring is the part of a session that depends on the
language. Reading a key and remembering a line are the same job whatever is
being typed; where the tokens begin and end is not. A lang sets this to a
painter that knows its own syntax.

### it exists, and starts with no painter installed

Nil means no painter, not "no colour" -- `x/repl/paint` installs the
platform's when the line editor loads it, and `--no-color` is what answers the
colour question.

```x
(null? %repl-paint)
```
---
    #t

### and so does %repl-marks, the marker beside it

Both are nil until x/repl/paint installs the platform's, which the first
import below does; this case runs before it.

```x
(null? %repl-marks)
```
---
    #t

### a painter is a function from the line's text to the text to display

```x
(do
  (def %spec-old %repl-paint)
  (set! %repl-paint (fn (_ s) (Str8 append "[" (Str8 append s "]"))))
  (let ((r (%repl-paint "(f x)")))
    (set! %repl-paint %spec-old)
    r))
```
---
    "[(f x)]"

### the platform installs over nil, and never over a lang's own painter

x/repl/paint's install is the rule repl/ansi.x follows for the printer: over
nil, or over the painter it last installed itself, and over nothing else. A
bundle's entry runs before the launcher that imports the editor, so an
unconditional install would take a lang's painter away and colour its lines as
x-lang.

```x
(do (import x/repl/paint)
    (def %spec-old %repl-paint)
    (def %spec-old-marks %repl-marks)
    (def %spec-mine (fn (_ s) s))
    (set! %repl-paint %spec-mine)
    ((eval (lit %paint-install-hook!) (module x/repl/paint)))
    (let ((kept (same? %repl-paint %spec-mine)))
      (set! %repl-paint %spec-old)
      (set! %repl-marks %spec-old-marks)
      kept))
```
---
    #t

### and it does install when nothing has claimed the seat

The install fills both seats, so both are put back.

```x
(do (import x/repl/paint)
    (def %spec-old %repl-paint)
    (def %spec-old-marks %repl-marks)
    (set! %repl-paint ())
    ((eval (lit %paint-install-hook!) (module x/repl/paint)))
    (let ((filled (not (null? %repl-paint))))
      (set! %repl-paint %spec-old)
      (set! %repl-marks %spec-old-marks)
      filled))
```
---
    #t

## %repl-marks

The fourth customisation point: a mark for every bracket on a redraw, given
the whole line and the cursor, as (offset depth focused). A lang whose
brackets are not x-lang's sets its own.

### the platform installs over nil, and never over a lang's own marker

```x
(do (import x/repl/paint)
    (def %spec-old %repl-marks)
    (def %spec-old-paint %repl-paint)
    (def %spec-mine (fn (_ s at) ()))
    (set! %repl-marks %spec-mine)
    ((eval (lit %paint-install-hook!) (module x/repl/paint)))
    (let ((kept (same? %repl-marks %spec-mine)))
      (set! %repl-marks %spec-old)
      (set! %repl-paint %spec-old-paint)
      kept))
```
---
    #t

### the editor translates marks into the window it paints

Offsets become window-relative, and a mark outside the window is dropped: a
partner that has scrolled out of view is still found on the whole line, and
simply not drawn.

```x
(do (import x/repl/line)
    (let ((%ln-marks (eval (lit %ln-marks) (module x/repl/line))))
      (list (%ln-marks "(f x)" 5 2 5) (%ln-marks "(f x)" 3 0 5))))
```
---
    (((2 0 #t)) ((0 0 #f) (4 0 #f)))

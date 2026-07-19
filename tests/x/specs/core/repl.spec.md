# REPL operative: %repl-prompt / %repl-print

The REPL is an x-lang operative (`lib/x/repl/loop.x`), and its prompt and print
path are **customizable variables** rather than C hooks. These were previously
untested. The print-path tests use the harness's full-output (```` ```output ````)
mode, since `%repl-print` emits during evaluation. Each customization test
saves and restores the variable so it cannot leak into later tests (the batch
harness itself drives output through `%repl-print`).

## %repl-prompt

### the default prompt is "> "

```scheme
%repl-prompt
```
---
    "> "

### is a customizable variable (set! then restore)

```scheme
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

```scheme
(do (%repl-print 42) ())
```
---
```output
42
```

### writes strings in read syntax (quoted)

```scheme
(do (%repl-print "hi") ())
```
---
```output
"hi"
```

### prints nothing for nil -- just the newline (no "()")

```scheme
(do (%repl-print ()) (display "after") (newline))
```
---
```output
after
```

### is customizable: a custom printer takes effect, then restores

```scheme
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

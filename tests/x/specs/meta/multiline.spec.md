# Harness: full multi-line output mode
# @weight 1

Exercises the runner's own opt-in `output`-fenced comparison (full multi-line
stdout) and confirms the default last-line mode is unaffected in the same file.
See `tests/spec-runner.awk`. An expected block fenced as ```` ```output ````
compares every captured line; anything else compares only the last line.

## full-output mode

### captures multiple output lines, not just the last

```x
(do (display "alpha") (newline) (display "beta") (newline) (display "gamma") (newline))
```
---
```output
alpha
beta
gamma
```

### preserves an interior blank line

```x
(do (display "top") (newline) (newline) (display "bottom") (newline))
```
---
```output
top

bottom
```

### a single-line result still works under full mode

```x
(display "solo")
```
---
```output
solo
```

## last-line mode unaffected

### default mode still compares only the last line

```x
(do (display "ignored-first-line") (newline) (+ 2 3))
```
---
    5

## NUL bytes in captured output

A zero byte reaches the comparison as the literal text `<<NUL>>`, in the same
in-band sentinel style as the harness's own `<<SEP>>`. Escaping happens in the
pipeline, before awk reads the line: awk is a C-string language, so a raw NUL
in a record TERMINATES it and the rest of the line was silently lost -- `a\0b`
compared as `a`, and no spec could assert a zero byte at all. x-python needs
this: its `bytes` already carries NULs and its `str` is moving to a code-point
carrier that can hold one, so `print` of such a value has to be assertable.

`display` is NOT the door to test this with -- it stops at the zero byte
itself, so it never puts one on the wire. `(File write)` takes a buffer and an
explicit length, which is why the byte survives to stdout here.

### a raw NUL byte survives the capture

```x
(do
  (import x/sys/file)
  (def %mk (prim-ref (lit str) (lit make)))
  (def %toptr (prim-ref (lit str) (lit ->ptr)))
  (def %set (prim-ref (lit ptr) (lit set!)))
  (def r (%mk 3))
  (def pp (%toptr r))
  (%set pp 0 97 1)
  (%set pp 1 0 1)
  (%set pp 2 98 1)
  (File write 1 r 3)
  (newline))
```
---
```output
a<<NUL>>b
```

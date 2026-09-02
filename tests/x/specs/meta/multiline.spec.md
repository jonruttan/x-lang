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

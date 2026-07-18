# Fmt: rendering (width + indentation golden-master)

Characterizes the formatter's **rendering** — width estimation and the
indentation/width-threshold logic of the mutually-recursive `%fmt-expr` /
`%fmt-list` / `%fmt-body` printers (homed on the `Fmt` class in `lib/x/tool/fmt.x`).
This guards that refactor: a regression in the recursion would change the
indented shape below. Previously unassertable — the formatter writes multi-line
output, which needs the harness's full-output (```` ```output ````) mode.

These feed hand-quoted forms via `(lit …)` (so no tokenizer — sidestepping the
separate open `token-read-string` issue). A quoted form writes its symbols in
`(lit x)` syntax, so atoms render as `(lit +)` etc.; the point here is the
*structure* (line breaks + 2-space indentation), not the atom spelling. The
real tool feeds tokenizer output and is covered separately by `tools/fmt.spec.md`.

## Fmt width

### estimates the display width of a form

```scheme
(do (import x/tool/fmt) (Fmt width (lit (+ 1 2))))
```
---
    8

## Fmt expr

### a narrow form prints on one line (under the 60-char threshold)

```scheme
(do (import x/tool/fmt) (Fmt expr (lit (+ 1 2)) 0))
```
---
    ('+ 1 2)

### a wide form breaks across lines with 2-space indentation

```scheme
(do (import x/tool/fmt) (Fmt expr (lit (define (factorial n) (if (= n 0) 1 (* n (factorial (- n 1)))))) 0))
```
---
```output
('define
  ('factorial 'n)
  ('if ('= 'n 0) 1 ('* 'n ('factorial ('- 'n 1)))))
```

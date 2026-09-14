# Line: the seams a lang drives the editor through
# @weight 1

The editor splits into a half that carries a grammar and a half that does
not. The buffer, the cursor, the history and the redraw have no syntax in
them; the colouring and the completion are x-lang's, by construction --
`Paint`'s scan splits on `(`, `)`, `;` and `"`, and `%ln-candidates` walks
those same lexemes to find the head of the open form. So a lang whose REPL
loop calls `(Line read)` installs its own of each, or neither.

These cases drive `%ln-redraw` and `%ln-complete!` directly rather than
through `Line read`, which needs a terminal; the frame is emitted to fd 2 so
it does not land in the captured output. What they pin is which function the
editor asks, not the bytes the terminal finally sees.

A spec file is one process, and these cases install into it, so each one
installs what it needs rather than inheriting the case above -- the two that
test the defaults put them back first.

## painter

### the default paints x-lang

```x
(do (import x/repl/line)
    (Line painter (method-ref Paint line))
    (let ((s "(def x 42)")) (str=? ((Line painter) s) (Paint line s))))
```
---
    #t

### the redraw hands the visible bytes to the installed painter

```x
(do (import x/repl/line)
    (let ((seen (list ())) (ed (Edit make)))
      (Line painter (fn (_ s) (%set-first! seen s) s))
      (ed set-text! "(def x 42)" 10)
      (%ln-redraw 2 "> " ed 80)
      (first seen)))
```
---
    "(def x 42)"

### () turns colouring off, and the painter is not called

```x
(do (import x/repl/line)
    (let ((seen (list ())) (ed (Edit make)))
      (Line painter (fn (_ s) (%set-first! seen "called") s))
      (Line painter ())
      (ed set-text! "(def x 42)" 10)
      (%ln-redraw 2 "> " ed 80)
      (list (null? (Line painter)) (first seen))))
```
---
    (#t ())

### installing one answers with it

```x
(do (import x/repl/line)
    (let ((mine (fn (_ s) s)))
      (Line painter mine)
      (same? (Line painter) mine)))
```
---
    #t

## completer

### the default completes x names from the doc registry

```x
(do (import x/repl/line)
    (Line completer %ln-candidates)
    (let ((ed (Edit make)))
      (ed set-text! "(Str8 sta" 9)
      (%ln-complete! 2 ed)
      (ed text)))
```
---
    "(Str8 starts?"

### Tab asks the installed completer, and fills what it answers

```x
(do (import x/repl/line)
    (let ((ed (Edit make)))
      (Line completer (fn (_ e) (pair "de" (list "definitely"))))
      (ed set-text! "de" 2)
      (%ln-complete! 2 ed)
      (ed text)))
```
---
    "definitely"

### () turns Tab off without reaching for a candidate

```x
(do (import x/repl/line)
    (let ((ed (Edit make)))
      (Line completer ())
      (ed set-text! "(Str8 sta" 9)
      (%ln-complete! 2 ed)
      (list (null? (Line completer)) (ed text))))
```
---
    (#t "(Str8 sta")

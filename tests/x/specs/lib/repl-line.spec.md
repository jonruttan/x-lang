# Line: the completer a lang installs
# @weight 1

Tab has two halves. Finding the candidates reads x-lang: `%ln-candidates`
walks parens and quotes to find the head of the open form, then prefix-searches
the doc registry, which holds what x-lang modules document. A lang that parses
its own syntax has none of its names there. Filling a unique answer, extending
to the common prefix and listing on the second Tab are the same job whatever
the syntax is, and stay whichever completer is installed.

`(Line completer f)` installs one, `()` turns Tab off, and the colour has the
same seam in `%repl-paint`.

x/repl/line is a scoped module, so its private names are not bound in the
root: each case that drives one binds it from the module's environment,
`(eval (lit NAME) (module x/repl/line))`, which is the door a test takes to
a private. These cases drive `%ln-complete!` directly rather than through `Line read`,
which needs a terminal; its listing goes to fd 2 so it does not land in the
captured output. A spec file is one process and these cases install into it, so
each installs what it needs rather than inheriting the case above.

## default

### completes x names from the doc registry

```x
(do (import x/repl/line)
    (let ((%ln-candidates (eval (lit %ln-candidates) (module x/repl/line)))
          (%ln-complete! (eval (lit %ln-complete!) (module x/repl/line))))
      (Line completer %ln-candidates)
      (let ((ed (Edit make)))
        (ed set-text! "(Str8 sta" 9)
        (%ln-complete! 2 ed)
        (ed text))))
```
---
    "(Str8 starts?"

## an installed completer

### Tab asks it, and fills what it answers

```x
(do (import x/repl/line)
    (let ((%ln-complete! (eval (lit %ln-complete!) (module x/repl/line))))
      (let ((ed (Edit make)))
        (Line completer (fn (_ e) (pair "de" (list "definitely"))))
        (ed set-text! "de" 2)
        (%ln-complete! 2 ed)
        (ed text))))
```
---
    "definitely"

### it is handed the buffer

```x
(do (import x/repl/line)
    (let ((%ln-complete! (eval (lit %ln-complete!) (module x/repl/line))))
      (let ((seen (list ())) (ed (Edit make)))
        (Line completer (fn (_ e) (%set-first! seen (e text)) (pair "" ())))
        (ed set-text! "abc" 3)
        (%ln-complete! 2 ed)
        (first seen))))
```
---
    "abc"

### installing one answers with it

```x
(do (import x/repl/line)
    (let ((mine (fn (_ e) (pair "" ()))))
      (Line completer mine)
      (same? (Line completer) mine)))
```
---
    #t

## no completer

### () turns Tab off without reaching for a candidate

```x
(do (import x/repl/line)
    (let ((%ln-complete! (eval (lit %ln-complete!) (module x/repl/line))))
      (let ((ed (Edit make)))
        (Line completer ())
        (ed set-text! "(Str8 sta" 9)
        (%ln-complete! 2 ed)
        (list (null? (Line completer)) (ed text)))))
```
---
    (#t "(Str8 sta")

## the line evaluator

### a bare atom at the end of the line is a form

The editor hands the line back without its newline, and the reader drops a
final atom that nothing terminates. `name` at the prompt printed nothing while
`(def name 1)` printed, because the paren closes it.

```x
(do (import x/repl/line)
    (def %ln-spec-name "Jon")
    (let ((%ln-eval-line (eval (lit %ln-eval-line) (module x/repl/line))))
      (%ln-eval-line "%ln-spec-name")
      (%ln-eval-line "42")
      (%ln-eval-line "1 2")
      ()))
```
---
```output
"Jon"
42
1
2
```

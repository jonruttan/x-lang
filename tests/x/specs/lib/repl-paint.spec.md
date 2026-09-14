# Paint: colouring a half-typed line
# @weight 1

The interesting claim in `x/repl/paint` is that it does not decide what an
atom is. It hands the bytes to the READER and takes the type of the value
that comes back, so the colour and the evaluator cannot disagree — and a
literal syntax this file has never heard of classifies correctly anyway.

These cases run with colour off (the harness has no terminal), which is why
they check `classify` rather than escape codes: the classification is the
part that has to be right, and it is palette-independent.

## The reader decides what an atom is

### the numeric tower's spellings are all numbers

Not one of these is special-cased here. `3.14`, `1/2`, `0xff` and `1e9` are
numbers because the reader answers with a number.

```x
(do (import x/repl/paint)
    (List map (fn (_ s) (Paint classify s))
          (list "42" "-7" "3.14" "1/2" "0xff" "1e9")))
```
---
    ('number 'number 'number 'number 'number 'number)

### a lone minus is the operator it actually is, not a number

The rule a hand-written painter gets wrong first.

```x
(do (import x/repl/paint)
    (list (Paint classify "-") (Paint classify "+") (Paint classify "1+")))
```
---
    ('symbol 'symbol 'number)

### strings, characters and booleans

```x
(do (import x/repl/paint)
    (List map (fn (_ s) (Paint classify s))
          (list "\"hi\"" "#\\a" "#t" "#f")))
```
---
    ('string 'char 'bool 'bool)

### a construct is a construct, from lib/x/constructs.x

```x
(do (import x/repl/paint)
    (List map (fn (_ s) (Paint classify s))
          (list "def" "fn" "if" "match" "guard")))
```
---
    ('construct 'construct 'construct 'construct 'construct)

### the construct set is the one the rest of the toolchain reads

```x
(do (import x/repl/paint)
    (and (> ((Paint keywords) length) 20) ((Paint keywords) get-or #f "def")))
```
---
    #t

### names are told apart by the conventions the library itself follows

```x
(do (import x/repl/paint)
    (List map (fn (_ s) (Paint classify s))
          (list "foo" "%private" "Str8" "foo-bar?")))
```
---
    ('symbol 'private 'class 'symbol)

### an atom the reader cannot make sense of is a plain name, not an error

A line being typed is unreadable most of the time; that is not a failure.

```x
(do (import x/repl/paint)
    (Paint classify "\"unterminated"))
```
---
    'symbol

## Colour off is a passthrough

### with no terminal, line returns its argument unchanged

```x
(do (import x/repl/paint)
    (let ((s "(def x 42) ; note"))
      (list (Paint enabled?) (Str8 =? (Paint line s) s))))
```
---
    (#f #t)

### every class has a colour entry, empty though they are here

```x
(do (import x/repl/paint)
    (List all? (fn (_ c) (str? (Paint colour c))) (Paint classes)))
```
---
    #t

### classes covers what classify can answer

```x
(do (import x/repl/paint)
    (List all? (fn (_ c) (List includes? c (Paint classes)))
      (List map (fn (_ s) (Paint classify s))
        (list "42" "\"s\"" "#\\a" "#t" "def" "foo" "%p" "Str8"))))
```
---
    #t

## The construct set survives a lang rebinding the vocabulary

`(Paint keywords)` is a string-keyed `Dict`, and `Dict` compares content keys
with structural equality, so the painter depends on what `equal?` names. A
lang bundle may rebind it -- x-sweet ships `(def equal? eq?)` -- and a lookup
that followed the rebinding would miss every key while the set itself stayed
correct. Containers read `%equal?` in core/logic.x, so the construct set
classifies the same under any session's `equal?`.

### `def` is still a construct while `equal?` is eq?

`forget!` runs inside the window, so the set is built and read under the
rebinding. The first element checks that the rebinding is live.

```x
(do (import x/repl/paint)
  (let ((saved equal?))
    (set! equal? eq?)
    (let ((got (guard (e (list 'raised e))
                 (do (Paint forget!)
                     (list (equal? "a" "a") (Paint classify "def"))))))
      (set! equal? saved)
      (Paint forget!)
      got)))
```
---
    (#f 'construct)

### and the session's own `equal?` is back afterwards

```x
(equal? "a" "a")
```
---
    #t

## The memo

### forget! rebuilds the caches and classification survives it

```x
(do (import x/repl/paint)
    (let ((before (Paint classify "1/2")))
      (Paint forget!)
      (list before (Paint classify "1/2"))))
```
---
    ('number 'number)

## Bracket colouring

`marks` gives every paren in a line its nesting depth, which is what `line`
colours it by: both halves of a pair share a depth, so they share a colour,
and a close paren with nothing to close is -1. It runs on the scan's own
rules, so strings, comments and character literals are stepped over. Pure, so
it runs here with no terminal.

### each paren carries its depth, and a pair shares one

```x
(do (import x/repl/paint) (Paint marks "(a (b (c)))" 0))
```
---
    ((0 0 #t) (3 1 #f) (6 2 #f) (8 2 #f) (9 1 #f) (10 0 #t))

### an open paren without a close yet is depth 0, not an error

The state of every line while its first form is being typed.

```x
(do (import x/repl/paint) (Paint marks "(def x" 1))
```
---
    ((0 0 #f))

### a close paren with nothing to close is -1

```x
(do (import x/repl/paint) (Paint marks "f x)" 4))
```
---
    ((3 -1 #t))

### the pair beside the cursor is focused on both halves

A close just before the cursor is preferred, so the pair lights as its close
is typed; an open under the cursor is matched forward.

```x
(do (import x/repl/paint)
    (list (Paint marks "(def x (f 1))" 13)
          (Paint marks "(def x (f 1))" 12)))
```
---
    (((0 0 #t) (7 1 #f) (11 1 #f) (12 0 #t)) ((0 0 #f) (7 1 #t) (11 1 #t) (12 0 #f)))

### a cursor not beside a paren focuses nothing, and no parens is no marks

```x
(do (import x/repl/paint)
    (list (Paint marks "(f x" 3) (Paint marks "f x" 3) (Paint marks "" 0)))
```
---
    (((0 0 #f)) () ())

### a paren inside a string is not a paren

```x
(do (import x/repl/paint) (Paint marks "(\")\")" 5))
```
---
    ((0 0 #t) (4 0 #t))

### a character literal and a comment are stepped over

```x
(do (import x/repl/paint)
    (list (Paint marks "(f #\\()" 6) (Paint marks "(f) ; (" 3)))
```
---
    (((0 0 #t) (6 0 #t)) ((0 0 #t) (2 0 #t)))

### with colour off, marks change nothing

```x
(do (import x/repl/paint)
    (let ((s "(f (g))"))
      (Str8 =? (Paint line s (Paint marks s 0)) s)))
```
---
    #t

# Edit: the REPL line buffer
# @weight 1

`x/repl/edit` is the line editor with the terminal taken out of it: a string,
a cursor, a kill ring and a history walk, and not one descriptor. That is the
point of the split — every behaviour a person would otherwise have to check by
typing at a prompt is checked here, in the ordinary batch harness, with no pty
anywhere.

Offsets are bytes; motion is by character, so a multi-byte glyph is never
split in half.

## Inserting and deleting

### insert leaves the point after what was inserted

```x
(do (import x/repl/edit)
    (let ((e (Edit make))) (e insert! "hi") (list (e text) (e point))))
```
---
    ("hi" 2)

### insert happens AT the point, not at the end

```x
(do (import x/repl/edit)
    (let ((e (Edit make)))
      (e insert! "ab") (e back!) (e insert! "X")
      (list (e text) (e point))))
```
---
    ("aXb" 2)

### backspace at the start of the line is a no-op, not an error

```x
(do (import x/repl/edit)
    (let ((e (Edit make))) (e del-back!) (list (e text) (e point))))
```
---
    ("" 0)

### delete at the end of the line is a no-op

```x
(do (import x/repl/edit)
    (let ((e (Edit make))) (e insert! "ab") (e del!) (e text)))
```
---
    "ab"

## UTF-8: motion is by character, never by byte

`héllo` is six bytes and five characters. A cursor that moved by bytes would
land inside the `é` and the next redraw would render a replacement glyph for
the rest of the session.

### two characters back from the end is four bytes back

```x
(do (import x/repl/edit)
    (let ((e (Edit make))) (e insert! "héllo") (e back!) (e back!) (e point)))
```
---
    4

### backspace removes the whole sequence, not one of its bytes

```x
(do (import x/repl/edit)
    (let ((e (Edit make)))
      (e insert! "héllo") (e bol!) (e forward!) (e forward!) (e del-back!)
      (e text)))
```
---
    "hllo"

### prev-start lands on a boundary from inside a sequence's tail

```x
(do (import x/repl/edit)
    (list (Edit prev-start "hé" 3) (Edit next-start "hé" 1)))
```
---
    (1 3)

## Word motion

A word is anything that is not whitespace and not a delimiter the reader
breaks on, so `foo-bar?` and `+` are each one word.

### back-word skips the separators first, then the word

```x
(do (import x/repl/edit)
    (let ((e (Edit make))) (e insert! "ab cd") (e back-word!) (e point)))
```
---
    3

### back-word from inside a form stops at the atom, not at the paren

```x
(do (import x/repl/edit)
    (let ((e (Edit make))) (e insert! "(foo bar)") (e back!) (e back-word!) (e point)))
```
---
    5

### forward-word from the start of a form crosses the paren

```x
(do (import x/repl/edit)
    (let ((e (Edit make))) (e insert! "(foo bar)") (e bol!) (e forward-word!) (e point)))
```
---
    4

### a paren is not word material and a letter is

```x
(do (import x/repl/edit)
    (list (Edit word-byte? 40) (Edit word-byte? 97) (Edit word-byte? 32)))
```
---
    (#f #t #f)

## Killing and yanking

### kill to end of line saves what it removed

```x
(do (import x/repl/edit)
    (let ((e (Edit make)))
      (e insert! "hello world") (e bol!) (e forward!) (e kill-eol!)
      (list (e text) (e kill))))
```
---
    ("h" "ello world")

### kill to start of line leaves the point at 0

```x
(do (import x/repl/edit)
    (let ((e (Edit make)))
      (e insert! "hello") (e back!) (e kill-bol!)
      (list (e text) (e point) (e kill))))
```
---
    ("o" 0 "hell")

### kill-word then yank puts the word back

```x
(do (import x/repl/edit)
    (let ((e (Edit make)))
      (e insert! "ab cd") (e kill-word-back!)
      (let ((killed (e text))) (e yank!) (list killed (e text)))))
```
---
    ("ab " "ab cd")

## History

Newest first. The half-typed line is stashed when browsing starts and comes
back at the bottom of the walk, which is the behaviour that makes Up safe to
press by accident.

### a blank line and an immediate repeat are not recorded

```x
(do (import x/repl/edit)
    (let ((e (Edit make)))
      (e remember! "one") (e remember! "two") (e remember! "two") (e remember! "   ")
      (e hist)))
```
---
    ("two" "one")

### walking back reaches each entry, then stops at the oldest

```x
(do (import x/repl/edit)
    (let ((e (Edit make)))
      (e remember! "one") (e remember! "two")
      (list (list (e earlier!) (e text))
            (list (e earlier!) (e text))
            (list (e earlier!) (e text)))))
```
---
    ((#t "two") (#t "one") (#f "one"))

### the half-typed line is stashed on the way out and restored on the way back

```x
(do (import x/repl/edit)
    (let ((e (Edit make)))
      (e remember! "one") (e remember! "two")
      (e insert! "draft")
      (e earlier!) (e earlier!)
      (list (list (e later!) (e text))
            (list (e later!) (e text))
            (list (e later!) (e text)))))
```
---
    ((#t "two") (#t "draft") (#f "draft"))

### browsing? reports whether a history entry is on show

```x
(do (import x/repl/edit)
    (let ((e (Edit make)))
      (e remember! "one")
      (let ((fresh (e browsing?)))
        (e earlier!)
        (let ((walking (e browsing?)))
          (e later!)
          (list fresh walking (e browsing?))))))
```
---
    (#f #t #f)

### remembering a line ends the walk

```x
(do (import x/repl/edit)
    (let ((e (Edit make)))
      (e remember! "one") (e earlier!) (e remember! "two")
      (list (e browsing?) (e hist))))
```
---
    (#f ("two" "one"))

## Reading around the point

### before and after split the line at the cursor

```x
(do (import x/repl/edit)
    (let ((e (Edit make)))
      (e insert! "abcd") (e back!) (e back!)
      (list (e before) (e after))))
```
---
    ("ab" "cd")

### set-text! clamps a point past the end

```x
(do (import x/repl/edit)
    (let ((e (Edit make))) (e set-text! "abc" 99) (list (e text) (e point))))
```
---
    ("abc" 3)

### clear! ends the history walk, so the next Up starts from the newest entry

```x
(do (import x/repl/edit)
    (let ((e (Edit make)))
      (e remember! "one") (e remember! "two")
      (e earlier!) (e earlier!)
      (e clear!)
      (list (e text) (e browsing?) (list (e earlier!) (e text)))))
```
---
    ("" #f (#t "two"))

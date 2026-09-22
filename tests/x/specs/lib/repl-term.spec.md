# Term: decoding a keystroke
# @weight 1

`Term key` takes a function that yields the next byte rather than a
descriptor, which is the whole reason a terminal's key decoding can be tested
here at all: a spec hands it a list and never opens a tty.

Each case below builds such a reader over a byte list. Three shapes come
back: a STRING of literal text to insert, a SYMBOL naming a key, or nil when
the input ended.

## Literal text

### an ASCII byte is the character to insert

```x
(do (import x/repl/term)
    (Term key (fn (_) 65)))
```
---
    "A"

### a two-byte UTF-8 sequence arrives whole

```x
(do (import x/repl/term)
    (let ((bs (list 195 169)))
      (Term key (fn (_) (if (null? bs) () (let ((b (first bs))) (set! bs (rest bs)) b))))))
```
---
    "é"

### a three-byte sequence arrives whole

```x
(do (import x/repl/term)
    (let ((bs (list 226 130 172)))
      (Term key (fn (_) (if (null? bs) () (let ((b (first bs))) (set! bs (rest bs)) b))))))
```
---
    "€"

### end of input is nil

```x
(do (import x/repl/term)
    (null? (Term key (fn (_) ()))))
```
---
    #t

## Control bytes carry readline's names

```x
(do (import x/repl/term)
    (List map (fn (_ b) (Term key (fn (_) b)))
          (list 1 2 3 4 5 6 9 13 10 11 21 23 25 127)))
```
---
    ('home 'left 'interrupt 'eof 'end 'right 'complete 'enter 'enter 'kill-eol 'kill-bol 'kill-word 'yank 'backspace)

### an unbound control byte is dropped, not inserted

A byte with no binding must never reach the buffer: the redraw measures what
it holds, and an unprintable byte has no width.

```x
(do (import x/repl/term)
    (Term key (fn (_) 24)))
```
---
    'unbound

### ctrl-v is quoted-insert

The key after it is inserted as text, whatever it would have done; the loop
in x/repl/line reads that key.

```x
(do (import x/repl/term)
    (Term key (fn (_) 22)))
```
---
    'quoted-insert

## Escape sequences

### the CSI arrows

```x
(do (import x/repl/term)
    (List map
      (fn (_ bs) (Term key (fn (_) (if (null? bs) () (let ((b (first bs))) (set! bs (rest bs)) b)))))
      (list (list 27 91 65) (list 27 91 66) (list 27 91 67) (list 27 91 68))))
```
---
    ('up 'down 'right 'left)

### SS3 arrows, which a terminal in application-cursor mode sends instead

```x
(do (import x/repl/term)
    (List map
      (fn (_ bs) (Term key (fn (_) (if (null? bs) () (let ((b (first bs))) (set! bs (rest bs)) b)))))
      (list (list 27 79 65) (list 27 79 68) (list 27 79 72) (list 27 79 70))))
```
---
    ('up 'left 'home 'end)

### Home, End and Delete in both their spellings

```x
(do (import x/repl/term)
    (List map
      (fn (_ bs) (Term key (fn (_) (if (null? bs) () (let ((b (first bs))) (set! bs (rest bs)) b)))))
      (list (list 27 91 72) (list 27 91 70)
            (list 27 91 49 126) (list 27 91 52 126) (list 27 91 51 126))))
```
---
    ('home 'end 'home 'end 'delete)

### a ctrl-modified arrow is word motion

The modifier arrives as `;5` among the parameter bytes, which is why the
parameters are kept rather than dropped at the final byte.

```x
(do (import x/repl/term)
    (List map
      (fn (_ bs) (Term key (fn (_) (if (null? bs) () (let ((b (first bs))) (set! bs (rest bs)) b)))))
      (list (list 27 91 49 59 53 67) (list 27 91 49 59 53 68))))
```
---
    ('word-right 'word-left)

### meta-b and meta-f are the same two motions

```x
(do (import x/repl/term)
    (List map
      (fn (_ bs) (Term key (fn (_) (if (null? bs) () (let ((b (first bs))) (set! bs (rest bs)) b)))))
      (list (list 27 98) (list 27 102) (list 27 127))))
```
---
    ('word-left 'word-right 'kill-word)

### an escape that goes nowhere is 'escape, not a stray insert

```x
(do (import x/repl/term)
    (let ((bs (list 27)))
      (Term key (fn (_) (if (null? bs) () (let ((b (first bs))) (set! bs (rest bs)) b))))))
```
---
    'escape

## Capability, without a terminal

### a pipe is not a tty, so raw! declines and restore! of nil is a no-op

The two together are what let a caller bracket a read unconditionally and
fall back when there is nothing to bracket.

```x
(do (import x/repl/term)
    (list (Term tty? 0) (null? (Term raw! 0)) (Term restore! 0 ())))
```
---
    (#f #t #f)

### window always answers, falling back rather than failing

```x
(do (import x/repl/term)
    (let ((s (Term window 0))) (and (> (first s) 0) (> (rest s) 0))))
```
---
    #t

## write

### writes an integer

```scheme
(write 42)
```
---
    42

### writes a string with quotes

```scheme
(write "hello")
```
---
    "hello"

### writes a symbol

```scheme
(write 'hello)
```
---
    'hello

### writes a list

```scheme
(write (lit (1 2 3)))
```
---
    (1 2 3)

### writes a nested list

```scheme
(write (lit (1 (2 3))))
```
---
    (1 (2 3))

### writes a nested empty list

```scheme
(write (list (list)))
```
---
    (())

### writes a named character

```scheme
(write #\newline)
```
---
    #\newline

### returns nil

```scheme
(do (def r (write 42)) (newline) (null? r))
```
---
    #t

## display

### displays an integer

```scheme
(display 42)
```
---
    42

### displays a string without quotes

```scheme
(display "hello")
```
---
    hello

### displays a symbol

```scheme
(display 'hello)
```
---
    hello

### displays a list

```scheme
(display (lit (1 2 3)))
```
---
    (1 2 3)

### returns nil

```scheme
(do (def r (display 42)) (newline) (null? r))
```
---
    #t

### displays the most-negative fixnum (word-size portable)

The probe computes the platform's most-negative fixnum from %word-size
(a 64-bit literal can never pass on the 32-bit Pi), and asserts
properties instead of a literal: negative rendering, termination, and
str->number round-trip.  Relies on two's-complement wrap like every
raw-op consumer.

```scheme
(do
  (def %n (<< 1 (- (* 8 %word-size) 1)))
  (def %s ((prim-ref 'io 'display-to-str) %n))
  (list (eq? (%str-ref %s 0) #\-) (< 1 (%str-length %s)) (eq? (%str->number %s) %n)))
```
---
    (#t #t #t)

### does not spoof a boolean on value-word collision

```scheme
(str=? ((prim-ref 'io 'display-to-str) (%cell-int #t)) "#t")
```
---
    #f

## opaque forms

The seven opaque types render fixed #<...> forms from boot/printer.x (the
retired C write handlers printed the same strings).

### procedure, operative, primitive, pointer

```scheme
(list ((prim-ref 'io 'write-to-str) (fn (_ x) x))
      ((prim-ref 'io 'write-to-str) (op (x) e ()))
      ((prim-ref 'io 'write-to-str) (prim-ref 'io 'write-str))
      ((prim-ref 'io 'write-to-str) ((prim-ref 'obj '->ptr) 0)))
```
---
    ("#<fn>" "#<op>" "#<prim>" "#<ptr>")

### display falls back to the write form

```scheme
(display (pair 1 (pair (fn (_ x) x) ())))
```
---
    (1 #<fn>)

### to-str captures opaque forms without leaking to stdout

```scheme
(do
  (def %s ((prim-ref 'io 'write-to-str) (pair (fn (_ x) x) ())))
  (display "[") (display %s) (display "]"))
```
---
    [(#<fn>)]

## newline

### returns nil

```scheme
(null? (newline))
```
---
    #t

## read

### reads an integer

```scheme
(do (def x (Io read)) x) 42
```

### reads a symbol

```scheme
(do (def x (Io read)) x) hello
```

### reads a list

```scheme
(do (def x (Io read)) x) (1 2 3)
```

### reads a string

```scheme
(do (def x (Io read)) x) "world"
```

## read-char

### reads a single character

```scheme
(do (def c (Io read-char)) (char? c))
```

### returns nil on end of input

```scheme
(do (Io read-char) (null? (Io read-char)))
```

## current-line

### returns positive integer

```scheme
(> (%current-line) 0)
```
---
    #t

## gc

### returns nil

```scheme
(null? (Heap collect))
```
---
    #t


## write-fits?: bounded rendering

`(io write-fits?)` answers "does this render in under N columns?" by counting
through the printer's own sink and aborting at the limit -- so it never
materializes the text, and its cost is bounded by N rather than by the form.
It must agree with measuring `write-to-str` the long way, which is what these
pin.

### agrees with write-to-str's length, form by form

```scheme
(do
  (def fits? (prim-ref (lit io) (lit write-fits?)))
  (def wtos (prim-ref (lit io) (lit write-to-str)))
  (def long? (fn (_ f n) (< ((wtos f)) n)))
  (def forms (list 1 "ab" (lit sym) (list 1 2 3) (list "a" (list 2 (list 3 4)))
                   (list (lit lit) (lit x)) (pair 1 2) ()))
  (%for-each (fn (_ f)
    (%for-each (fn (_ n)
      (unless (eq? (fits? f n) (long? f n))
        (Err raise (lit value) "write-fits? disagrees with write-to-str" f)))
      (list 1 2 3 5 8 20)))
    forms)
  #t)
```
---
    #t

### counts CODE POINTS, not bytes

`"aé"` writes as 4 code points in 5 bytes, so a byte count would refuse a
width the form actually fits.

```scheme
(do
  (def fits? (prim-ref (lit io) (lit write-fits?)))
  (def wtos (prim-ref (lit io) (lit write-to-str)))
  (list ((wtos "aé")) (Str8 length (wtos "aé")) (fits? "aé" 5) (fits? "aé" 4)))
```
---
    (4 5 #t #f)

### the sink is restored after an aborted render

```scheme
(do
  (def fits? (prim-ref (lit io) (lit write-fits?)))
  (def wtos (prim-ref (lit io) (lit write-to-str)))
  (fits? (list 1 2 3 4 5 6 7 8 9) 3)
  (wtos (list 1 2)))
```
---
    "(1 2)"

### a nested ask keeps its own counter

```scheme
(do
  (def fits? (prim-ref (lit io) (lit write-fits?)))
  (def wtos (prim-ref (lit io) (lit write-to-str)))
  (list (wtos (list 1 (fits? (list 1 2 3) 3) 2))
        (fits? (list 1 (fits? (list 9 9 9) 3) 2) 60)))
```
---
    ("(1 #f 2)" #t)

## repl-read -- deliberately not specced here

`repl-read` reads a form from the process's stdin. Under this harness stdin
IS the program being fed to the interpreter, so calling it consumes the rest
of the spec file: the same hazard that put `x/constructs` and `x/repl/launch`
on the doctest denylist, where it silently swallowed 40 tests. Its behaviour
is covered end-to-end by the REPL specs, which drive a real session rather
than calling the primitive mid-file.

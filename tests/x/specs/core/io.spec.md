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
(write (lit hello))
```
---
    (lit hello)

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
(display (lit hello))
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
  (def %s ((prim-ref (lit io) (lit display-to-str)) %n))
  (list (eq? (str-ref %s 0) #\-) (< 1 (str-length %s)) (eq? (str->number %s) %n)))
```
---
    (#t #t #t)

### does not spoof a boolean on value-word collision

```scheme
(str=? ((prim-ref (lit io) (lit display-to-str)) (first-int #t)) "#t")
```
---
    #f

## opaque forms

The seven opaque types render fixed #<...> forms from boot/printer.x (the
retired C write handlers printed the same strings).

### procedure, operative, primitive, pointer

```scheme
(list ((prim-ref (lit io) (lit write-to-str)) (fn (_ x) x))
      ((prim-ref (lit io) (lit write-to-str)) (op (x) e ()))
      ((prim-ref (lit io) (lit write-to-str)) (prim-ref (lit io) (lit write-str)))
      ((prim-ref (lit io) (lit write-to-str)) ((prim-ref (lit obj) (lit ->ptr)) 0)))
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
  (def %s ((prim-ref (lit io) (lit write-to-str)) (pair (fn (_ x) x) ())))
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
(> (current-line) 0)
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


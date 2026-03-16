## open-input-string

### string port is input port

```scheme
(input-port? (open-input-string "test"))
```
---
    #t

### read from string port

```scheme
(define p (open-input-string "(+ 1 2)"))
(read p)
```
---
    (+ 1 2)

### read-char from string port

```scheme
(define p (open-input-string "hello"))
(read-char p)
```
---
    h

### multiple read-chars

```scheme
(define p (open-input-string "ab"))
(list (read-char p) (read-char p))
```
---
    (a b)

### eof after string exhausted

```scheme
(define p (open-input-string "x"))
(read-char p)
(eof-object? (read-char p))
```
---
    #t

### read multiple values

```scheme
(define p (open-input-string "1 2 3"))
(list (read p) (read p) (read p))
```
---
    (1 2 3)

### empty string gives eof

```scheme
(define p (open-input-string ""))
(eof-object? (read-char p))
```
---
    #t

### read string with special chars

```scheme
(define p (open-input-string "(define x 42)"))
(read p)
```
---
    (define x 42)

### close string port

```scheme
(define p (open-input-string "hello"))
(close-input-port p)
#t
```
---
    #t

## open-output-string

### output string port is output port

```scheme
(output-port? (open-output-string))
```
---
    #t

### get-output-string empty

```scheme
(get-output-string (open-output-string))
```
---
    ""

### write to string port

```scheme
(define p (open-output-string))
(display "hello" p)
(get-output-string p)
```
---
    "hello"

### write multiple to string port

```scheme
(define p (open-output-string))
(display "abc" p)
(display "def" p)
(get-output-string p)
```
---
    "abcdef"

### write-char to string port

```scheme
(define p (open-output-string))
(write-char #\x p)
(get-output-string p)
```
---
    "x"

### newline to string port

```scheme
(define p (open-output-string))
(display "hi" p)
(newline p)
(display "there" p)
(string-length (get-output-string p))
```
---
    9

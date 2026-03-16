# Port System (R5RS §6.6)

## port predicates

### input-port? on input port

```scheme
(input-port? (open-input-file "/dev/null"))
```
---
    #t

### output-port? on output port

```scheme
(output-port? (open-output-file "/dev/null"))
```
---
    #t

### input-port? on output port

```scheme
(input-port? (open-output-file "/dev/null"))
```
---
    #f

### output-port? on input port

```scheme
(output-port? (open-input-file "/dev/null"))
```
---
    #f

### input-port? on non-port

```scheme
(input-port? 42)
```
---
    #f

### output-port? on non-port

```scheme
(output-port? "hello")
```
---
    #f

## current ports

### current-input-port is input

```scheme
(input-port? (current-input-port))
```
---
    #t

### current-output-port is output

```scheme
(output-port? (current-output-port))
```
---
    #t

## eof-object

### eof-object? on eof from empty file

```scheme
(let ((p (open-input-file "/dev/null")))
  (let ((r (read p)))
    (close-input-port p)
    (eof-object? r)))
```
---
    #t

### read-char eof from empty file

```scheme
(let ((p (open-input-file "/dev/null")))
  (let ((r (read-char p)))
    (close-input-port p)
    (eof-object? r)))
```
---
    #t

### eof-object? on non-eof

```scheme
(eof-object? 42)
```
---
    #f

### eof-object? on empty list

```scheme
(eof-object? '())
```
---
    #f

### eof-object? on boolean

```scheme
(eof-object? #f)
```
---
    #f

## boolean?

### boolean? true

```scheme
(boolean? #t)
```
---
    #t

### boolean? false

```scheme
(boolean? #f)
```
---
    #t

### boolean? number

```scheme
(boolean? 0)
```
---
    #f

### boolean? string

```scheme
(boolean? "hello")
```
---
    #f

### boolean? nil

```scheme
(boolean? '())
```
---
    #f

## char-ready?

### char-ready? returns boolean

```scheme
(boolean? (char-ready?))
```
---
    #t

## load

### load is defined

```scheme
(procedure? load)
```
---
    #t

## transcript

### transcript-on is defined

```scheme
(procedure? transcript-on)
```
---
    #t

### transcript-off is defined

```scheme
(procedure? transcript-off)
```
---
    #t

### transcript records display output

```scheme
(transcript-on "/tmp/x-test-transcript.txt")
(with-output-to-file "/dev/null" (lambda () (display "hello")))
(transcript-off)
(call-with-input-file "/tmp/x-test-transcript.txt"
  (lambda (p)
    (let ((c1 (read-char p))
          (c2 (read-char p))
          (c3 (read-char p))
          (c4 (read-char p))
          (c5 (read-char p)))
      (string c1 c2 c3 c4 c5))))
```
---
    "hello"

### transcript records write output

```scheme
(transcript-on "/tmp/x-test-transcript2.txt")
(with-output-to-file "/dev/null" (lambda () (write 42)))
(transcript-off)
(call-with-input-file "/tmp/x-test-transcript2.txt"
  (lambda (p)
    (let ((c1 (read-char p))
          (c2 (read-char p)))
      (string c1 c2))))
```
---
    "42"

### transcript records newline

```scheme
(transcript-on "/tmp/x-test-transcript3.txt")
(with-output-to-file "/dev/null"
  (lambda () (display "a") (newline) (display "b")))
(transcript-off)
(call-with-input-file "/tmp/x-test-transcript3.txt"
  (lambda (p)
    (let* ((c1 (read-char p))
           (c2 (read-char p))
           (c3 (read-char p)))
      (string c1 c3))))
```
---
    "ab"

### transcript-off stops recording

```scheme
(transcript-on "/tmp/x-test-transcript4.txt")
(with-output-to-file "/dev/null" (lambda () (display "yes")))
(transcript-off)
(with-output-to-file "/dev/null" (lambda () (display "no")))
(call-with-input-file "/tmp/x-test-transcript4.txt"
  (lambda (p)
    (let* ((c1 (read-char p))
           (c2 (read-char p))
           (c3 (read-char p))
           (c4 (read-char p)))
      (list (string c1 c2 c3) (eof-object? c4)))))
```
---
    ("yes" #t)

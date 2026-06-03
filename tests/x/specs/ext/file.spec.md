# @lib ../tests/x/lib/file.x

File I/O (`lib/x/sys/file.x`) issues raw Linux (x86_64) syscalls, so it cannot
run on a non-Linux dev machine. The `@lib` harness stubs `syscall`/`syscall-id`
to capture the arguments each function passes instead of performing real I/O.

These cases pin down **argument binding**: the regression they guard against is
every `file.x` function missing its leading `_` self slot, which silently
shifted every argument by one (so `fd`/`pathname` bound to the function object
itself rather than the caller's value).

## file: fopen argument binding

### passes pathname then numeric mode (not shifted by the self slot)

```scheme
(do
  (fopen "/path/x" 577)
  (def c (first %last-syscall))
  (and (str=? (first (rest c)) "/path/x")
       (eq? (first (rest (rest c))) 577)))
```
---
    #t

### resolves a symbolic mode via file-modes (rdwr -> 2)

```scheme
(do
  (fopen "/p" (lit rdwr))
  (eq? (first (rest (rest (first %last-syscall)))) 2))
```
---
    #t

## file: fread / fwrite argument binding

### fread passes fd, buffer, size in order

```scheme
(do
  (fread 7 "buf" 3)
  (def c (first %last-syscall))
  (and (eq? (first (rest c)) 7)
       (str=? (first (rest (rest c))) "buf")
       (eq? (first (rest (rest (rest c)))) 3)))
```
---
    #t

### fwrite passes the write op, fd, and buffer

```scheme
(do
  (fwrite 7 "data" 4)
  (def c (first %last-syscall))
  (and (eq? (first c) (lit write))
       (eq? (first (rest c)) 7)
       (str=? (first (rest (rest c))) "data")))
```
---
    #t

## file: fclose / fgetc argument binding

### fclose passes the close op and fd

```scheme
(do
  (fclose 9)
  (def c (first %last-syscall))
  (and (eq? (first c) (lit close))
       (eq? (first (rest c)) 9)))
```
---
    #t

### fgetc reads one byte via fread with the given fd, returns -1 at EOF

```scheme
(do
  (def r (fgetc 5))
  (and (eq? r (- 0 1))
       (eq? (first (first %last-syscall)) (lit read))
       (eq? (first (rest (first %last-syscall))) 5)))
```
---
    #t

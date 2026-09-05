# @lib ../tests/x/lib/file.x
# @weight 1

File I/O (`lib/x/sys/file.x`) issues raw Linux (x86_64) syscalls, so it cannot
run on a non-Linux dev machine. The `@lib` harness stubs `syscall`/`syscall-id`
to capture the arguments each function passes instead of performing real I/O.

These cases pin down **argument binding**: the regression they guard against is
every `File` method missing its leading `self` slot, which silently shifted
every argument by one (so `fd`/`pathname` bound to the method itself rather than
the caller's value).

## file: (File open) argument binding

### passes pathname then numeric mode (not shifted by the self slot)

```x
(do
  (File open "/path/x" 577)
  (def c (first %last-syscall))
  (and (str=? (first (rest c)) "/path/x")
       (eq? (first (rest (rest c))) 577)))
```
---
    #t

### resolves a symbolic mode via (File file-modes) (rdwr -> 2)

```x
(do
  (File open "/p" 'rdwr)
  (eq? (first (rest (rest (first %last-syscall)))) 2))
```
---
    #t

### ORs a list of flags together (numeric, platform-independent: 1|2|4 -> 7)

```x
(do
  (File open "/p" (list 1 2 4))
  (eq? (first (rest (rest (first %last-syscall)))) 7))
```
---
    #t

### ORs a list of stable symbolic flags (rdonly|wronly = 0|1 -> 1, same on every OS)

```x
(do
  (File open "/p" (list 'rdonly 'wronly))
  (eq? (first (rest (rest (first %last-syscall)))) 1))
```
---
    #t

### passes a default permission arg (0644 = 420) as open()'s third argument

```x
(do
  (File open "/p" 'creat)
  (eq? (first (rest (rest (rest (first %last-syscall))))) 420))
```
---
    #t

### accepts an explicit permission arg (0777 = 511)

```x
(do
  (File open "/p" 'creat 511)
  (eq? (first (rest (rest (rest (first %last-syscall))))) 511))
```
---
    #t

## file: (File read) / (File write) argument binding

### read passes fd, buffer, size in order

```x
(do
  (File read 7 "buf" 3)
  (def c (first %last-syscall))
  (and (eq? (first (rest c)) 7)
       (str=? (first (rest (rest c))) "buf")
       (eq? (first (rest (rest (rest c)))) 3)))
```
---
    #t

### write passes the write op, fd, and buffer

```x
(do
  (File write 7 "data" 4)
  (def c (first %last-syscall))
  (and (eq? (first c) 'write)
       (eq? (first (rest c)) 7)
       (str=? (first (rest (rest c))) "data")))
```
---
    #t

## file: (File close) / (File getc) argument binding

### close passes the close op and fd

```x
(do
  (File close 9)
  (def c (first %last-syscall))
  (and (eq? (first c) 'close)
       (eq? (first (rest c)) 9)))
```
---
    #t

### getc reads one byte via (File read) with the given fd, returns -1 at EOF

```x
(do
  (def r (File getc 5))
  (and (eq? r -1)
       (eq? (first (first %last-syscall)) 'read)
       (eq? (first (rest (first %last-syscall))) 5)))
```
---
    #t

## file: (File seek) / (File tell) / (File truncate) argument binding (#360)

### seek passes fd, offset, and the resolved whence symbol (end -> 2)

```x
(do
  (File seek 7 128 'end)
  (def c (first %last-syscall))
  (and (eq? (first c) 'lseek)
       (eq? (first (rest c)) 7)
       (eq? (first (rest (rest c))) 128)
       (eq? (first (rest (rest (rest c)))) 2)))
```
---
    #t

### seek defaults whence to 'set (absolute, 0)

```x
(do
  (File seek 7 32)
  (eq? (first (rest (rest (rest (first %last-syscall))))) 0))
```
---
    #t

### seek passes a numeric whence straight through

```x
(do
  (File seek 7 0 1)
  (eq? (first (rest (rest (rest (first %last-syscall))))) 1))
```
---
    #t

### tell is (seek fd 0 'cur)

```x
(do
  (File tell 7)
  (def c (first %last-syscall))
  (and (eq? (first c) 'lseek)
       (eq? (first (rest c)) 7)
       (eq? (first (rest (rest c))) 0)
       (eq? (first (rest (rest (rest c)))) 1)))
```
---
    #t

### truncate passes fd and the explicit size

```x
(do
  (File truncate 7 3)
  (def c (first %last-syscall))
  (and (eq? (first c) 'ftruncate)
       (eq? (first (rest c)) 7)
       (eq? (first (rest (rest c))) 3)))
```
---
    #t

### truncate without a size cuts at the current offset (tell's result)

```x
(do
  (File truncate 7)
  (def c (first %last-syscall))
  (and (eq? (first c) 'ftruncate)
       (eq? (first (rest c)) 7)
       (eq? (first (rest (rest c))) 0)))
```
---
    #t

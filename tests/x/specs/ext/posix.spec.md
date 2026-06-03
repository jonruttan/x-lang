# @lib ../tests/x/lib/posix.x

## fd-write

### writes to file descriptor

```scheme
(do (def fd (sh-open-write "/tmp/x-test-fd.txt"))
    (fd-write fd "hello")
    (sh-close fd)
    (file-exists? "/tmp/x-test-fd.txt"))
```
---
    #t

## file-exists?

### returns true for existing file

```scheme
(file-exists? "lib/x-core.x")
```
---
    #t

### returns false for missing file

```scheme
(file-exists? "/tmp/x-nonexistent-file-999")
```
---
    #f

## sh-getpid

### returns a positive integer

```scheme
(> (sh-getpid) 0)
```
---
    #t

## sh-getenv

### is a function

```scheme
(procedure? sh-getenv)
```
---
    #t

## sh-setenv

### is a function

```scheme
(procedure? sh-setenv)
```
---
    #t

## sh-open-write / sh-close

### opens and closes without error

```scheme
(do (def fd (sh-open-write "/tmp/x-test-open.txt"))
    (sh-close fd)
    #t)
```
---
    #t

## sh-open-read

### opens readable file

```scheme
(do (def fd (sh-open-read "lib/x-core.x"))
    (def ok (> fd 0))
    (sh-close fd)
    ok)
```
---
    #t

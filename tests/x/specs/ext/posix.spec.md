# @lib ../tests/x/lib/posix.x

## fd-write

### writes to file descriptor

```scheme
(do (def fd (Sys open-write "/tmp/x-test-fd.txt"))
    (Sys fd-write fd "hello")
    (Sys close fd)
    (Sys file-exists? "/tmp/x-test-fd.txt"))
```
---
    #t

## file-exists?

### returns true for existing file

```scheme
(Sys file-exists? "lib/x-core.x")
```
---
    #t

### returns false for missing file

```scheme
(Sys file-exists? "/tmp/x-nonexistent-file-999")
```
---
    #f

## sh-getpid

### returns a positive integer

```scheme
(> (Sys getpid) 0)
```
---
    #t

## getenv

### reads an unset variable as nil

```scheme
(null? (Sys getenv "X_SPEC_UNSET_VAR_42"))
```
---
    #t

## setenv

### reports success

```scheme
(Sys setenv "X_SPEC_VAR_42" "ok")
```
---
    0

## sh-open-write / sh-close

### opens and closes without error

```scheme
(do (def fd (Sys open-write "/tmp/x-test-open.txt"))
    (Sys close fd)
    #t)
```
---
    #t

## sh-open-read

### opens readable file

```scheme
(do (def fd (Sys open-read "lib/x-core.x"))
    (def ok (> fd 0))
    (Sys close fd)
    ok)
```
---
    #t

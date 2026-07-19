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

### roundtrips through getenv

```scheme
(do (Sys setenv "X_SPEC_RT_VAR" "ok") (Sys getenv "X_SPEC_RT_VAR"))
```
---
    "ok"

### overwrites an existing value

```scheme
(do (Sys setenv "X_SPEC_RT_VAR" "first")
    (Sys setenv "X_SPEC_RT_VAR" "second")
    (Sys getenv "X_SPEC_RT_VAR"))
```
---
    "second"

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

## failure paths are NEGATIVE ints (the Linux sign-fold pin)

On Linux, the ptr-call FFI prim hands libc's -1 back zero-extended
(4294967295) -- an int-returning callee writes only the low 32 bits of
the return register -- so without %sys-fold every one of these reads
failure as success. Darwin sign-extends, so only the Linux CI leg
distinguishes; that is the point of the pin.

### open-read on a missing path answers a negative fd

```scheme
(< (Sys open-read "/tmp/x-nonexistent-file-999") 0)
```
---
    #t

### chdir to a missing directory answers negative

```scheme
(< (Sys chdir "/tmp/x-nonexistent-dir-999") 0)
```
---
    #t

### fd-read on a bad fd is (), not a four-billion-byte walk

Unfolded, read(2)'s -1 became a 4294967295-iteration pointer walk off
the end of the buffer.

```scheme
(null? (Sys fd-read -1 4))
```
---
    #t

### fd-write on a bad fd answers negative

```scheme
(< (Sys fd-write -1 "x") 0)
```
---
    #t

### close on a bad fd answers negative

```scheme
(< (Sys close -1) 0)
```
---
    #t

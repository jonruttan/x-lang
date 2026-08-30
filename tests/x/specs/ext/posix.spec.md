# @lib ../tests/x/lib/posix.x
# @weight 1

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

## marshal guards: nil is NULL, unsupported args raise (#244)

`syscall` and the ptr-call FFI prim marshal arguments into positional
slots. An unsupported argument used to be silently SKIPPED, shifting
every following argument one slot left -- positional corruption in the
two rawest primitives. Now: a nil argument is the NULL pointer/zero and
fills its OWN slot (nil = NULL, the settled model -- the rn execve/wait4
examples spell NULL as `()`), and anything that is not nil/int/str(/ptr)
raises catchably at marshal time, before anything executes.

The ptr-call cases make a real cross-platform call (libc `getpid` via
`dlsym`); the syscall raise-case needs no valid syscall number because
the guard fires during marshalling, before the syscall executes (raw
syscall numbers are per-arch and unavailable on arm64 -- the rest of
this file uses the `Sys` abstraction for that reason).

### an unsupported syscall argument raises before the call fires

```scheme
(guard (e 'raised) (syscall 999 (list 1)))
```
---
    'raised

### a nil ptr-call argument marshals as NULL in its own slot

```scheme
(do (def %pc-dlopen (prim-ref 'ffi 'dlopen))
    (def %pc-dlsym (prim-ref 'ffi 'dlsym))
    (def %pc-call (prim-ref 'ptr 'call))
    (def %pc-fp (%pc-dlsym (%pc-dlopen () 1) "getpid"))
    (> (%pc-call %pc-fp ()) 0))
```
---
    #t

### an unsupported ptr-call argument raises

```scheme
(do (def %pc2-dlopen (prim-ref 'ffi 'dlopen))
    (def %pc2-dlsym (prim-ref 'ffi 'dlsym))
    (def %pc2-call (prim-ref 'ptr 'call))
    (def %pc2-fp (%pc2-dlsym (%pc2-dlopen () 1) "getpid"))
    (guard (e 'raised) (%pc2-call %pc2-fp (list 1))))
```
---
    'raised

## getcwd (#361)

### getcwd returns a string

```scheme
(str? (Sys getcwd))
```
---
    #t

### chdir and getcwd round-trip

```scheme
(do (def home (Sys getcwd))
    (Sys chdir "/")
    (def at-root (Sys getcwd))
    (Sys chdir home)
    (list (str=? at-root "/") (str=? (Sys getcwd) home)))
```
---
    (#t #t)

## setenv / unsetenv / environ (#361)

### unsetenv removes what setenv set

```scheme
(do (Sys setenv "X_SPEC_361" "v1")
    (def before (Sys getenv "X_SPEC_361"))
    (Sys unsetenv "X_SPEC_361")
    (list before (Sys getenv "X_SPEC_361")))
```
---
    ("v1" ())

### unsetenv of an absent name succeeds

```scheme
(Sys unsetenv "X_SPEC_361_NEVER_SET")
```
---
    0

### environ carries a variable we set, as NAME=VALUE

```scheme
(do (Sys setenv "X_SPEC_361E" "yes")
    (def found
      (let go ((es (Sys environ)))
        (if (null? es) #f
          (if (str=? (first es) "X_SPEC_361E=yes") #t (go (rest es))))))
    (Sys unsetenv "X_SPEC_361E")
    found)
```
---
    #t

## sleep (#361)

### sleep 0 and a 1ms usleep return 0 promptly

```scheme
(list (Sys sleep 0) (Sys usleep 1000))
```
---
    (0 0)

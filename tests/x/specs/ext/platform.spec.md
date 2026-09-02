# @lib ../tests/x/lib/platform.x
# @weight 1

The syscall/file layers are platform-aware: macOS (Darwin) uses BSD syscall
numbers and different `O_*` flag values than Linux. `syscall-id` and
`(File file-modes)` are pure lookups, so these cases compute the platform's
values **without issuing any real syscall**; the assertions branch on
`os-darwin?` so they hold on both Linux and macOS.

## platform: syscall numbers

### os-darwin? reflects the build machine (x-machine)

```x
(eq? os-darwin? (Str8 includes? "darwin" x-machine))
```
---
    #t

### syscall-id maps open to the platform's number (BSD 5 / Linux 2)

```x
(eq? (syscall-id 'open) (if os-darwin? 5 2))
```
---
    #t

### syscall-id maps read / write / close per platform

```x
(and (eq? (syscall-id 'read)  (if os-darwin? 3 0))
     (eq? (syscall-id 'write) (if os-darwin? 4 1))
     (eq? (syscall-id 'close) (if os-darwin? 6 3)))
```
---
    #t

### syscall-id maps fork / execve / wait4 per platform (examples/or/execve-ls.x)

```x
(and (eq? (syscall-id 'fork)   (if os-darwin? 2 57))
     (eq? (syscall-id 'execve) 59)
     (eq? (syscall-id 'wait4)  (if os-darwin? 7 61)))
```
---
    #t

## platform: open flags

### O_CREAT matches the platform (macOS 512 / Linux 64)

```x
(eq? (first (Assoc get 'creat (File file-modes))) (if os-darwin? 512 64))
```
---
    #t

### O_TRUNC matches the platform (macOS 1024 / Linux 512)

```x
(eq? (first (Assoc get 'trunc (File file-modes))) (if os-darwin? 1024 512))
```
---
    #t

### O_RDWR is 2 on every platform (the low access-mode bits are universal)

```x
(eq? (first (Assoc get 'rdwr (File file-modes))) 2)
```
---
    #t

## engine identity constants

`x-version`, `x-release` and `x-machine` are VALUE bindings, not calls --
`x_value_bind` in x-cli.c, from the build's headers.  Calling one applies the
string, which is a different operation entirely: `(x-version)` returns its
length, not its text.

### x-version is a string, not a callable

```x
(str? x-version)
```
---
    #t

### x-version carries a dotted version

The exact value moves with the release, so this asserts the shape.

```x
(Str8 includes? "." x-version)
```
---
    #t

### x-release is a non-empty string

Set from `git describe` at build time, so only its shape is stable.

```x
(if (str? x-release) (> ((prim-ref 'str 'byte-len) x-release) 0) #f)
```
---
    #t

### applying the value is a string call, NOT a lookup

`(x-version)` looks like an accessor and is not one; it applies the string to
no arguments, which answers its byte length.

```x
(eq? (x-version) ((prim-ref 'str 'byte-len) x-version))
```
---
    #t

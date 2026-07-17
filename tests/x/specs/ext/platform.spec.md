# @lib ../tests/x/lib/platform.x

The syscall/file layers are platform-aware: macOS (Darwin) uses BSD syscall
numbers and different `O_*` flag values than Linux. `syscall-id` and
`(File file-modes)` are pure lookups, so these cases compute the platform's
values **without issuing any real syscall**; the assertions branch on
`os-darwin?` so they hold on both Linux and macOS.

## platform: syscall numbers

### os-darwin? reflects the build machine (x-machine)

```scheme
(eq? os-darwin? (Str8 contains? "darwin" x-machine))
```
---
    #t

### syscall-id maps open to the platform's number (BSD 5 / Linux 2)

```scheme
(eq? (syscall-id (lit open)) (if os-darwin? 5 2))
```
---
    #t

### syscall-id maps read / write / close per platform

```scheme
(and (eq? (syscall-id (lit read))  (if os-darwin? 3 0))
     (eq? (syscall-id (lit write)) (if os-darwin? 4 1))
     (eq? (syscall-id (lit close)) (if os-darwin? 6 3)))
```
---
    #t

### syscall-id maps fork / execve / wait4 per platform (examples/or/execve-ls.x)

```scheme
(and (eq? (syscall-id (lit fork))   (if os-darwin? 2 57))
     (eq? (syscall-id (lit execve)) 59)
     (eq? (syscall-id (lit wait4))  (if os-darwin? 7 61)))
```
---
    #t

## platform: open flags

### O_CREAT matches the platform (macOS 512 / Linux 64)

```scheme
(eq? (first (assoc-get (lit creat) (File file-modes))) (if os-darwin? 512 64))
```
---
    #t

### O_TRUNC matches the platform (macOS 1024 / Linux 512)

```scheme
(eq? (first (assoc-get (lit trunc) (File file-modes))) (if os-darwin? 1024 512))
```
---
    #t

### O_RDWR is 2 on every platform (the low access-mode bits are universal)

```scheme
(eq? (first (assoc-get (lit rdwr) (File file-modes))) 2)
```
---
    #t

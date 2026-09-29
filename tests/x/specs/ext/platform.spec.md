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

### syscall-id maps open to the platform's number (BSD 5 / Linux x86-64 2 / none on arm64 Linux)

The Linux generic table, which arm64 uses, has no `open`: the miss is -1.

```x
(eq? (syscall-id 'open)
     (match (os-darwin? 5) (arch-arm64? -1) (#t 2)))
```
---
    #t

### syscall-id maps read / write / close per platform

```x
(def %want
  (match (os-darwin? (list 3 4 6))
         (arch-arm64? (list 63 64 57))
         (#t (list 0 1 3))))
(equal? (list (syscall-id 'read) (syscall-id 'write) (syscall-id 'close))
        %want)
```
---
    #t

### syscall-id maps fork / execve / wait4 per platform (examples/or/execve-ls.x)

```x
(def %want
  (match (os-darwin? (list 2 59 7))
         (arch-arm64? (list -1 221 260))
         (#t (list 57 59 61))))
(equal? (list (syscall-id 'fork) (syscall-id 'execve) (syscall-id 'wait4))
        %want)
```
---
    #t

## platform: the door

`syscall-door` resolves a call by name to something that makes it. These cases
make real calls, on a path every host has.

### a door opens and closes a directory

On arm64 Linux this is `openat`, with the working directory's descriptor ahead
of the path.

```x
(def %fd ((syscall-door 'open) "/" 0 0))
(list (> %fd 2) ((syscall-door 'close) %fd))
```
---
    (#t 0)

### a door for a name the platform cannot make raises when it is made

```x
(guard (e e) (syscall-door 'no-such-call))
```
---
    ('unsupported-syscall . 'no-such-call)

### a door through a stand-in puts each of its slots in place

A stand-in is the call made in a name's place, with its argument list. Only arm64
Linux has stand-ins, so this case builds one through the module's own builder:
`write` with the count fixed at two, which writes two bytes of the three it is
handed.

```x
(def %standing-in (eval (lit %door-standing-in) (module x/platform/syscall)))
(def %null (File open "/dev/null" 'wronly))
(def %write-2 (%standing-in (syscall-id 'write) (lit (a0 a1 2))))
(list (%write-2 %null "abc") (File close %null))
```
---
    (2 0)

### cwd in a shape is the working directory's descriptor

```x
((eval (lit %door-slots) (module x/platform/syscall)) (lit (cwd a0 cwd a1 0)))
```
---
    (-100 'a0 -100 'a1 0)

### a call through a door resolves nothing

A door is resolved when it is made, so a call through it costs its own frame
and no more: fewer than 40 objects a call over the primitive called with the
number in hand.

```x
(def %null (File open "/dev/null" 'wronly))
(def %n (syscall-id 'write))
(def %door (syscall-door 'write))
(def %cost
  (fn (_ f)
    (f)
    (def c0 (Heap count))
    ((fn (loop i) (if (= i 0) () (do (f) (loop (- i 1))))) 100)
    (- (Heap count) c0)))
(def %over
  (- (%cost (fn (_ ) (%door %null "ab" 2)))
     (%cost (fn (_ ) (syscall %n %null "ab" 2)))))
(list (< %over (* 40 100)) (File close %null))
```
---
    (#t 0)

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

### O_DIRECTORY matches the platform (macOS 1048576 / Linux x86-64 65536 / arm64 16384)

```x
(eq? (first (Assoc get 'directory (File file-modes)))
     (match (os-darwin? 1048576) (arch-arm64? 16384) (#t 65536)))
```
---
    #t

### O_SYNC on Linux carries O_DSYNC

```x
(if os-darwin? #t
  (eq? (first (Assoc get 'sync (File file-modes))) 1052672))
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

### applying the value is a call, and it names no index

`(x-version)` looks like an accessor and is not one -- it applies the string.
A string's value-call INDEXES, so a call with no index raises rather than
answering some other question about the string. `(Str length x-version)` is
the length; the constant itself is just `x-version`.

```x
(guard (e e) (x-version))
```
---
    "string: call with no index -- (Str length s) is the length"

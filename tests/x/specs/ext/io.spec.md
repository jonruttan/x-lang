# @lib ../tests/x/lib/io.x

# Real file I/O round-trips (Sys / File / Stream)

Actual end-to-end file I/O: write a temp file, read it back, assert the bytes,
and unlink. Previously untested -- `ext/file.spec.md` and `ext/stream.spec.md`
stub the syscall or only test fd-wrapping. `Sys` reads via libc FFI and returns
a list of byte values; `File` writes via raw syscall; `Stream` redirects
displayed output to a file. Each test cleans up its own `/tmp` file via `unlink`.

(Bytes are asserted directly: "abc" = `(97 98 99)`, "hello" =
`(104 101 108 108 111)`, "hi" = `(104 105)`.)

## Sys (libc FFI)

### write then read round-trips the bytes

```scheme
(do
  (def %p "/tmp/x-spec-io-sys.txt")
  (def %w (Sys open-write %p)) (Sys fd-write %w "abc") (Sys close %w)
  (def %r (Sys open-read %p)) (def %b (Sys fd-read %r 8)) (Sys close %r)
  (syscall (syscall-id 'unlink) %p)
  %b)
```
---
    (97 98 99)

### fd-read returns nil at end of file

```scheme
(do
  (def %p "/tmp/x-spec-io-eof.txt")
  (def %w (Sys open-write %p)) (Sys fd-write %w "z") (Sys close %w)
  (def %r (Sys open-read %p))
  (Sys fd-read %r 8)
  (def %eof (Sys fd-read %r 8))
  (Sys close %r)
  (syscall (syscall-id 'unlink) %p)
  (null? %eof))
```
---
    #t

### file-exists? tracks create then unlink

```scheme
(do
  (def %p "/tmp/x-spec-io-exists.txt")
  (syscall (syscall-id 'unlink) %p)
  (def %before (Sys file-exists? %p))
  (def %w (Sys open-write %p)) (Sys fd-write %w "x") (Sys close %w)
  (def %after (Sys file-exists? %p))
  (syscall (syscall-id 'unlink) %p)
  (def %gone (Sys file-exists? %p))
  (list %before %after %gone))
```
---
    (#f #t #f)

## File (raw syscall) write + Sys read

### File write lands bytes that read back

```scheme
(do
  (def %p "/tmp/x-spec-io-file.txt")
  (def %w (File open %p (list 'wronly 'creat 'trunc)))
  (File write %w "hello" 5)
  (File close %w)
  (def %r (Sys open-read %p)) (def %b (Sys fd-read %r 16)) (Sys close %r)
  (syscall (syscall-id 'unlink) %p)
  %b)
```
---
    (104 101 108 108 111)

## File (raw syscall) read

Reads fill a caller-allocated buffer; `(str make)` provides the GC-owned
region (File read/getc were blocked before it existed).

### File read fills a (str make) buffer

```scheme
(do
  (def %p "/tmp/x-spec-io-fread.txt")
  (def %w (Sys open-write %p)) (Sys fd-write %w "abc") (Sys close %w)
  (def %r (File open %p 'rdonly))
  (def %buf ((prim-ref 'str 'make) 8))
  (def %n (File read %r %buf 8))
  (File close %r)
  (syscall (syscall-id 'unlink) %p)
  (list (> %n 0) (%str-ref %buf 0)))
```
---
    (#t #\a)

### File getc returns the first byte as a char

```scheme
(do
  (def %p "/tmp/x-spec-io-getc.txt")
  (def %w (Sys open-write %p)) (Sys fd-write %w "Q") (Sys close %w)
  (def %r (File open %p 'rdonly))
  (def %c (File getc %r))
  (File close %r)
  (syscall (syscall-id 'unlink) %p)
  %c)
```
---
    #\Q

## Stream (redirect display to a file)

### with-output-to-file writes the displayed output

```scheme
(do
  (def %p "/tmp/x-spec-io-stream.txt")
  (Stream with-output-to-file %p (fn (_) (display "hi")))
  (def %r (Sys open-read %p)) (def %b (Sys fd-read %r 8)) (Sys close %r)
  (syscall (syscall-id 'unlink) %p)
  %b)
```
---
    (104 105)

# File ergonomics: read-all / write-all / stat / read-lines / list-dir (#22)

The ergonomic tier over the raw syscall layer: whole-file operations
that RAISE kind-'io Errs (via Err from-errno) instead of returning
negative results. Real I/O under /tmp; every test cleans up after
itself. The raw ops (open/close/read/write/getc/seek/tell/truncate)
keep their raw contract -- see ext/file.spec.md.

## write-all and read-all

### write-all writes, read-all reads back, unlink cleans up

```scheme
(do (import x/sys/posix) (import x/sys/file)
  (def p "/tmp/x-spec22-a")
  (def n (File write-all p "alpha\nbeta\n"))
  (def s (File read-all p))
  (File unlink p)
  (list n s (File exists? p)))
```
---
    (11 "alpha\nbeta\n" #f)

### write-all truncates on rewrite

```scheme
(do (import x/sys/posix) (import x/sys/file)
  (def p "/tmp/x-spec22-b")
  (File write-all p "a longer first body")
  (File write-all p "short")
  (def s (File read-all p))
  (File unlink p)
  s)
```
---
    "short"

## stat

### stat reports size and kind for a file we control

```scheme
(do (import x/sys/posix) (import x/sys/file)
  (def p "/tmp/x-spec22-c")
  (File write-all p "12345")
  (def st (File stat p))
  (File unlink p)
  (list (Assoc get 'size st) (Assoc get 'kind st) (> (Assoc get 'mtime st) 0)))
```
---
    (5 'file #t)

### a directory stats as kind 'dir

```scheme
(do (import x/sys/posix) (import x/sys/file)
  (Assoc get 'kind (File stat "/tmp")))
```
---
    'dir

### exists? is a presence door, not an error

```scheme
(do (import x/sys/posix) (import x/sys/file)
  (list (File exists? "/tmp") (File exists? "/tmp/x-spec22-definitely-not")))
```
---
    (#t #f)

## read-lines

### splits on newline, no phantom empty last line

```scheme
(do (import x/sys/posix) (import x/sys/file)
  (def p "/tmp/x-spec22-d")
  (File write-all p "one\ntwo\nthree\n")
  (def ls (File read-lines p))
  (File unlink p)
  ls)
```
---
    ("one" "two" "three")

### a file without a trailing newline keeps its last line

```scheme
(do (import x/sys/posix) (import x/sys/file)
  (def p "/tmp/x-spec22-e")
  (File write-all p "one\ntwo")
  (def ls (File read-lines p))
  (File unlink p)
  ls)
```
---
    ("one" "two")

## directories

### mkdir / list-dir / rename / rmdir roundtrip

```scheme
(do (import x/sys/posix) (import x/sys/file)
  (def d "/tmp/x-spec22-dir")
  (File mkdir d)
  (File write-all "/tmp/x-spec22-dir/inner" "x")
  (File rename "/tmp/x-spec22-dir/inner" "/tmp/x-spec22-dir/moved")
  (def names (File list-dir d))
  (File unlink "/tmp/x-spec22-dir/moved")
  (File rmdir d)
  (list names (File exists? d)))
```
---
    (("moved") #f)

### list-dir excludes dot and dotdot

```scheme
(do (import x/sys/posix) (import x/sys/file)
  (def d "/tmp/x-spec22-dir2")
  (File mkdir d)
  (def names (File list-dir d))
  (File rmdir d)
  (null? names))
```
---
    #t

## structured failure

### a missing file read-alls to a kind-'io enoent Err

```scheme
(do (import x/sys/posix) (import x/sys/file)
  (guard (e (list (Err kind-of e) (Assoc get 'sym (e data)) (Assoc get 'op (e data))))
    (File read-all "/tmp/x-spec22-definitely-not")))
```
---
    ('io 'enoent 'stat)

### rmdir on a missing directory raises, with the path as detail

```scheme
(do (import x/sys/posix) (import x/sys/file)
  (guard (e (Assoc get 'detail (e data)))
    (File rmdir "/tmp/x-spec22-definitely-not")))
```
---
    "/tmp/x-spec22-definitely-not"

## boundary guards

### a missing/nil path fails as kind-'type at the door, not EFAULT in the kernel

The class dispatch binds a missing argument as nil; before this guard
(File list-dir) surfaced as a baffling "Bad address" io error (or worse
through the REPL error path -- jon hit corrupted error bytes).

```scheme
(do (import x/sys/posix) (import x/sys/file)
  (list (guard (e (Err kind-of e)) (File list-dir))
        (guard (e (Err kind-of e)) (File read-all))
        (guard (e (Err kind-of e)) (File stat 42))
        (guard (e (Err kind-of e)) (File rename "a" ()))))
```
---
    ('type 'type 'type 'type)

## seek / tell / truncate (raw tier, #360)

### seek to end reports the size; an absolute seek rereads mid-file

```scheme
(do (import x/sys/posix) (import x/sys/file)
  (def p "/tmp/x-spec360-a")
  (File write-all p "hello world")
  (def fd (File open p 'rdonly))
  (def at-end (File seek fd 0 'end))
  (def back (File seek fd 6))
  (def buf ((prim-ref 'str 'make) 5))
  (def n (File read fd buf 5))
  (File close fd)
  (File unlink p)
  (list at-end back n buf))
```
---
    (11 6 5 "world")

### tell starts at 0 and tracks reads

```scheme
(do (import x/sys/posix) (import x/sys/file)
  (def p "/tmp/x-spec360-b")
  (File write-all p "abcdef")
  (def fd (File open p 'rdonly))
  (def t0 (File tell fd))
  (def buf ((prim-ref 'str 'make) 4))
  (File read fd buf 4)
  (def t1 (File tell fd))
  (File close fd)
  (File unlink p)
  (list t0 t1))
```
---
    (0 4)

### truncate to an explicit size; stat and read-all confirm

```scheme
(do (import x/sys/posix) (import x/sys/file)
  (def p "/tmp/x-spec360-c")
  (File write-all p "abcdef")
  (def fd (File open p 'wronly))
  (def r (File truncate fd 3))
  (File close fd)
  (def size (Assoc get 'size (File stat p)))
  (def body (File read-all p))
  (File unlink p)
  (list r size body))
```
---
    (0 3 "abc")

### truncate without a size cuts at the current offset

```scheme
(do (import x/sys/posix) (import x/sys/file)
  (def p "/tmp/x-spec360-d")
  (File write-all p "abcdef")
  (def fd (File open p 'rdwr))
  (File seek fd 2)
  (File truncate fd)
  (File close fd)
  (def body (File read-all p))
  (File unlink p)
  body)
```
---
    "ab"

### seek rejects an unknown whence symbol at the door

```scheme
(do (import x/sys/posix) (import x/sys/file)
  (list (guard (e (Err kind-of e)) (File seek 0 0 'nope))))
```
---
    ('type)

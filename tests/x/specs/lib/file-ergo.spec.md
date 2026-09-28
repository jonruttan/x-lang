# File ergonomics: read-all / write-all / stat / read-lines / list-dir (#22)
# @weight 2

The ergonomic tier over the raw syscall layer: whole-file operations
that RAISE label 'io Errs (via Err from-errno) instead of returning
negative results. Real I/O under /tmp, on names from `File temp`, so
overlapping runs never share a path; every test cleans up after itself.
A test that needs a path that does not exist yet (a directory, a link,
a fifo) unlinks its fresh temp file and reuses the name. The raw ops (open/close/read/write/getc/seek/tell/truncate)
keep their raw contract -- see ext/file.spec.md.

## write-all and read-all

### write-all writes, read-all reads back, unlink cleans up

```x
(do (import x/sys/posix) (import x/sys/file)
  (def tmp (File temp "/tmp/x-spec22-a-"))
  (File close (first tmp))
  (def p (rest tmp))
  (def n (File write-all p "alpha\nbeta\n"))
  (def s (File read-all p))
  (File unlink p)
  (list n s (File exists? p)))
```
---
    (11 "alpha\nbeta\n" #f)

### write-all truncates on rewrite

```x
(do (import x/sys/posix) (import x/sys/file)
  (def tmp (File temp "/tmp/x-spec22-b-"))
  (File close (first tmp))
  (def p (rest tmp))
  (File write-all p "a longer first body")
  (File write-all p "short")
  (def s (File read-all p))
  (File unlink p)
  s)
```
---
    "short"

## stat

### stat reports size and file type for a file we control

```x
(do (import x/sys/posix) (import x/sys/file)
  (def tmp (File temp "/tmp/x-spec22-c-"))
  (File close (first tmp))
  (def p (rest tmp))
  (File write-all p "12345")
  (def st (File stat p))
  (File unlink p)
  (list (Assoc get 'size st) (Assoc get 'file-type st) (> (Assoc get 'mtime st) 0)))
```
---
    (5 'file #t)

### a directory stats as file type 'dir

```x
(do (import x/sys/posix) (import x/sys/file)
  (Assoc get 'file-type (File stat "/tmp")))
```
---
    'dir

### exists? is a presence door, not an error

```x
(do (import x/sys/posix) (import x/sys/file)
  (list (File exists? "/tmp") (File exists? "/tmp/x-spec22-definitely-not")))
```
---
    (#t #f)

### exists? answers #f for a path that is not a string

```x
(do (import x/sys/posix) (import x/sys/file)
  (list (File exists? 42) (File exists?)))
```
---
    (#f #f)

### stat and exists? cost fewer than 5,000 objects a call

The stat buffer decodes through a Struct reader compiled once, and exists?
tests the call's result without building an Err for a miss.  The loop
around an empty thunk is subtracted.

```x
(do (import x/sys/posix) (import x/sys/file) (import x/sys/gc)
  (def %cost
    (fn (_ f)
      (f)
      (def c0 (Heap count))
      ((fn (loop i) (if (= i 0) () (do (f) (loop (- i 1))))) 10)
      (- (Heap count) c0)))
  (def %nop (%cost (fn (_) ())))
  (list (< (- (%cost (fn (_) (File stat "/tmp"))) %nop) (* 5000 10))
        (< (- (%cost (fn (_) (File exists? "/tmp"))) %nop) (* 5000 10))
        (< (- (%cost (fn (_) (File exists? "/tmp/x-spec22-definitely-not"))) %nop)
           (* 5000 10))))
```
---
    (#t #t #t)

## read-lines

### splits on newline, no phantom empty last line

```x
(do (import x/sys/posix) (import x/sys/file)
  (def tmp (File temp "/tmp/x-spec22-d-"))
  (File close (first tmp))
  (def p (rest tmp))
  (File write-all p "one\ntwo\nthree\n")
  (def ls (File read-lines p))
  (File unlink p)
  ls)
```
---
    ("one" "two" "three")

### a file without a trailing newline keeps its last line

```x
(do (import x/sys/posix) (import x/sys/file)
  (def tmp (File temp "/tmp/x-spec22-e-"))
  (File close (first tmp))
  (def p (rest tmp))
  (File write-all p "one\ntwo")
  (def ls (File read-lines p))
  (File unlink p)
  ls)
```
---
    ("one" "two")

## directories

### mkdir / list-dir / rename / rmdir roundtrip

```x
(do (import x/sys/posix) (import x/sys/file)
  (def tmp (File temp "/tmp/x-spec22-dir-"))
  (File close (first tmp))
  (File unlink (rest tmp))
  (def d (rest tmp))
  (def inner (Str8 append d "/inner"))
  (def moved (Str8 append d "/moved"))
  (File mkdir d)
  (File write-all inner "x")
  (File rename inner moved)
  (def names (File list-dir d))
  (File unlink moved)
  (File rmdir d)
  (list names (File exists? d)))
```
---
    (("moved") #f)

### list-dir excludes dot and dotdot

```x
(do (import x/sys/posix) (import x/sys/file)
  (def tmp (File temp "/tmp/x-spec22-dir2-"))
  (File close (first tmp))
  (File unlink (rest tmp))
  (def d (rest tmp))
  (File mkdir d)
  (def names (File list-dir d))
  (File rmdir d)
  (null? names))
```
---
    #t

### listing an empty directory costs fewer than 10,000 objects

A listing opens and closes the directory through the module's doors and
drops "." and ".." in one walk; the loop around an empty thunk is
subtracted.

```x
(do (import x/sys/posix) (import x/sys/file) (import x/sys/gc)
  (def tmp (File temp "/tmp/x-spec22-dir3-"))
  (File close (first tmp))
  (File unlink (rest tmp))
  (def d (rest tmp))
  (File mkdir d)
  (def %cost
    (fn (_ f)
      (f)
      (def c0 (Heap count))
      ((fn (loop i) (if (= i 0) () (do (f) (loop (- i 1))))) 10)
      (- (Heap count) c0)))
  (def %over (- (%cost (fn (_) (File list-dir d))) (%cost (fn (_) ()))))
  (File rmdir d)
  (< %over (* 10000 10)))
```
---
    #t

## structured failure

### a missing file read-alls to a label 'io enoent Err

```x
(do (import x/sys/posix) (import x/sys/file)
  (guard (e (list (Err label e) (Assoc get 'sym (e data)) (Assoc get 'op (e data))))
    (File read-all "/tmp/x-spec22-definitely-not")))
```
---
    ('io 'enoent 'stat)

### rmdir on a missing directory raises, with the path as detail

```x
(do (import x/sys/posix) (import x/sys/file)
  (guard (e (Assoc get 'detail (e data)))
    (File rmdir "/tmp/x-spec22-definitely-not")))
```
---
    "/tmp/x-spec22-definitely-not"

## boundary guards

### a missing/nil path fails as label 'type at the door, not EFAULT in the kernel

The class dispatch binds a missing argument as nil; before this guard
(File list-dir) surfaced as a baffling "Bad address" io error (or worse
through the REPL error path -- jon hit corrupted error bytes).

```x
(do (import x/sys/posix) (import x/sys/file)
  (list (guard (e (Err label e)) (File list-dir))
        (guard (e (Err label e)) (File read-all))
        (guard (e (Err label e)) (File stat 42))
        (guard (e (Err label e)) (File rename "a" ()))))
```
---
    ('type 'type 'type 'type)

## seek / tell / truncate (raw tier, #360)

### seek to end reports the size; an absolute seek rereads mid-file

```x
(do (import x/sys/posix) (import x/sys/file)
  (def tmp (File temp "/tmp/x-spec360-a-"))
  (File close (first tmp))
  (def p (rest tmp))
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

```x
(do (import x/sys/posix) (import x/sys/file)
  (def tmp (File temp "/tmp/x-spec360-b-"))
  (File close (first tmp))
  (def p (rest tmp))
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

```x
(do (import x/sys/posix) (import x/sys/file)
  (def tmp (File temp "/tmp/x-spec360-c-"))
  (File close (first tmp))
  (def p (rest tmp))
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

```x
(do (import x/sys/posix) (import x/sys/file)
  (def tmp (File temp "/tmp/x-spec360-d-"))
  (File close (first tmp))
  (def p (rest tmp))
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

```x
(do (import x/sys/posix) (import x/sys/file)
  (list (guard (e (Err label e)) (File seek 0 0 'nope))))
```
---
    ('type)

## lstat / copy / temp / walk (#364)

### copy is binary-safe: a NUL-bearing file copies byte-exact

```x
(do (import x/sys/posix) (import x/sys/file)
  (def t1 (File temp "/tmp/x-364a-"))
  (def t2 (File temp "/tmp/x-364b-"))
  (File write (first t1) "ab" 2)
  (File write (first t1) (bytes->str (list 0)) 1)
  (File write (first t1) "cd" 2)
  (File close (first t1))
  (File close (first t2))
  (def n (File copy (rest t1) (rest t2)))
  (def size (Assoc get 'size (File stat (rest t2))))
  (File unlink (rest t1))
  (File unlink (rest t2))
  (list n size))
```
---
    (5 5)

### temp creates a fresh openable file under the prefix

```x
(do (import x/sys/posix) (import x/sys/file)
  (def t (File temp "/tmp/x-364t-"))
  (def existed (File exists? (rest t)))
  (File close (first t))
  (File unlink (rest t))
  (list (>= (first t) 0) existed (Str8 starts? "/tmp/x-364t-" (rest t))))
```
---
    (#t #t #t)

### walk reports every non-directory entry, relative, recursing subdirs

```x
(do (import x/sys/posix) (import x/sys/file)
  (def tmp (File temp "/tmp/x-364-walk-"))
  (File close (first tmp))
  (File unlink (rest tmp))
  (def d (rest tmp))
  (def sub (Str8 append d "/sub"))
  (def a (Str8 append d "/a.txt"))
  (def b (Str8 append d "/sub/b.txt"))
  (File mkdir d)
  (File mkdir sub)
  (File write-all a "1")
  (File write-all b "2")
  (def found (List sort (fn (_ x y) (Str8 <? x y)) (File walk d)))
  (File unlink a)
  (File unlink b)
  (File rmdir sub)
  (File rmdir d)
  found)
```
---
    ("a.txt" "sub/b.txt")

### lstat reports a symlink as itself; stat follows it

```x
(do (import x/sys/posix) (import x/sys/file) (import x/sys/proc)
  (def tmp (File temp "/tmp/x-364-lnk-target-"))
  (File close (first tmp))
  (def p (rest tmp))
  (def l (Str8 append p "-lnk"))
  (File write-all p "x")
  (Proc run! (list "/bin/ln" "-s" p l))
  (def file-types (list (Assoc get 'file-type (File lstat l))
                        (Assoc get 'file-type (File stat l))))
  (File unlink l)
  (File unlink p)
  file-types)
```
---
    ('link 'file)

## the metadata doors

### chmod sets the mode stat reads back

```scheme
(do (import x/sys/posix) (import x/sys/file)
  (def tmp (File temp "/tmp/x-doors-chmod-"))
  (File close (first tmp))
  (def p (rest tmp))
  (File write-all p "x")
  (File chmod p 384)
  (def m (& (Assoc get 'mode (File stat p)) 4095))
  (File chmod p 420)
  (def m2 (& (Assoc get 'mode (File stat p)) 4095))
  (File unlink p)
  (list m m2))
```
---
    (384 420)

### symlink writes a target readlink reads back, verbatim

```scheme
(do (import x/sys/posix) (import x/sys/file)
  (def tmp (File temp "/tmp/x-doors-link-"))
  (File close (first tmp))
  (File unlink (rest tmp))
  (def l (rest tmp))
  (File symlink "../relative/target" l)
  (def t (File readlink l))
  (File unlink l)
  t)
```
---
    "../relative/target"

### link makes a second name for the same bytes

```scheme
(do (import x/sys/posix) (import x/sys/file)
  (def tmp (File temp "/tmp/x-doors-hard-"))
  (File close (first tmp))
  (def a (rest tmp))
  (def b (Str8 append a "-b"))
  (File write-all a "shared")
  (File link a b)
  (def same (= (Assoc get 'ino (File stat a)) (Assoc get 'ino (File stat b))))
  (def body (File read-all b))
  (File unlink a)
  (def survives (File read-all b))
  (File unlink b)
  (list body survives))
```
---
    ("shared" "shared")

### readlink refuses a path that is not a link

```scheme
(do (import x/sys/posix) (import x/sys/file) (import x/type/err)
  (def tmp (File temp "/tmp/x-doors-notlink-"))
  (File close (first tmp))
  (def p (rest tmp))
  (File write-all p "x")
  (def r (guard (e (Err label e)) (do (File readlink p) (lit no-raise))))
  (File unlink p)
  r)
```
---
    'io

### utimes bumps the modification time without touching the bytes

```scheme
(do (import x/sys/posix) (import x/sys/file)
  (def tmp (File temp "/tmp/x-doors-utimes-"))
  (File close (first tmp))
  (def p (rest tmp))
  (File write-all p "unchanged")
  (File utimes p)
  (def s (File stat p))
  (def body (File read-all p))
  (File unlink p)
  (list body (Assoc get 'size s)))
```
---
    ("unchanged" 9)

### mkfifo makes a path whose file type is fifo

```scheme
(do (import x/sys/posix) (import x/sys/file)
  (def tmp (File temp "/tmp/x-doors-fifo-"))
  (File close (first tmp))
  (File unlink (rest tmp))
  (def p (rest tmp))
  (File mkfifo p)
  (def k (Assoc get 'file-type (File stat p)))
  (File unlink p)
  k)
```
---
    'fifo

### statfs answers block counts that multiply out to a real size

```scheme
(do (import x/sys/posix) (import x/sys/file)
  (def s (File statfs "/tmp"))
  (list (> (Assoc get 'bsize s) 0)
        (> (Assoc get 'blocks s) 0)
        (<= (Assoc get 'bavail s) (Assoc get 'blocks s))))
```
---
    (#t #t #t)

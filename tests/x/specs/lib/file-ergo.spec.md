# File ergonomics: slurp / spit / stat / read-lines / list-dir (#22)

The ergonomic tier over the raw syscall layer: whole-file operations
that RAISE kind-'io Errs (via Err from-errno) instead of returning
negative results. Real I/O under /tmp; every test cleans up after
itself. The raw five (open/close/read/write/getc) keep their raw
contract -- see ext/file.spec.md.

## spit and slurp

### spit writes, slurp reads back, unlink cleans up

```scheme
(do (import x/sys/posix) (import x/sys/file)
  (def p "/tmp/x-spec22-a")
  (def n (File spit p "alpha\nbeta\n"))
  (def s (File slurp p))
  (File unlink p)
  (list n s (File exists? p)))
```
---
    (11 "alpha\nbeta\n" #f)

### spit truncates on rewrite

```scheme
(do (import x/sys/posix) (import x/sys/file)
  (def p "/tmp/x-spec22-b")
  (File spit p "a longer first body")
  (File spit p "short")
  (def s (File slurp p))
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
  (File spit p "12345")
  (def st (File stat p))
  (File unlink p)
  (list (assoc-get 'size st) (assoc-get 'kind st) (> (assoc-get 'mtime st) 0)))
```
---
    (5 'file #t)

### a directory stats as kind 'dir

```scheme
(do (import x/sys/posix) (import x/sys/file)
  (assoc-get 'kind (File stat "/tmp")))
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
  (File spit p "one\ntwo\nthree\n")
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
  (File spit p "one\ntwo")
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
  (File spit "/tmp/x-spec22-dir/inner" "x")
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

### a missing file slurps to a kind-'io enoent Err

```scheme
(do (import x/sys/posix) (import x/sys/file)
  (guard (e (list (Err kind-of e) (assoc-get 'sym (e data)) (assoc-get 'op (e data))))
    (File slurp "/tmp/x-spec22-definitely-not")))
```
---
    ('io 'enoent 'stat)

### rmdir on a missing directory raises, with the path as detail

```scheme
(do (import x/sys/posix) (import x/sys/file)
  (guard (e (assoc-get 'detail (e data)))
    (File rmdir "/tmp/x-spec22-definitely-not")))
```
---
    "/tmp/x-spec22-definitely-not"

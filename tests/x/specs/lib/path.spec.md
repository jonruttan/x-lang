# Path: pure-string pathname manipulation (#22)
# @weight 2

No filesystem access -- every method is a total string function.

## join

### seams get exactly one slash

```x
(do (import x/type/path)
  (list (Path join "a" "b") (Path join "a/" "b") (Path join "a" "/b") (Path join "a/" "/b")))
```
---
    ("a/b" "a/b" "a/b" "a/b")

### empty components vanish, absolute roots survive

```x
(do (import x/type/path)
  (list (Path join "a" "" "b") (Path join "/root" "etc") (Path join "" "rel")))
```
---
    ("a/b" "/root/etc" "rel")

## dirname / basename

### the usual splits

```x
(do (import x/type/path)
  (list (Path dirname "/a/b/c.txt") (Path basename "/a/b/c.txt")))
```
---
    ("/a/b" "c.txt")

### no slash means dot; root-level means root

```x
(do (import x/type/path)
  (list (Path dirname "c.txt") (Path dirname "/etc")))
```
---
    ("." "/")

### trailing slashes strip before splitting

```x
(do (import x/type/path)
  (list (Path dirname "/a/b/") (Path basename "/a/b/")))
```
---
    ("/a" "b")

### the root itself

```x
(do (import x/type/path)
  (list (Path dirname "/") (Path basename "/")))
```
---
    ("/" "/")

## ext

### extension without its dot

```x
(do (import x/type/path)
  (list (Path ext "a/b.tar.gz") (Path ext "x.txt")))
```
---
    ("gz" "txt")

### absence is nil: no dot, dotfile, trailing dot

```x
(do (import x/type/path)
  (list (null? (Path ext "Makefile")) (null? (Path ext ".bashrc")) (null? (Path ext "x."))))
```
---
    (#t #t #t)

## split and absolute?

### components, empties dropped

```x
(do (import x/type/path)
  (list (Path split "/a/b/c") (Path split "a//b/") (Path split "/")))
```
---
    (("a" "b" "c") ("a" "b") ())

### absolute? checks the leading slash

```x
(do (import x/type/path)
  (list (Path absolute? "/etc") (Path absolute? "etc") (Path absolute? "")))
```
---
    (#t #f #f)

## Path norm

### dot and empty components drop, dot-dot consumes

```x
(do (import x/type/path)
  (display (Path norm "a/./b//c"))
  (display " ")
  (display (Path norm "a/b/../c")))
```
---
    a/b/c a/c

### leading dot-dots survive for the caller to judge

```x
(do (import x/type/path)
  (display (Path norm "../a"))
  (display " ")
  (display (Path norm "a/../../b")))
```
---
    ../a ../b

### collapse to current dir or root

```x
(do (import x/type/path)
  (display (Path norm "a/.."))
  (display " ")
  (display (Path norm "/a/../..")))
```
---
    . /

## Path strip-ext

### strips one extension from the basename, keeps the directory

```x
(do (import x/type/path)
  (display (Path strip-ext "a/b.x"))
  (display " ")
  (display (Path strip-ext "a.tar.gz"))
  (display " ")
  (display (Path strip-ext "Makefile")))
```
---
    a/b a.tar Makefile

## relpath (#364)

### common prefix drops; climbs become ..

```x
(do (import x/type/path)
  (list (Path relpath "/a/b" "/a/c/d")
        (Path relpath "a/b" "a/b")
        (Path relpath "/a" "/a/b")
        (Path relpath "/a/b/c" "/")))
```
---
    ("../c/d" "." "b" "../../..")

### mixing absolute and relative raises 'value

```x
(do (import x/type/path)
  (list (guard (e (Err kind-of e)) (Path relpath "/a" "b"))))
```
---
    ('value)

## match? (#364)

### segment-aware: * stays inside a segment, ** crosses

```x
(do (import x/type/path)
  (list (Path match? "*.x" "file.x")
        (Path match? "*.x" "dir/file.x")
        (Path match? "lib/**/*.x" "lib/a/b.x")
        (Path match? "lib/**/*.x" "lib/b.x")
        (Path match? "lib/**" "lib")
        (Path match? "a?c" "abc")
        (Path match? "a?c" "ac")))
```
---
    (#t #f #t #t #t #t #f)

# Path: pure-string pathname manipulation (#22)

No filesystem access -- every method is a total string function.

## join

### seams get exactly one slash

```scheme
(do (import x/type/path)
  (list (Path join "a" "b") (Path join "a/" "b") (Path join "a" "/b") (Path join "a/" "/b")))
```
---
    ("a/b" "a/b" "a/b" "a/b")

### empty components vanish, absolute roots survive

```scheme
(do (import x/type/path)
  (list (Path join "a" "" "b") (Path join "/root" "etc") (Path join "" "rel")))
```
---
    ("a/b" "/root/etc" "rel")

## dirname / basename

### the usual splits

```scheme
(do (import x/type/path)
  (list (Path dirname "/a/b/c.txt") (Path basename "/a/b/c.txt")))
```
---
    ("/a/b" "c.txt")

### no slash means dot; root-level means root

```scheme
(do (import x/type/path)
  (list (Path dirname "c.txt") (Path dirname "/etc")))
```
---
    ("." "/")

### trailing slashes strip before splitting

```scheme
(do (import x/type/path)
  (list (Path dirname "/a/b/") (Path basename "/a/b/")))
```
---
    ("/a" "b")

### the root itself

```scheme
(do (import x/type/path)
  (list (Path dirname "/") (Path basename "/")))
```
---
    ("/" "/")

## ext

### extension without its dot

```scheme
(do (import x/type/path)
  (list (Path ext "a/b.tar.gz") (Path ext "x.txt")))
```
---
    ("gz" "txt")

### absence is nil: no dot, dotfile, trailing dot

```scheme
(do (import x/type/path)
  (list (null? (Path ext "Makefile")) (null? (Path ext ".bashrc")) (null? (Path ext "x."))))
```
---
    (#t #t #t)

## split and absolute?

### components, empties dropped

```scheme
(do (import x/type/path)
  (list (Path split "/a/b/c") (Path split "a//b/") (Path split "/")))
```
---
    (("a" "b" "c") ("a" "b") ())

### absolute? checks the leading slash

```scheme
(do (import x/type/path)
  (list (Path absolute? "/etc") (Path absolute? "etc") (Path absolute? "")))
```
---
    (#t #f #f)

# @lib ../tests/x/lib/compile.x

## compile-cc-flags

### is a list

```scheme
(pair? compile-cc-flags)
```
---
    #t

## compile-ext

### is a string

```scheme
(string? compile-ext)
```
---
    #t

### is a known extension

```scheme
(or (string=? compile-ext ".so") (string=? compile-ext ".dylib") (string=? compile-ext ".bundle"))
```
---
    #t

## compile-emitters

### is a list

```scheme
(pair? compile-emitters)
```
---
    #t

### has entries

```scheme
(> (length compile-emitters) 10)
```
---
    #t

## compile-add-emitter!

### adds an emitter

```scheme
(do (def before (length compile-emitters))
    (compile-add-emitter! (lit test-emit-42) (fn (_ args) (display "42")))
    (def after (length compile-emitters))
    (> after before))
```
---
    #t

## compile-to-c

### generates C source string

```scheme
(string? (compile-to-c (lit (fn (_ n) n)) ()))
```
---
    #t

### includes x-obj.h header

```scheme
(string-contains? "x-obj.h" (compile-to-c (lit (fn (_ n) n)) ()))
```
---
    #t

### generates function body

```scheme
(string-contains? "fn_0" (compile-to-c (lit (fn (_ n) n)) ()))
```
---
    #t

## compile-write

### writes string to file

```scheme
(do (compile-write "/tmp/x-test-write.txt" "hello")
    (file-exists? "/tmp/x-test-write.txt"))
```
---
    #t

## compile-with-writers

### executes body with writers pushed

```scheme
(string? (compile-with-writers (fn (_) (write-to-string 42))))
```
---
    #t

# @lib ../tests/x/lib/compile.x

# @weight 8
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
(str? compile-ext)
```
---
    #t

### is a known extension

```scheme
(or (str=? compile-ext ".so") (str=? compile-ext ".dylib") (str=? compile-ext ".bundle"))
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
(> (List length compile-emitters) 10)
```
---
    #t

## compile-add-emitter!

### adds an emitter

```scheme
(do (def before (List length compile-emitters))
    (compile-add-emitter! 'test-emit-42 (fn (_ args) (display "42")))
    (def after (List length compile-emitters))
    (> after before))
```
---
    #t

## compile-to-c

### generates C source string

```scheme
(str? (compile-to-c (lit (fn (_ n) n)) ()))
```
---
    #t

### includes x-obj.h header

```scheme
(Str includes? "x-obj.h" (compile-to-c (lit (fn (_ n) n)) ()))
```
---
    #t

### generates function body

```scheme
(Str includes? "fn_0" (compile-to-c (lit (fn (_ n) n)) ()))
```
---
    #t

## compile-write

### writes string to file

```scheme
(do (compile-write "/tmp/x-test-write.txt" "hello")
    (Sys file-exists? "/tmp/x-test-write.txt"))
```
---
    #t

## compile-with-writers

### executes body with writers pushed

```scheme
(str? (compile-with-writers (fn (_) (Io write-to-str 42))))
```
---
    #t

## compile-cache-identity

The cache holds NATIVE OBJECTS, so its key has to carry everything that
changes what those objects mean. The triple alone does not: a bundle is
compiled against one ENGINE's headers -- struct layouts, prim ABI -- and a
key blind to the engine serves an ABI-stale object to every later engine on
the machine. That is #590, and it failed silently: tower analysers built
against an older engine read `2.5` as the int `2` followed by the symbol
`.5`, with no error raised anywhere.

### carries the build triple and the engine release, in that order

Asserting the exact composition, not merely that it is non-empty: this is
the property that keeps a new engine MISSING the old entries instead of
hitting them, so it has to fail if either half is ever dropped.

```scheme
(str=? %compile-cache-identity (Str append x-machine x-release))
```
---
    #t

### the key is a function of the identity, not of the expression alone

Two engines differing only in release must not agree on a key. The identity
is the whole of the non-expression half, so hashing it with the expression
is what partitions the cache.

```scheme
(do (def %k (%compile-cache-key "expr"))
    (and (str? %k)
         (not (str=? %k (Hash ->hex (Hash fnv-1a (Str append x-machine "expr")))))))
```
---
    #t

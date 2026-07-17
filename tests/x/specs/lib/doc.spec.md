# Documentation discovery (apropos / help)

These pin the argument-handling fixes; they assert the calls complete without
error (a bare-symbol `apropos`/`help` used to raise "Unbound SYMBOL"), not the
exact rendered doc text.

## apropos

### accepts a bare symbol

```scheme
(do (apropos upcase) #t)
```
---
    #t

### accepts a string

```scheme
(do (apropos "upcase") #t)
```
---
    #t

### accepts a quoted symbol

```scheme
(do (apropos (lit gcd)) #t)
```
---
    #t

### no matches is not an error

```scheme
(do (apropos "zzzznotamethod") #t)
```
---
    #t

## help

### a bare method name resolves to matching methods rather than erroring

```scheme
(do (help upcase) #t)
```
---
    #t

### a genuinely unknown name still completes

```scheme
(do (help totallyunknownxyz) #t)
```
---
    #t

## provide registration

### the List class module is registered

```scheme
(null? (%module-find (lit x/type/list)))
```
---
    #f

### boot modules register retroactively

```scheme
(null? (%module-find (lit x/boot/module)))
```
---
    #f

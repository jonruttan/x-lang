# Documentation discovery (apropos / help)
# @weight 1

These pin the argument-handling fixes; they assert the calls complete without
error (a bare-symbol `apropos`/`help` used to raise "Unbound SYMBOL"), not the
exact rendered doc text.

## apropos

### accepts a bare symbol

```x
(do (apropos upcase) #t)
```
---
    #t

### accepts a string

```x
(do (apropos "upcase") #t)
```
---
    #t

### accepts a quoted symbol

```x
(do (apropos 'gcd) #t)
```
---
    #t

### no matches is not an error

```x
(do (apropos "zzzznotamethod") #t)
```
---
    #t

## help

### a bare method name resolves to matching methods rather than erroring

```x
(do (help upcase) #t)
```
---
    #t

### a genuinely unknown name still completes

```x
(do (help totallyunknownxyz) #t)
```
---
    #t

## provide registration

### the List class module is registered

```x
(null? (%module-find 'x/type/list))
```
---
    #f

### boot modules register retroactively

```x
(null? (%module-find 'x/boot/module))
```
---
    #f

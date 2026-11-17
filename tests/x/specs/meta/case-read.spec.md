# Harness: a snippet is read one form at a time
# @weight 1

The runner reads each form of a snippet after the form before it has run,
so a form that changes the reader changes how the rest of the snippet
reads. See `tests/spec-runner.awk`.

## reading

### a float literal reads in the snippet whose import loads the float reader

```x
(import x/num/float)
(write (list 1.96 -2.5))
```
---
    (1.96 -2.5)

### the last form's value is the snippet's value

```x
(def case-read-a 1)
(def case-read-b 2)
(+ case-read-a case-read-b)
```
---
    3

### a definition carries into the next snippet

```x
(+ case-read-a 10)
```
---
    11

### a trailing comment does not swallow the end of the snippet

```x
(+ 1 2) ; three
```
---
    3

## errors

### an error stops the snippet and skips its remaining forms

```x
(def case-read-c 1)
(car 1)
(def case-read-c 2)
```
---
    Error: Unbound SYMBOL 'car'

### the next snippet runs after an error

```x
case-read-c
```
---
    1

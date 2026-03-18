# Promises

## promise?

### delay creates a promise

```x
(promise? (delay 42))
```
---
    #t

### non-promise values

```x
(list (promise? 42) (promise? "hello") (promise? (fn (x) x)))
```
---
    (#f #f #f)

## force

### force evaluates delayed expression

```x
(force (delay (+ 1 2)))
```
---
    3

### force on non-promise returns value

```x
(force 42)
```
---
    42

### force on list returns list

```x
(force (list 1 2 3))
```
---
    (1 2 3)

## memoization

### delay body executes only once

```x
(def count 0)
(def p (delay (do (set count (+ count 1)) count)))
(list (force p) (force p) count)
```
---
    (1 1 1)

### many forces same promise

```x
(let ((count 0))
  (let ((p (delay (do (set count (+ count 1)) count))))
    (let loop ((i 0))
      (if (= i 100)
        (list (force p) count)
        (do (force p) (loop (+ i 1)))))))
```
---
    (1 1)

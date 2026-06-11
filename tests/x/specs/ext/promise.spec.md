# Promises

## promise?

### delay creates a promise

```x
(Promise promise? (delay 42))
```
---
    #t

### non-promise values

```x
(list (Promise promise? 42) (Promise promise? "hello") (Promise promise? (fn (_ x) x)))
```
---
    (#f #f #f)

## force

### force evaluates delayed expression

```x
(Promise force (delay (+ 1 2)))
```
---
    3

### force on non-promise returns value

```x
(Promise force 42)
```
---
    42

### force on list returns list

```x
(Promise force (list 1 2 3))
```
---
    (1 2 3)

## memoization

### delay body executes only once

```x
(def count 0)
(def p (delay (do (set! count (+ count 1)) count)))
(list (Promise force p) (Promise force p) count)
```
---
    (1 1 1)

### many forces same promise

```x
(let ((count 0))
  (let ((p (delay (do (set! count (+ count 1)) count))))
    (let loop ((i 0))
      (if (= i 100)
        (list (Promise force p) count)
        (do (Promise force p) (loop (+ i 1)))))))
```
---
    (1 1)

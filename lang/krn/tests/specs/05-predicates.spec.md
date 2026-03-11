## Kernel predicates

### operative?

```scheme
(operative? ($vau (x) e x))
```
---
    t

### operative? false on applicative

```scheme
(null? (operative? ($lambda (x) x)))
```
---
    t

### applicative?

```scheme
(applicative? ($lambda (x) x))
```
---
    t

### applicative? false on number

```scheme
(null? (applicative? 42))
```
---
    t

### boolean? on #t

```scheme
(boolean? #t)
```
---
    t

### boolean? on #f

```scheme
(boolean? #f)
```
---
    t

### boolean? false

```scheme
(null? (boolean? 42))
```
---
    t

### inert? on #inert

```scheme
(inert? #inert)
```
---
    t

## number predicates

### zero?

```scheme
(zero? 0)
```
---
    t

### zero? false

```scheme
(null? (zero? 1))
```
---
    t

### positive?

```scheme
(positive? 5)
```
---
    t

### negative?

```scheme
(negative? (- 0 3))
```
---
    t

### even?

```scheme
(even? 4)
```
---
    t

### even? false

```scheme
(null? (even? 3))
```
---
    t

### odd?

```scheme
(odd? 3)
```
---
    t

### odd? false

```scheme
(null? (odd? 4))
```
---
    t

## numeric operations

### abs positive

```scheme
(abs 5)
```
---
    5

### abs negative

```scheme
(abs (- 0 5))
```
---
    5

### min

```scheme
(min 3 7)
```
---
    3

### max

```scheme
(max 3 7)
```
---
    7


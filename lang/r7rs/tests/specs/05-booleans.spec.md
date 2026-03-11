## boolean?

### boolean? on true

```scheme
(boolean? #t)
```
---
    t

### boolean? on false

```scheme
(boolean? #f)
```
---
    t

### boolean? on number

```scheme
(null? (boolean? 0))
```
---
    t

### boolean? on string

```scheme
(null? (boolean? ""))
```
---
    t

### boolean? on nil

```scheme
(boolean? ())
```
---
    t

## not

### not true

```scheme
(null? (not #t))
```
---
    t

### not false

```scheme
(not #f)
```
---
    t

### not 3

```scheme
(null? (not 3))
```
---
    t

### not nil

```scheme
(not ())
```
---
    t

## boolean=?

### boolean=? both true

```scheme
(boolean=? #t #t)
```
---
    t

### boolean=? both false

```scheme
(boolean=? #f #f)
```
---
    t

### boolean=? true false

```scheme
(null? (boolean=? #t #f))
```
---
    t

### boolean=? false true

```scheme
(null? (boolean=? #f #t))
```
---
    t


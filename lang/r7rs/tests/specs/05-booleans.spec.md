## boolean?

### boolean? on true

```scheme
(boolean? #t)
```
---
    #t

### boolean? on false

```scheme
(boolean? #f)
```
---
    #t

### boolean? on number

```scheme
(not (boolean? 0))
```
---
    #t

### boolean? on string

```scheme
(not (boolean? ""))
```
---
    #t

### boolean? on nil

```scheme
(not (boolean? ()))
```
---
    #t

## not

### not true

```scheme
(not (not #t))
```
---
    #t

### not false

```scheme
(not #f)
```
---
    #t

### not 3

```scheme
(not (not 3))
```
---
    #t

### not nil

```scheme
(not ())
```
---
    #t

## boolean=?

### boolean=? both true

```scheme
(boolean=? #t #t)
```
---
    #t

### boolean=? both false

```scheme
(boolean=? #f #f)
```
---
    #t

### boolean=? true false

```scheme
(not (boolean=? #t #f))
```
---
    #t

### boolean=? false true

```scheme
(not (boolean=? #f #t))
```
---
    #t


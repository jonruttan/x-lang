## composition accessors

### caar

```scheme
(caar (list (list 1 2) (list 3 4)))
```
---
    1

### cadr

```scheme
(cadr (list 1 2 3))
```
---
    2

### cdar

```scheme
(cdar (list (list 1 2) 3))
```
---
    (2)

### cddr

```scheme
(cddr (list 1 2 3))
```
---
    (3)

### caddr

```scheme
(caddr (list 1 2 3))
```
---
    3

## convenience aliases

### second returns cadr

```scheme
(second (list 10 20 30))
```
---
    20

### third returns caddr

```scheme
(third (list 10 20 30))
```
---
    30

### else is true

```scheme
(if else 1 0)
```
---
    1

## I/O constants

### stdin is 0

```scheme
stdin
```
---
    0

### stdout is 1

```scheme
stdout
```
---
    1

### stderr is 2

```scheme
stderr
```
---
    2

## character constants

### newline character

```scheme
(= (char->integer (#newline 0)) 10)
```
---
    #t

### cr character

```scheme
(= (char->integer (#cr 0)) 13)
```
---
    #t

## compatibility aliases

### list-ref gets nth element

```scheme
(list-ref (list 10 20 30 40) 2)
```
---
    30

### list-tail drops first n

```scheme
(list-tail (list 10 20 30 40) 2)
```
---
    (30 40)

### string-copy

```scheme
(string-copy "hello")
```
---
    "hello"

## derived forms from x-lang

### when executes body when true

```scheme
(def x 0) (when #t (set! x 42)) x
```
---
    42

### when skips body when false

```scheme
(def x 0) (when #f (set! x 42)) x
```
---
    0

### unless executes body when false

```scheme
(def x 0) (unless #f (set! x 42)) x
```
---
    42

### let* sequential binding

```scheme
(let* ((x 1) (y (+ x 1))) (+ x y))
```
---
    3

### letrec mutual recursion

```scheme
(letrec ((even? (fn (n) (if (= n 0) #t (odd? (- n 1))))) (odd? (fn (n) (if (= n 0) #f (even? (- n 1)))))) (even? 10))
```
---
    #t

### named let loop

```scheme
(let loop ((i 0) (acc 0)) (if (= i 5) acc (loop (+ i 1) (+ acc i))))
```
---
    10

### case matches literal

```scheme
(case 2 ((1) 10) ((2) 20) ((3) 30))
```
---
    20

### case matches else clause

```scheme
(case 99 ((1) 10) (else 0))
```
---
    0

### member finds element

```scheme
(member 3 (list 1 2 3 4 5))
```
---
    (3 4 5)

### member returns false when not found

```scheme
(if (member 6 (list 1 2 3)) 1 0)
```
---
    0

### assoc finds key

```scheme
(assoc 2 (list (list 1 10) (list 2 20) (list 3 30)))
```
---
    (2 20)

### assoc returns false when not found

```scheme
(if (assoc 4 (list (list 1 10) (list 2 20))) 1 0)
```
---
    0

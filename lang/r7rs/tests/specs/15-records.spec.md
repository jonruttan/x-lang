## define-record-type basics

### define-record-type returns name

```scheme
(define-record-type <point> (make-point x y) point? (x point-x) (y point-y))
```
---
    <point>

### constructor creates record

```scheme
(define-record-type <point> (make-point x y) point? (x point-x) (y point-y)) (point? (make-point 1 2))
```
---
    #t

### predicate true for record

```scheme
(define-record-type <box> (make-box val) box? (val box-val)) (box? (make-box 42))
```
---
    #t

### predicate false for non-record

```scheme
(define-record-type <box> (make-box val) box? (val box-val)) (not (box? 42))
```
---
    #t

### predicate false for list

```scheme
(define-record-type <box> (make-box val) box? (val box-val)) (not (box? (list 1 2)))
```
---
    #t

## record accessors

### access first field

```scheme
(define-record-type <point> (make-point x y) point? (x point-x) (y point-y)) (point-x (make-point 3 4))
```
---
    3

### access second field

```scheme
(define-record-type <point> (make-point x y) point? (x point-x) (y point-y)) (point-y (make-point 3 4))
```
---
    4

### access single field

```scheme
(define-record-type <box> (make-box val) box? (val box-val)) (box-val (make-box 99))
```
---
    99

### fields with string values

```scheme
(define-record-type <person> (make-person name age) person? (name person-name) (age person-age)) (person-name (make-person "Alice" 30))
```
---
    "Alice"

### fields with list values

```scheme
(define-record-type <box> (make-box val) box? (val box-val)) (box-val (make-box (list 1 2 3)))
```
---
    (1 2 3)

## record patterns

### multiple records independent

```scheme
(define-record-type <point> (make-point x y) point? (x point-x) (y point-y)) (define-record-type <color> (make-color r g b) color? (r color-r) (g color-g) (b color-b)) (list (point-x (make-point 1 2)) (color-r (make-color 255 0 0)))
```
---
    (1 255)

### record in variable

```scheme
(define-record-type <box> (make-box val) box? (val box-val)) (define b (make-box 42)) (box-val b)
```
---
    42

### record with three fields

```scheme
(define-record-type <vec3> (make-vec3 x y z) vec3? (x vec3-x) (y vec3-y) (z vec3-z)) (define v (make-vec3 1 2 3)) (list (vec3-x v) (vec3-y v) (vec3-z v))
```
---
    (1 2 3)


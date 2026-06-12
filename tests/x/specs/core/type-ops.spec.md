# Generic-operator dispatch (type ops group)

## int fast path

### int arithmetic is unchanged

```scheme
(+ 2 3)
```
---
    5

### int comparison is unchanged

```scheme
(< 2 3)
```
---
    #t

## typed-operand dispatch

### a typed operand dispatches + to its type's handler

```scheme
(do
  (def %t (make-type "OPSPEC" (list)))
  (def %ts (Type by-atom %t))
  (Type push-op %ts (lit +) (fn (_ a b) (lit dispatched)))
  (+ (make-instance %t 1) 2))
```
---
    (lit dispatched)

### dispatch works with the typed operand on the right

```scheme
(do
  (def %t2 (make-type "OPSPEC2" (list)))
  (def %ts2 (Type by-atom %t2))
  (Type push-op %ts2 (lit +) (fn (_ a b) (lit right-dispatched)))
  (+ 2 (make-instance %t2 1)))
```
---
    (lit right-dispatched)

### the handler receives both raw operands

```scheme
(do
  (def %t6 (make-type "OPSPEC6" (list)))
  (def %ts6 (Type by-atom %t6))
  (Type push-op %ts6 (lit +) (fn (_ a b) (+ (first a) b)))
  (+ (make-instance %t6 40) 2))
```
---
    42

### a new type's ops alist starts nil (never dispatches)

```scheme
(do
  (def %t3 (make-type "OPSPEC3" (list)))
  (def %ts3 (Type by-atom %t3))
  (null? (first (Type ops-cell %ts3))))
```
---
    #t

### comparison dispatches too

```scheme
(do
  (def %t4 (make-type "OPSPEC4" (list)))
  (def %ts4 (Type by-atom %t4))
  (Type push-op %ts4 (lit <) (fn (_ a b) #t))
  (< (make-instance %t4 1) 99))
```
---
    #t

### same type on both sides dispatches its handler

```scheme
(do
  (def %t7 (make-type "OPSPEC7" (list)))
  (def %ts7 (Type by-atom %t7))
  (Type push-op %ts7 (lit +) (fn (_ a b) (lit same-type)))
  (+ (make-instance %t7 1) (make-instance %t7 2)))
```
---
    (lit same-type)

### the from-relation decides mixed types (absorber wins)

```scheme
(do
  (def %lo2 (make-type "OPSLO2" (list)))
  (def %hi2 (make-type "OPSHI2"
    (list (pair (lit from) (list (pair %lo2 (fn (_ v) v)))))))
  (def %lo2-ts (Type by-atom %lo2))
  (def %hi2-ts (Type by-atom %hi2))
  (Type push-op %lo2-ts (lit *) (fn (_ a b) (lit lo2)))
  (Type push-op %hi2-ts (lit *) (fn (_ a b) (lit hi2)))
  (* (make-instance %lo2 1) (make-instance %hi2 1)))
```
---
    (lit hi2)

### the from-relation is order-independent

```scheme
(do
  (def %lo3 (make-type "OPSLO3" (list)))
  (def %hi3 (make-type "OPSHI3"
    (list (pair (lit from) (list (pair %lo3 (fn (_ v) v)))))))
  (def %lo3-ts (Type by-atom %lo3))
  (def %hi3-ts (Type by-atom %hi3))
  (Type push-op %lo3-ts (lit *) (fn (_ a b) (lit lo3)))
  (Type push-op %hi3-ts (lit *) (fn (_ a b) (lit hi3)))
  (* (make-instance %hi3 1) (make-instance %lo3 1)))
```
---
    (lit hi3)

### eq? keeps identity semantics (never dispatches)

```scheme
(do
  (def %t5 (make-type "OPSPEC5" (list)))
  (def %ts5 (Type by-atom %t5))
  (Type push-op %ts5 (lit =) (fn (_ a b) #t))
  (def %a (make-instance %t5 1))
  (def %b (make-instance %t5 2))
  (list (= %a %b) (eq? %a %a)))
```
---
    (#t #t)

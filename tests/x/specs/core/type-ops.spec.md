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
  (def %t (Type make "OPSPEC" (list)))
  (def %ts (Type by-atom %t))
  (Type push-op %ts '+ (fn (_ a b) 'dispatched))
  (+ (Type make-instance %t 1) 2))
```
---
    'dispatched

### dispatch works with the typed operand on the right

```scheme
(do
  (def %t2 (Type make "OPSPEC2" (list)))
  (def %ts2 (Type by-atom %t2))
  (Type push-op %ts2 '+ (fn (_ a b) 'right-dispatched))
  (+ 2 (Type make-instance %t2 1)))
```
---
    'right-dispatched

### the handler receives both raw operands

```scheme
(do
  (def %t6 (Type make "OPSPEC6" (list)))
  (def %ts6 (Type by-atom %t6))
  (Type push-op %ts6 '+ (fn (_ a b) (+ (first a) b)))
  (+ (Type make-instance %t6 40) 2))
```
---
    42

### a new type's ops alist starts nil (never dispatches)

```scheme
(do
  (def %t3 (Type make "OPSPEC3" (list)))
  (def %ts3 (Type by-atom %t3))
  (null? (first (Type ops-cell %ts3))))
```
---
    #t

### comparison dispatches too

```scheme
(do
  (def %t4 (Type make "OPSPEC4" (list)))
  (def %ts4 (Type by-atom %t4))
  (Type push-op %ts4 '< (fn (_ a b) #t))
  (< (Type make-instance %t4 1) 99))
```
---
    #t

### same type on both sides dispatches its handler

```scheme
(do
  (def %t7 (Type make "OPSPEC7" (list)))
  (def %ts7 (Type by-atom %t7))
  (Type push-op %ts7 '+ (fn (_ a b) 'same-type))
  (+ (Type make-instance %t7 1) (Type make-instance %t7 2)))
```
---
    'same-type

### the from-relation decides mixed types (absorber wins)

```scheme
(do
  (def %lo2 (Type make "OPSLO2" (list)))
  (def %hi2 (Type make "OPSHI2"
    (list (pair 'from (list (pair %lo2 (fn (_ v) v)))))))
  (def %lo2-ts (Type by-atom %lo2))
  (def %hi2-ts (Type by-atom %hi2))
  (Type push-op %lo2-ts '* (fn (_ a b) 'lo2))
  (Type push-op %hi2-ts '* (fn (_ a b) 'hi2))
  (* (Type make-instance %lo2 1) (Type make-instance %hi2 1)))
```
---
    'hi2

### the from-relation is order-independent

```scheme
(do
  (def %lo3 (Type make "OPSLO3" (list)))
  (def %hi3 (Type make "OPSHI3"
    (list (pair 'from (list (pair %lo3 (fn (_ v) v)))))))
  (def %lo3-ts (Type by-atom %lo3))
  (def %hi3-ts (Type by-atom %hi3))
  (Type push-op %lo3-ts '* (fn (_ a b) 'lo3))
  (Type push-op %hi3-ts '* (fn (_ a b) 'hi3))
  (* (Type make-instance %hi3 1) (Type make-instance %lo3 1)))
```
---
    'hi3

### eq? keeps identity semantics (never dispatches)

```scheme
(do
  (def %t5 (Type make "OPSPEC5" (list)))
  (def %ts5 (Type by-atom %t5))
  (Type push-op %ts5 '= (fn (_ a b) #t))
  (def %a (Type make-instance %t5 1))
  (def %b (Type make-instance %t5 2))
  (list (= %a %b) (eq? %a %a)))
```
---
    (#t #t)

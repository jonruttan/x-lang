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
  (def %ts (type-by-atom %t))
  (type-push-op %ts (lit +) (fn (_ a b) (lit dispatched)))
  (+ (make-instance %t 1) 2))
```
---
    (lit dispatched)

### dispatch works with the typed operand on the right

```scheme
(do
  (def %t2 (make-type "OPSPEC2" (list)))
  (def %ts2 (type-by-atom %t2))
  (type-push-op %ts2 (lit +) (fn (_ a b) (lit right-dispatched)))
  (+ 2 (make-instance %t2 1)))
```
---
    (lit right-dispatched)

### the handler receives both raw operands

```scheme
(do
  (def %t6 (make-type "OPSPEC6" (list)))
  (def %ts6 (type-by-atom %t6))
  (type-push-op %ts6 (lit +) (fn (_ a b) (+ (first a) b)))
  (+ (make-instance %t6 40) 2))
```
---
    42

### a new type's ops alist starts nil (never dispatches)

```scheme
(do
  (def %t3 (make-type "OPSPEC3" (list)))
  (def %ts3 (type-by-atom %t3))
  (null? (first (type-ops-cell %ts3))))
```
---
    #t

### comparison dispatches too

```scheme
(do
  (def %t4 (make-type "OPSPEC4" (list)))
  (def %ts4 (type-by-atom %t4))
  (type-push-op %ts4 (lit <) (fn (_ a b) #t))
  (< (make-instance %t4 1) 99))
```
---
    #t

### eq? keeps identity semantics (never dispatches)

```scheme
(do
  (def %t5 (make-type "OPSPEC5" (list)))
  (def %ts5 (type-by-atom %t5))
  (type-push-op %ts5 (lit =) (fn (_ a b) #t))
  (def %a (make-instance %t5 1))
  (def %b (make-instance %t5 2))
  (list (= %a %b) (eq? %a %a)))
```
---
    (#t #t)

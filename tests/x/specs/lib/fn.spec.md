## identity

### returns its argument

```scheme
(Fn identity 42)
```
---
    42

### returns a list

```scheme
(Fn identity (list 1 2))
```
---
    (1 2)

## const

### returns a constant function

```scheme
((Fn const 5) 99)
```
---
    5

## compose

### composes two functions

```scheme
((Fn compose (method-ref Num inc) (method-ref Num inc)) 3)
```
---
    5

### applies right-to-left

```scheme
((Fn compose (fn (_ x) (* x 2)) (method-ref Num inc)) 3)
```
---
    8

## pipe

### pipes two functions left-to-right

```scheme
((Fn pipe (method-ref Num inc) (fn (_ x) (* x 2))) 3)
```
---
    8

## curry

### partially applies first argument

```scheme
((Fn curry + 10) 5)
```
---
    15

## flip

### swaps argument order

```scheme
((Fn flip -) 3 10)
```
---
    7

## tap

### returns original value

```scheme
((Fn tap (fn (_ x) x)) 42)
```
---
    42

## complement

### negates a predicate

```scheme
((Fn complement (method-ref Num even?)) 3)
```
---
    #t

### negates a true result

```scheme
(if ((Fn complement (method-ref Num even?)) 4) "odd" "even")
```
---
    "even"

## partial

### partially applies one argument

```scheme
((Fn partial * 3) 4)
```
---
    12

### partially applies with subtract

```scheme
((Fn partial - 100) 30)
```
---
    70

## juxt

### applies multiple functions

```scheme
((Fn juxt (method-ref Num inc) (method-ref Num dec)) 5)
```
---
    (6 4)

## both

### returns #t when both pass

```scheme
((Fn both (method-ref Num positive?) (method-ref Num even?)) 4)
```
---
    #t

### returns nil when one fails

```scheme
(if ((Fn both (method-ref Num positive?) (method-ref Num even?)) 3) "y" "n")
```
---
    "n"

## either

### returns #t when one passes

```scheme
((Fn either (method-ref Num positive?) (method-ref Num even?)) -2)
```
---
    #t

### returns nil when both fail

```scheme
(if ((Fn either (method-ref Num positive?) (method-ref Num even?)) -3) "y" "n")
```
---
    "n"

## all-pass

### all predicates pass

```scheme
((Fn all-pass (list (method-ref Num positive?) (method-ref Num even?))) 4)
```
---
    #t

### fails when one fails

```scheme
(if ((Fn all-pass (list (method-ref Num positive?) (method-ref Num even?))) 3) "y" "n")
```
---
    "n"

## any-pass

### one predicate passes

```scheme
((Fn any-pass (list (method-ref Num negative?) (method-ref Num even?))) 4)
```
---
    #t

### fails when all fail

```scheme
(if ((Fn any-pass (list (method-ref Num negative?) (method-ref Num even?))) 3) "y" "n")
```
---
    "n"


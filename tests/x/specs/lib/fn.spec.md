# @weight 1
## identity

### returns its argument

```x
(Fn identity 42)
```
---
    42

### returns a list

```x
(Fn identity (list 1 2))
```
---
    (1 2)

## const

### returns a constant function

```x
((Fn const 5) 99)
```
---
    5

## compose

### composes two functions

```x
((Fn compose (method-ref Num inc) (method-ref Num inc)) 3)
```
---
    5

### applies right-to-left

```x
((Fn compose (fn (_ x) (* x 2)) (method-ref Num inc)) 3)
```
---
    8

## pipe

### pipes two functions left-to-right

```x
((Fn pipe (method-ref Num inc) (fn (_ x) (* x 2))) 3)
```
---
    8

## curry

### partially applies first argument

```x
((Fn curry + 10) 5)
```
---
    15

## flip

### swaps argument order

```x
((Fn flip -) 3 10)
```
---
    7

## tap

### returns original value

```x
((Fn tap (fn (_ x) x)) 42)
```
---
    42

## complement

### negates a predicate

```x
((Fn complement (method-ref Num even?)) 3)
```
---
    #t

### negates a true result

```x
(if ((Fn complement (method-ref Num even?)) 4) "odd" "even")
```
---
    "even"

## partial

### partially applies one argument

```x
((Fn partial * 3) 4)
```
---
    12

### partially applies with subtract

```x
((Fn partial - 100) 30)
```
---
    70

## juxt

### applies multiple functions

```x
((Fn juxt (method-ref Num inc) (method-ref Num dec)) 5)
```
---
    (6 4)

## both

### returns #t when both pass

```x
((Fn both (method-ref Num positive?) (method-ref Num even?)) 4)
```
---
    #t

### returns nil when one fails

```x
(if ((Fn both (method-ref Num positive?) (method-ref Num even?)) 3) "y" "n")
```
---
    "n"

## either

### returns #t when one passes

```x
((Fn either (method-ref Num positive?) (method-ref Num even?)) -2)
```
---
    #t

### returns nil when both fail

```x
(if ((Fn either (method-ref Num positive?) (method-ref Num even?)) -3) "y" "n")
```
---
    "n"

## all-pass

### all predicates pass

```x
((Fn all-pass (list (method-ref Num positive?) (method-ref Num even?))) 4)
```
---
    #t

### fails when one fails

```x
(if ((Fn all-pass (list (method-ref Num positive?) (method-ref Num even?))) 3) "y" "n")
```
---
    "n"

## any-pass

### one predicate passes

```x
((Fn any-pass (list (method-ref Num negative?) (method-ref Num even?))) 4)
```
---
    #t

### fails when all fail

```x
(if ((Fn any-pass (list (method-ref Num negative?) (method-ref Num even?))) 3) "y" "n")
```
---
    "n"


## identity

### returns its argument

```scheme
(identity 42)
```
---
    42

### returns a list

```scheme
(identity (list 1 2))
```
---
    (1 2)

## const

### returns a constant function

```scheme
((const 5) 99)
```
---
    5

## compose

### composes two functions

```scheme
((compose inc inc) 3)
```
---
    5

### applies right-to-left

```scheme
((compose (fn (_ x) (* x 2)) inc) 3)
```
---
    8

## pipe

### pipes two functions left-to-right

```scheme
((pipe inc (fn (_ x) (* x 2))) 3)
```
---
    8

## curry

### partially applies first argument

```scheme
((curry + 10) 5)
```
---
    15

## flip

### swaps argument order

```scheme
((flip -) 3 10)
```
---
    7

## tap

### returns original value

```scheme
((tap identity) 42)
```
---
    42

## complement

### negates a predicate

```scheme
((List complement even?) 3)
```
---
    #t

### negates a true result

```scheme
(if ((List complement even?) 4) "odd" "even")
```
---
    "even"

## partial

### partially applies one argument

```scheme
((partial * 3) 4)
```
---
    12

### partially applies with subtract

```scheme
((partial - 100) 30)
```
---
    70

## juxt

### applies multiple functions

```scheme
((List juxt inc dec) 5)
```
---
    (6 4)

## both

### returns #t when both pass

```scheme
((List both positive? even?) 4)
```
---
    #t

### returns nil when one fails

```scheme
(if ((List both positive? even?) 3) "y" "n")
```
---
    "n"

## either

### returns #t when one passes

```scheme
((List either positive? even?) -2)
```
---
    #t

### returns nil when both fail

```scheme
(if ((List either positive? even?) -3) "y" "n")
```
---
    "n"

## all-pass

### all predicates pass

```scheme
((List all-pass (list positive? even?)) 4)
```
---
    #t

### fails when one fails

```scheme
(if ((List all-pass (list positive? even?)) 3) "y" "n")
```
---
    "n"

## any-pass

### one predicate passes

```scheme
((List any-pass (list negative? even?)) 4)
```
---
    #t

### fails when all fail

```scheme
(if ((List any-pass (list negative? even?)) 3) "y" "n")
```
---
    "n"

